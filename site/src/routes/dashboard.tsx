import { Hono } from 'hono'
import { basicAuth } from 'hono/basic-auth'
import type { AppEnv } from '../index'
import { STREAM_LIMIT, eventsAfter, maxEventId, summarize } from '../analytics'
import { Dashboard, renderSummarySections } from '../views/dashboard'

/** SSE のポーリング間隔と、1 接続あたりの最大保持時間。 */
const POLL_INTERVAL_MS = 2500
const MAX_STREAM_MS = 10 * 60 * 1000

export const dashboardRoutes = new Hono<AppEnv>()

/**
 * ダッシュボードを所有者だけに限定する。
 *
 * 最終形は Cloudflare Access（新ドメイン befold.degino.com の /dashboard と
 * /dashboard/* を self-hosted アプリケーションで保護し、Worker 側で Access の
 * JWT を検証する）で、Basic 認証はそこへ移るまでの暫定（ADR 0007 の決定 5）。
 * かつてここには「workers.dev には Access を設定できない」と書かれていたが、
 * これは誤り。Cloudflare のドキュメント（Workers「workers.dev」の
 * Manage access to `workers.dev`）は workers.dev URL へ Access を有効化する
 * 手順を明記している。旧ホストで Access を張らないのは技術的な不可能性では
 * なく、保護面を 1 つに畳むという判断による。
 *
 * パスワードは `wrangler secret put DASHBOARD_PASSWORD` で設定し、コードには
 * 持たない。未設定のまま公開されると素通しになるので、その場合は 503 で閉じる。
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
          // カーソルは生の最大 id で進める。eventsAfter はロボットの巡回を除いて
          // 返すため、返った行だけで再開位置を決めると、ボットしか来なかった周期で
          // 位置が進まず、集計（ロボットの数を含む）も再描画されない。
          const latestId = await maxEventId(db)
          const events = await eventsAfter(db, lastId)
          for (const event of events) {
            controller.enqueue(
              encoder.encode(`id: ${event.id}\nevent: event\ndata: ${JSON.stringify(event)}\n\n`),
            )
          }
          const arrived = latestId > lastId
          // 上限まで返った周期は未読の行が残っているので、最後に読んだ位置で止める。
          // それ以外は、maxEventId を取った後に入った行も読んで流しているため、
          // 大きいほうまで進めないと同じ行を次の周期でもう一度送ってしまう。
          const lastEventId = events.at(-1)?.id ?? 0
          lastId =
            events.length === STREAM_LIMIT ? lastEventId : Math.max(latestId, lastEventId)
          // 集計は summarize() の再実行結果をそのまま流す。D1 クエリを伴うため
          // 新着があったポーリング周期でのみ行う。data 行は改行を含められないので
          // HTML は JSON 文字列にして送る。
          if (arrived) {
            const html = renderSummarySections(await summarize(db, Date.now()))
            controller.enqueue(encoder.encode(`event: summary\ndata: ${JSON.stringify(html)}\n\n`))
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
