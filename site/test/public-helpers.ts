import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { vi } from 'vitest'

import app from '../src/index'

export const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 Safari/605.1.15'
export const IP = '203.0.113.5'
export const APPCAST_XML =
  '<?xml version="1.0"?><rss><channel><title>befold</title></channel></rss>'
export const DEVELOP_XML =
  '<?xml version="1.0"?><rss><channel><title>befold-dev</title></channel></rss>'

/** テストの既定オリジン。ホストに依存しない振る舞いはこれで確かめる。 */
export const DEFAULT_ORIGIN = 'https://befold.example'

/** 実リクエストと同じヘッダ構成でルートを叩き、waitUntil の完了まで待つ。 */
export async function call(
  path: string,
  headers: Record<string, string> = {},
  cf?: IncomingRequestCfProperties,
  origin: string = DEFAULT_ORIGIN,
): Promise<Response> {
  const request = new Request(`${origin}${path}`, {
    headers: { 'User-Agent': UA, 'CF-Connecting-IP': IP, 'CF-IPCountry': 'JP', ...headers },
    redirect: 'manual',
    ...(cf === undefined ? {} : { cf }),
  })
  const ctx = createExecutionContext()
  const response = await app.fetch(request, env, ctx)
  await waitOnExecutionContext(ctx)
  return response
}

export type EventRow = {
  kind: string
  version: string | null
  channel: string | null
  country: string | null
  os: string | null
  ua_summary: string | null
  visitor_token: string | null
  referrer: string | null
  as_org: string | null
  source: string | null
  page: string | null
  browser_lang: string | null
  display_lang: string | null
  host: string | null
  fallback: string | null
  app_version: string | null
}

/**
 * `<body>` 以降だけを返す。
 *
 * 「相手言語が出ない」を HTML 全体で判定すると、head の
 * `<link rel="alternate" hreflang="en">` や `og:locale:alternate` に引っかかる。
 * これらは相手言語を指すのが正しい状態で、本文の言語混在とは別物。
 */
export function bodyOf(html: string): string {
  const index = html.indexOf('<body>')
  return index === -1 ? html : html.slice(index)
}

/**
 * 最後に記録されたイベント。kind を渡すとその種別に絞る。
 *
 * 1 リクエストが 2 件記録することがある（R2 ミスの `github_fallback` と、その
 * 経路本来の download / update_check）。絞り込みを既定で入れて隠すのではなく、
 * どちらを見たいのかを呼び出し側に書かせる。
 */
export async function latestEvent(kind?: string): Promise<EventRow | null> {
  const columns =
    'SELECT kind, version, channel, country, os, ua_summary, visitor_token, referrer, as_org,' +
    ' source, page, browser_lang, display_lang, host, fallback, app_version FROM events'
  const query = kind === undefined ? columns : `${columns} WHERE kind = ?`

  return await env.DB.prepare(`${query} ORDER BY id DESC LIMIT 1`)
    .bind(...(kind === undefined ? [] : [kind]))
    .first<EventRow>()
}

/** 上流（GitHub）への fetch を URL 単位で差し替える。 */
export function mockUpstream(responses: Record<string, Response>): void {
  vi.stubGlobal('fetch', (input: RequestInfo | URL) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
    const response = responses[url]
    if (response === undefined) throw new Error(`unexpected fetch: ${url}`)
    return Promise.resolve(response)
  })
}

export const LATEST_RELEASE_URL = 'https://api.github.com/repos/YTommy109/befold/releases/latest'
export const RELEASES_LIST_URL =
  'https://api.github.com/repos/YTommy109/befold/releases?per_page=100'
export const APPCAST_URL =
  'https://github.com/YTommy109/befold/releases/download/appcast/appcast.xml'
export const APPCAST_DEVELOP_URL =
  'https://github.com/YTommy109/befold/releases/download/appcast/appcast-develop.xml'

/** 各テストファイルが `afterEach` に登録する後始末。 */
export async function cleanupAfterEach(): Promise<void> {
  vi.unstubAllGlobals()
  await env.DB.prepare('DELETE FROM events').run()

  const { objects } = await env.DIST.list()
  await Promise.all(objects.map((object) => env.DIST.delete(object.key)))

  // caches.default はテスト間で共有される。前のテストの appcast が残ると
  // 次のテストが R2 を読まずにそれを返してしまう。
  await Promise.all(
    ['/appcast.xml', '/appcast-develop.xml'].map((path) =>
      caches.default.delete(`https://befold.example${path}`),
    ),
  )
}
