import { Hono } from 'hono'
import { basicAuth } from 'hono/basic-auth'
import type { AppEnv } from '../index'
import { eventsAfter, maxEventId, summarize } from '../analytics'
import { Dashboard } from '../views/dashboard'

/** SSE のポーリング間隔と、1 接続あたりの最大保持時間。 */
const POLL_INTERVAL_MS = 2500
const MAX_STREAM_MS = 10 * 60 * 1000

export const dashboardRoutes = new Hono<AppEnv>()

/**
 * ダッシュボードを所有者だけに限定する。
 *
 * 配信先が *.workers.dev（Cloudflare 所有ドメイン）で Cloudflare Access を
 * 設定できないため、Worker 側の Basic 認証で保護する。パスワードは
 * `wrangler secret put DASHBOARD_PASSWORD` で設定し、コードには持たない。
 * 未設定のまま公開されると素通しになるので、その場合は 503 で閉じる。
 */
dashboardRoutes.use('*', async (c, next) => {
  const password = c.env.DASHBOARD_PASSWORD
  if (password === undefined || password.length === 0) {
    return c.text('dashboard password is not configured', 503)
  }

  const auth = basicAuth({ username: c.env.DASHBOARD_USER ?? 'owner', password })
  return await auth(c, next)
})

dashboardRoutes.get('/', async (c) => {
  const summary = await summarize(c.env.DB, Date.now())
  const lastId = await maxEventId(c.env.DB)
  return c.html(<Dashboard summary={summary} lastId={lastId} />)
})

dashboardRoutes.get('/stream', (c) => {
  // 再接続時は Last-Event-ID、初回はクエリの after から再開位置を決める。
  const resumeFrom = c.req.header('Last-Event-ID') ?? c.req.query('after') ?? '0'
  let lastId = Number.parseInt(resumeFrom, 10)
  if (!Number.isFinite(lastId) || lastId < 0) lastId = 0

  const db = c.env.DB
  const encoder = new TextEncoder()
  const deadline = Date.now() + MAX_STREAM_MS

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      controller.enqueue(encoder.encode(': connected\n\n'))

      try {
        while (Date.now() < deadline) {
          for (const event of await eventsAfter(db, lastId)) {
            lastId = event.id
            controller.enqueue(
              encoder.encode(`id: ${event.id}\nevent: event\ndata: ${JSON.stringify(event)}\n\n`),
            )
          }
          // 接続維持用のコメント（プロキシのアイドルタイムアウト対策）。
          controller.enqueue(encoder.encode(': keep-alive\n\n'))
          await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS))
        }
      } catch {
        // クライアント切断や D1 障害では静かに閉じ、ブラウザ側の再接続に任せる。
      } finally {
        controller.close()
      }
    },
  })

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-store',
      Connection: 'keep-alive',
    },
  })
})
