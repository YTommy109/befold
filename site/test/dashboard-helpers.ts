import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { afterAll, afterEach, beforeAll } from 'vitest'

import type { KindCounts } from '../src/analytics'
import app from '../src/index'
import { installAccessKeys, removeAccessKeys } from './access-helpers'

/** 全指標 0 の件数。合計の算出だけを見たいテストが土台にする。 */
export const EMPTY_COUNTS: KindCounts = {
  visit: 0,
  download: 0,
  update_download: 0,
  archive_download: 0,
  update_check: 0,
  github_fallback: 0,
  legacy_redirect: 0,
}

/** 面ごとの URL。`DASHBOARD_PAGES` の path と対になる。 */
export const PAGE = {
  overview: '/dashboard',
  users: '/dashboard/users',
  traffic: '/dashboard/traffic',
  delivery: '/dashboard/delivery',
  events: '/dashboard/events',
} as const

/**
 * Access が付ける JWT ヘッダ。中身は useDashboardFixtures の beforeAll で埋める（署名に鍵生成が要る）。
 * 参照は同じオブジェクトのまま各テストへ渡るので、ここを書き換えれば全体に効く。
 */
export const AUTH_HEADERS: Record<string, string> = {}

let sign: (claims: Record<string, unknown>) => Promise<string>

/** beforeAll で用意した鍵で JWT を署名する。 */
export const signJwt = (claims: Record<string, unknown>): Promise<string> => sign(claims)

/** テストファイルの先頭で 1 回呼び、Access 鍵の準備と events 表の掃除を登録する。 */
export function useDashboardFixtures(): void {
  beforeAll(async () => {
    const access = await installAccessKeys()
    sign = access.sign
    Object.assign(AUTH_HEADERS, await access.headers())
  })

  afterAll(() => {
    removeAccessKeys()
  })

  afterEach(async () => {
    await env.DB.prepare('DELETE FROM events').run()
  })
}

export async function call(
  path: string,
  headers: Record<string, string> = {},
  overrides: Partial<Env> = {},
  origin = 'https://befold.degino.com',
): Promise<Response> {
  const request = new Request(`${origin}${path}`, { headers })
  const ctx = createExecutionContext()
  const response = await app.fetch(request, { ...env, ...overrides }, ctx)
  await waitOnExecutionContext(ctx)
  return response
}

/** テスト用のイベントを 1 件投入し、その id を返す。 */
export async function seed(
  kind: string,
  extra: {
    version?: string
    country?: string
    os?: string
    visitorDay?: string
    channel?: string | null
    ts?: number
    referrer?: string
    asOrg?: string
    uaSummary?: string
    page?: string
    displayLang?: string
    browserLang?: string
    appVersion?: string | null
    source?: string
  } = {},
): Promise<number> {
  const result = await env.DB.prepare(
    'INSERT INTO events' +
      ' (timestamp, kind, version, channel, country, os, ua_summary, visitor_token, referrer,' +
      ' as_org, page, display_lang, browser_lang, app_version, source)' +
      ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id',
  )
    .bind(
      extra.ts ?? Date.now(),
      kind,
      extra.version ?? null,
      extra.channel === undefined ? 'stable' : extra.channel,
      extra.country ?? null,
      extra.os ?? null,
      extra.uaSummary ?? 'Safari',
      extra.visitorDay ?? 'hash-a',
      extra.referrer ?? null,
      extra.asOrg ?? null,
      extra.page ?? null,
      extra.displayLang ?? null,
      extra.browserLang ?? null,
      extra.appVersion ?? null,
      extra.source ?? null,
    )
    .first<{ id: number }>()

  return result?.id ?? 0
}
