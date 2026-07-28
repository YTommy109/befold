import { Hono } from 'hono'
import type { AppEnv } from '../index'
import { eventsAfter, maxEventId, summarize } from '../analytics'
import { Dashboard } from '../views/dashboard'

/** SSE のポーリング間隔と、1 接続あたりの最大保持時間。 */
const POLL_INTERVAL_MS = 2500
const MAX_STREAM_MS = 10 * 60 * 1000

export const dashboardRoutes = new Hono<AppEnv>()

/**
 * Cloudflare Access の通過を確認する。
 *
 * 認可そのものは Access のポリシー（所有者メールのみ許可）が担い、Worker は
 * ポリシー内容を持たない。ここで見るのは Access が付与する JWT ヘッダの有無だけで、
 * Access を経由しない経路（*.workers.dev への直アクセス等）を塞ぐための多層防御。
 */
dashboardRoutes.use('*', async (c, next) => {
  if (c.req.header('Cf-Access-Jwt-Assertion') === undefined) {
    return c.text('forbidden', 403)
  }
  await next()
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
