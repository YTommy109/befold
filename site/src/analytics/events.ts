/**
 * イベントストリーム（最新一覧・ページ送り・SSE の新着取得）。
 * 集計は置かない。ボットを除くのは HUMAN_ONLY、カーソルだけは生の id を返す。
 */

import { HUMAN_ONLY } from './access-class'
import { EVENTS_PAGE_LIMIT, STREAM_LIMIT } from './shared'

export type RecentEvent = {
  id: number
  timestamp: number
  kind: string
  version: string | null
  country: string | null
  os: string | null
  /** kind='visit' のときの訪問先ページ。それ以外の kind と、列の導入前の行では null。 */
  page: string | null
}

export const RECENT_LIMIT = 20

/**
 * 最新イベントの SELECT 句。**`recentEvents`・`eventsAfter`・`eventPage` で共有する。**
 *
 * 3 箇所に書き写さない。どれも同じ `RecentEvent` を返す契約だが、`.all<RecentEvent>()`
 * のジェネリクスは実際の列を検査しないため、片方の列を落としてもコンパイルは通り、
 * 初期表示にはあるのに SSE で流れる行にだけ列が無い、という形で静かに壊れる
 * （実測: `eventsAfter` から page を落としても typecheck も既存テストも通った）。
 */
export const RECENT_COLUMNS = 'id, timestamp, kind, version, country, os, page'

/** 最新イベント。SSE の差分取得と同じ形状・同じ絞り込み（人間のみ）で返す。 */
export async function recentEvents(db: D1Database, afterId = 0): Promise<RecentEvent[]> {
  const { results } = await db
    .prepare(
      `SELECT ${RECENT_COLUMNS}
       FROM events
       WHERE id > ? AND ${HUMAN_ONLY}
       ORDER BY id DESC
       LIMIT ?`,
    )
    .bind(afterId, RECENT_LIMIT)
    .all<RecentEvent>()

  return results
}

/**
 * イベント面のページ送りの向きと基準 id。
 *
 * `OFFSET` は使わない。イベントは常に先頭（新しい側）へ挿入されるため、
 * オフセットで数えるとページを送っている間に境界がずれ、同じ行が 2 度出たり
 * 抜けたりする。基準を id に置けば、その後に何件挿入されても
 * 「この id より古い 100 件」は変わらない。
 */
export type EventCursor = { direction: 'older' | 'newer'; id: number }

/**
 * イベント面の 1 ページ分。
 *
 * `olderCursor` / `newerCursor` は、その向きへさらにページがあるときだけ入る
 * （そのまま「前へ」「次へ」のリンクの有無になる）。
 */
export type EventPage = {
  events: RecentEvent[]
  olderCursor?: number
  newerCursor?: number
}

/**
 * イベント面の 1 ページを引く（新しい順、人間のみ）。
 *
 * **上限より 1 件多く引いて、次のページがあるかを同じクエリで確定させる。**
 * 「次があるか」を別のクエリ（COUNT など）で問い直すと 1 面 2 本になり、
 * `query-count.test.ts` の上限の意味が薄れる。
 *
 * 逆向きのカーソルは、そちらから来たことで存在が確定する。`older` へ送った
 * ときの基準 id は直前のページに表示されていた実在の行なので、`newer` を
 * たどれば必ずその行が返る（URL を手で書き換えれば空になりうるが、その場合も
 * 0 件の表示になるだけで壊れない）。
 */
export async function eventPage(db: D1Database, cursor?: EventCursor): Promise<EventPage> {
  const newer = cursor?.direction === 'newer'
  // ボットの除外は `HUMAN_ONLY` を SQL へ直に埋める（条件の書き写しを禁じる
  // 構造ガードが、events を読むクエリの近くにその参照を求めている）。
  // ここで組み立てるのは id の境界だけ。
  const bounded = cursor === undefined ? '' : `id ${newer ? '>' : '<'} ? AND `
  const bindings = cursor === undefined ? [] : [cursor.id]
  // 新しい側へ戻るときだけ昇順で引き、返してから並びを新しい順へ戻す。
  // 降順のまま `id > ?` を引くと、基準のすぐ上ではなく最新側の 100 件が返り、
  // 間のページが飛ぶ。
  const { results } = await db
    .prepare(
      `SELECT ${RECENT_COLUMNS}
       FROM events
       WHERE ${bounded}${HUMAN_ONLY}
       ORDER BY id ${newer ? 'ASC' : 'DESC'}
       LIMIT ?`,
    )
    .bind(...bindings, EVENTS_PAGE_LIMIT + 1)
    .all<RecentEvent>()

  const hasMore = results.length > EVENTS_PAGE_LIMIT
  const page = results.slice(0, EVENTS_PAGE_LIMIT)
  const events = newer ? page.toReversed() : page
  const first = events[0]
  const last = events.at(-1)

  return {
    events,
    // 引いた向きは実件数で確定する。逆向きは、そこから来ていれば必ず存在する。
    olderCursor: (newer ? cursor !== undefined : hasMore) ? last?.id : undefined,
    newerCursor: (newer ? hasMore : cursor !== undefined) ? first?.id : undefined,
  }
}

/**
 * クエリパラメータからページ送りの基準を読む。
 *
 * `parseInt` ではなく `Number` を使う（'12abc' を 12 として受け取らない）。
 * 読めない値・空文字・負の値は基準無し（＝最新のページ）に倒す。空文字を弾かないと
 * `Number('')` が 0 になり、`?after=` だけの URL が「id 0 より新しい」＝最新の
 * ページに化ける（先頭ページと同じ内容だが「新しい側へ戻れる」と表示される）。
 * `before` と `after` が
 * 同時に来たら `before` を採る（片方だけを見て両方指定を静かに無視しない）。
 */
export function parseEventCursor(query: {
  before?: string
  after?: string
}): EventCursor | undefined {
  const before = query.before ?? ''
  const after = query.after ?? ''
  const direction = before.length === 0 && after.length > 0 ? 'newer' : 'older'
  const raw = direction === 'newer' ? after : before
  if (raw.length === 0) return undefined

  const id = Math.trunc(Number(raw))
  if (!Number.isFinite(id) || id < 0) return undefined

  return { direction, id }
}

/**
 * SSE で push する新着イベント（古い順、人間のみ）。
 *
 * 返らなかったボットの行のぶんカーソルが進まないため、呼び出し側はこの戻り値で
 * 再開位置を決めない（`maxEventId` で進める）。上限まで返った周期だけは、
 * まだ読んでいない行が残るので最後の id で止める必要がある。
 */
export async function eventsAfter(db: D1Database, afterId: number): Promise<RecentEvent[]> {
  const { results } = await db
    .prepare(
      `SELECT ${RECENT_COLUMNS}
       FROM events
       WHERE id > ? AND ${HUMAN_ONLY}
       ORDER BY id
       LIMIT ${STREAM_LIMIT}`,
    )
    .bind(afterId)
    .all<RecentEvent>()

  return results
}

/**
 * 現在の最大イベント ID（SSE の開始位置・再開位置）。
 *
 * ボットを含む生の id を返す。集計・表示はボットを除くが、カーソルまで除くと
 * ボットだけが到来した周期で位置が進まず、集計の再描画も起きなくなる。
 */
export async function maxEventId(db: D1Database): Promise<number> {
  const row = await db.prepare('SELECT MAX(id) AS id FROM events').first<{ id: number | null }>()
  return row?.id ?? 0
}
