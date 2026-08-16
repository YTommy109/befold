import { z } from 'zod'

import { CHANNELS } from './lib/github'
import { RECORDED_HOSTS } from './lib/hosts'

/**
 * 記録するイベント種別。
 *
 * `github_fallback` と `legacy_redirect` は製品の指標ではなく運用の観測
 * （ADR 0007 の「旧ホストと GitHub 経路を止めてよいか」の判断材料）。
 * ダッシュボードのカード・グラフには出さず、専用のセクションで見る
 * （`src/analytics.ts` の `OPERATIONAL_KINDS`）。
 *
 * `legacy_redirect` を visit として記録しない。旧ホストの HTML ページは新ドメインへ
 * 301 で送るため、visit にすると 301 を追った先の正規ホスト側の visit と二重に
 * 数えられ、ページアクセス数が水増しされる。
 */
export const eventKindSchema = z.enum([
  'visit',
  'download',
  'update_check',
  'github_fallback',
  'legacy_redirect',
])

export type EventKind = z.infer<typeof eventKindSchema>

/**
 * ダウンロードの発生経路。
 *
 * `lp` は配布 LP の /download 経由、`sparkle` は appcast の enclosure
 * （自動アップデート）経由。成果物を R2 へ移して enclosure を Worker 配下に
 * すると、両者が同じ kind='download' として記録されるようになる。
 * 新規獲得と既存ユーザの更新は性質が違うので、集計時に分離できるようにする。
 */
export const downloadSourceSchema = z.enum(['lp', 'sparkle'])

export type DownloadSource = z.infer<typeof downloadSourceSchema>

/**
 * visit として計上するページ。
 *
 * 生のパスを入れない。`/dl/:tag/:file` のようにパスがパラメータを含む経路が
 * あるため、URL から導出するとカーディナリティが発散し、内訳が読めなくなる。
 * ここに列挙したページを、呼び出し側が明示して渡す。
 */
export const pageSchema = z.enum(['/', '/features'])

export type Page = z.infer<typeof pageSchema>

/**
 * ブラウザの言語設定（Accept-Language の第一タグ）。
 *
 * 実際に読まれた言語ではない。詳細は `lib/lang.ts` の `summarizeLang`。
 */
export const browserLangSchema = z.enum(['ja', 'en', 'other'])

export type BrowserLang = z.infer<typeof browserLangSchema>

/**
 * 実際に配信したページの言語（TASK-496）。
 *
 * `browserLang` と対にして読む。前者は「求めた言語」（Accept-Language）、こちらは
 * 「実際に出した言語」で、両方あって初めて「英語を求めて来た人が英語ページへ
 * 辿り着けたか」が測れる。値は配信したビューの言語そのもので、URL 文字列からは
 * 導出しない（`lib/pages.ts` の `SITE_PAGES` が唯一の対応表）。
 */
export const displayLangSchema = z.enum(['ja', 'en'])

export type DisplayLang = z.infer<typeof displayLangSchema>

/**
 * R2 に目的のオブジェクトが無く GitHub へ落ちた経路。
 *
 * `appcast` は appcast のプロキシ、`dmg` は成果物の 302、`release-api` は /download が
 * R2 の最新ポインタを読めず GitHub API へ落ちた場合。3 つを分けるのは、止められる
 * 順序が違うため（appcast は出荷済みアプリが依存し、dmg は過去タグの配置漏れで、
 * release-api は移行前の名残）。
 */
export const fallbackRouteSchema = z.enum(['appcast', 'dmg', 'release-api'])

export type FallbackRoute = z.infer<typeof fallbackRouteSchema>

/**
 * 記録するリクエスト先ホスト。列挙は `lib/hosts.ts` が唯一の定義元。
 *
 * 分類を通さない生のホスト名はここで落ちる。任意の値を送れる Host ヘッダを
 * そのまま列へ入れるとカーディナリティが発散するため（`classifyHost`）。
 */
export const hostSchema = z.enum(RECORDED_HOSTS)

/**
 * 配布チャネル。列挙は `lib/github.ts` の `CHANNELS` が唯一の定義元。
 *
 * ここで値を書き写さない。appcast の配信先とダッシュボードのチャネル別系列が
 * 同じ列挙から出ることを保証する（片方だけ増えると、新チャネルの記録は残るのに
 * 集計の系列が無く、画面のどこにも出ない）。
 */
export const channelSchema = z.enum(CHANNELS)

export type Channel = z.infer<typeof channelSchema>

/** D1 の events テーブルに INSERT する 1 行分の形状。 */
export const eventSchema = z.object({
  timestamp: z.number().int().nonnegative(),
  kind: eventKindSchema,
  version: z.string().nullable().default(null),
  channel: channelSchema.nullable().default(null),
  country: z.string().nullable().default(null),
  os: z.string().nullable().default(null),
  uaSummary: z.string().nullable().default(null),
  visitorToken: z.string().nullable().default(null),
  referrer: z.string().nullable().default(null),
  asOrg: z.string().nullable().default(null),
  source: downloadSourceSchema.nullable().default(null),
  page: pageSchema.nullable().default(null),
  browserLang: browserLangSchema.nullable().default(null),
  displayLang: displayLangSchema.nullable().default(null),
  host: hostSchema.nullable().default(null),
  fallback: fallbackRouteSchema.nullable().default(null),
  /**
   * 稼働中のアプリバージョン（TASK-491.1）。
   *
   * `version` とは意味が違う——あちらは download の対象タグ、こちらは「今どの
   * バージョンが動いているか」。`kind` に依らず UA から導出するため、
   * `fallback` のような kind との対応を強制する refine は置かない。
   */
  appVersion: z.string().nullable().default(null),
})
  /**
   * `fallback` は `github_fallback` 専用。対応をここで強制する。
   *
   * doc コメントだけでは守られない。他の kind に fallback が付くと、
   * ダッシュボードの「GitHub フォールバックの内訳」が実際には起きていない
   * 経路を数え、逆に github_fallback で fallback が抜けると内訳から消える。
   * どちらも値としては成立してしまうので、parse で落とす。
   */
  .refine((event) => (event.fallback !== null) === (event.kind === 'github_fallback'), {
    message: 'fallback は kind=github_fallback のときだけ指定する',
    path: ['fallback'],
  })

export type AnalyticsEvent = z.infer<typeof eventSchema>
