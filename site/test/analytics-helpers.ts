import { env } from 'cloudflare:test'

import {
  summarizeDelivery,
  summarizeOverview,
  summarizeTraffic,
  summarizeUsers,
} from '../src/analytics'
import type { EventKind } from '../src/schema'

/**
 * 面ごとに分かれた集計をまとめて 1 つのオブジェクトにする（テスト専用）。
 *
 * ここで検証したいのは集計 SQL の振る舞いであって、どの面にどの指標が載るかでは
 * ない。面の割り当ては `test/query-count.test.ts`（本数）と
 * `test/dashboard.test.ts`（表示）が担保する。
 */
export async function summarizeAll(db: D1Database, now: number) {
  const [overview, users, traffic, delivery] = await Promise.all([
    summarizeOverview(db, now),
    summarizeUsers(db, now),
    summarizeTraffic(db),
    summarizeDelivery(db, now),
  ])

  return { ...overview, ...users, ...traffic, ...delivery }
}

/** JST 2026-08-08 12:00（= UTC 03:00）を「現在」とする固定基準。 */
export const NOW = Date.parse('2026-08-08T03:00:00Z')

/** JST の 'YYYY-MM-DD HH:mm' を epoch ms にする（テストの意図を JST で書くため）。 */
export function jst(text: string): number {
  return Date.parse(`${text.replace(' ', 'T')}:00+09:00`)
}

export async function insert(
  ts: number,
  kind: EventKind,
  visitorToken: string | null = 'visitor-a',
  uaSummary: string | null = null,
): Promise<void> {
  await env.DB.prepare(
    'INSERT INTO events (timestamp, kind, visitor_token, ua_summary) VALUES (?, ?, ?, ?)',
  )
    .bind(ts, kind, visitorToken, uaSummary)
    .run()
}

/** 各テストファイルの afterEach に登録して、events を空に戻す。 */
export async function clearEvents(): Promise<void> {
  await env.DB.prepare('DELETE FROM events').run()
}

/** update_check を 1 件入れる（稼働バージョン分布のテスト用）。 */
export async function insertUpdateCheck(options: {
  ts: number
  appVersion: string | null
  channel?: string | null
  visitorToken?: string
  uaSummary?: string | null
  asOrg?: string | null
}): Promise<void> {
  await env.DB.prepare(
    'INSERT INTO events (timestamp, kind, channel, app_version, visitor_token, ua_summary, as_org)' +
      " VALUES (?, 'update_check', ?, ?, ?, ?, ?)",
  )
    .bind(
      options.ts,
      // `?? 'stable'` にしない。明示した null が既定値に化けて、
      // チャネル未記録のケースを検証できなくなる。
      'channel' in options ? options.channel : 'stable',
      options.appVersion,
      options.visitorToken ?? 'visitor-a',
      options.uaSummary ?? 'Sparkle',
      options.asOrg ?? null,
    )
    .run()
}

/**
 * 同日・同チャネルで sparkle 経由のダウンロードを 1 件入れる。
 *
 * 転換率の分子は「確認と更新の両方を持つアクセス元」なので、確認と同じ
 * visitor_token を渡せるようにしてある。
 */
export async function insertSparkleDownload(options: {
  ts: number
  channel?: string | null
  visitorToken?: string
  version?: string
  uaSummary?: string | null
}): Promise<void> {
  await env.DB.prepare(
    'INSERT INTO events (timestamp, kind, source, channel, version, visitor_token, ua_summary)' +
      " VALUES (?, 'download', 'sparkle', ?, ?, ?, ?)",
  )
    .bind(
      options.ts,
      'channel' in options ? options.channel : 'stable',
      options.version ?? 'v1.13.0',
      options.visitorToken ?? 'visitor-a',
      options.uaSummary ?? 'Sparkle',
    )
    .run()
}
