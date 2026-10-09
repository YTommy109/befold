/**
 * ユニークアクセス元の母集団とチャネル別の鍵・表示名。
 * 指標（metrics.ts）とは別の軸で、母集団を混ぜない。クエリ本体は置かない。
 */

import { CHANNELS } from '../lib/github'
import type { Channel } from '../schema'
import type { Count } from './shared'

/**
 * 日別のユニークアクセス元を数える母集団。
 *
 * **母集団を混ぜない。** `visit` はサイトを見に来た人、`update_check_*` は
 * アプリを起動してアップデート確認を飛ばした端末で、意味が違う。合算した
 * 「ユニーク」は、サイトも見てアプリも使った 1 人を 1 と数える一方で、
 * どちらの規模も表さない数になる。
 *
 * チャネルを分けるのは、実測で `update_check` の大半が develop（開発機）だった
 * ため。混ぜると利用者の規模を過大に見積もる。
 *
 * `update_check_unrecorded` は channel 列に値が無い行。0 件でも系列として残す
 * （`foldHosts` と同じ理由で、「まだ 0 だった」と「そもそも数えていない」を
 * 画面上で区別できなくしないため）。
 */
export type UniqueSourceKey = 'visit' | `update_check_${Channel}` | 'update_check_unrecorded'

/**
 * 母集団を SQL の条件式にする。**述語はここだけで組み立てる。**
 *
 * チャネル別の系列は `CHANNELS`（`lib/github.ts` が唯一の定義元）から生成する。
 * 手書きで並べるとチャネルを増やしたときに記録側だけが増え、新チャネルの
 * ユニーク数が画面のどこにも出ないまま落ちる。埋め込む値はこの定数だけで、
 * 外部入力は入らない。
 *
 * `visit` は page で絞らない。「ページビュー」の指標と範囲は同じ（サイト全体）だが、
 * こちらが数えるのは延べ回数ではなくアクセス元の異なり数で、サイトに来た人の規模を
 * 測るもの（当日集計の `uniqueVisitors` も同じ扱い）。
 */
const UNIQUE_SOURCE_FILTERS: Record<UniqueSourceKey, string> = {
  visit: `kind = 'visit'`,
  ...(Object.fromEntries(
    CHANNELS.map((channel) => [
      `update_check_${channel}`,
      `kind = 'update_check' AND channel = '${channel}'`,
    ]),
  ) as Record<`update_check_${Channel}`, string>),
  update_check_unrecorded: `kind = 'update_check' AND channel IS NULL`,
}

/**
 * チャネル別系列の表示名。`Record<Channel, ...>` なので、チャネルを増やすと
 * ここに名前を書くまで型で落ちる（系列だけ無名で増えることがない）。
 */
export const CHANNEL_LABELS: Record<Channel, string> = {
  stable: 'アプリ（stable）',
  develop: 'アプリ（develop）',
}

/** 母集団の並び順と表示名。集計・表示の双方でこの順を使う。 */
export const UNIQUE_SOURCE_LABELS: { key: UniqueSourceKey; label: string }[] = [
  { key: 'visit', label: 'サイト訪問' },
  ...CHANNELS.map((channel) => ({
    key: `update_check_${channel}` as const,
    label: CHANNEL_LABELS[channel],
  })),
  { key: 'update_check_unrecorded', label: 'アプリ（チャネル未記録）' },
]

/**
 * 稼働バージョン分布をチャネルごとに分ける鍵（TASK-491.2）。
 *
 * `channel` に値が無い行は `unrecorded` に入れる。0 件でも表として残すのは
 * `UNIQUE_SOURCE_LABELS` と同じ理由で、「まだ 0 だった」と「そもそも数えて
 * いない」を画面上で区別できなくしないため。
 */
export type RunningVersionKey = Channel | 'unrecorded'

/**
 * チャネル別の表の並び順と表示名。列挙は `CHANNELS` から生成する。
 *
 * 手書きで並べるとチャネルを増やしたときに記録側だけが増え、新チャネルの
 * 稼働バージョンが画面のどこにも出ないまま落ちる（`UNIQUE_SOURCE_LABELS` と
 * 同じ理由）。
 */
export const RUNNING_VERSION_LABELS: { key: RunningVersionKey; label: string }[] = [
  ...CHANNELS.map((channel) => ({
    key: channel as RunningVersionKey,
    label: CHANNEL_LABELS[channel],
  })),
  { key: 'unrecorded', label: 'アプリ（チャネル未記録）' },
]

/** 稼働バージョン分布の鍵。develop を含まない（{@link RUNNING_VERSION_TABLE_LABELS}）。 */
export type RunningVersionTableKey = Exclude<RunningVersionKey, 'develop'>

/**
 * 稼働バージョン分布が対象にするチャネル（`develop` を除いたもの）。
 *
 * develop は作者の開発機（個人 2 台 + 職場 1 台）しか映らない。しかも数える
 * 単位は「アクセス元×日」なので、同じ 1 台が回線や日をまたぐたびに増える。
 * 「他に利用者がいるのか」を読み取る用途には使えず、外部利用者の分布を見る
 * stable の表の隣に並ぶと誤読を招くだけなので、この表からは外す。
 *
 * 転換率（`RUNNING_VERSION_LABELS` を使う「確認 → 更新」）は develop も残す。
 * あちらは自分の機体でも更新経路が生きているかの確認に使える。
 */
export const RUNNING_VERSION_TABLE_LABELS: { key: RunningVersionTableKey; label: string }[] =
  RUNNING_VERSION_LABELS.filter(
    (entry): entry is { key: RunningVersionTableKey; label: string } => entry.key !== 'develop',
  )

/** チャネル別の稼働バージョン分布。 */
export type RunningVersions = Record<RunningVersionTableKey, Count[]>

/** 母集団ごとのユニークアクセス元数。 */
export type UniqueSources = Record<UniqueSourceKey, number>

/**
 * 母集団ごとの日次ユニーク数を取り出す SELECT 句。
 *
 * `COUNT(DISTINCT CASE WHEN ... END)` にするのは、母集団ごとにクエリを引かない
 * ため。日別推移のクエリに相乗りするので発行本数は増えない
 * （`query-count.test.ts` の上限がこの形を守る）。
 */
export const UNIQUE_SOURCE_COLUMNS = uniqueSourceKeys()
  .map(
    (key) =>
      `COUNT(DISTINCT CASE WHEN ${UNIQUE_SOURCE_FILTERS[key]} THEN visitor_token END)` +
      ` AS unique_${key}`,
  )
  .join(', ')

export type UniqueSourceRow = Partial<Record<`unique_${UniqueSourceKey}`, number | null>>

function uniqueSourceKeys(): UniqueSourceKey[] {
  return Object.keys(UNIQUE_SOURCE_FILTERS) as UniqueSourceKey[]
}

export function toUniqueSources(row: UniqueSourceRow | null): UniqueSources {
  const sources = {} as UniqueSources
  for (const key of uniqueSourceKeys()) sources[key] = row?.[`unique_${key}`] ?? 0
  return sources
}
