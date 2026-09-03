import { Hono } from 'hono'
import type { Context } from 'hono'

import {
  DASHBOARD_PAGES,
  STREAM_LIMIT,
  eventPage,
  eventsAfter,
  parseEventCursor,
  maxEventId,
  summarizeDelivery,
  summarizeOverview,
  summarizeTraffic,
  summarizeUsers,
} from '../analytics'
import type { DashboardPage } from '../analytics'
import type { AppEnv } from '../index'
import { verifyAccessJwt } from '../lib/access'
import { LEGACY_HOST, LEGACY_STAGING_HOST } from '../lib/hosts'
import {
  DashboardPageShell,
  DeliverySections,
  EventsSections,
  OverviewSections,
  TrafficSections,
  UsersSections,
  renderOverviewSections,
} from '../views/dashboard'

/** SSE のポーリング間隔と、1 接続あたりの最大保持時間。 */
const POLL_INTERVAL_MS = 2500
const MAX_STREAM_MS = 10 * 60 * 1000

/** Access が認証済みリクエストに付ける JWT のヘッダ名。 */
const ACCESS_JWT_HEADER = 'Cf-Access-Jwt-Assertion'

/** ローカル開発でだけ素通しするホスト。 */
const LOCAL_HOSTS: ReadonlySet<string> = new Set(['localhost', '127.0.0.1', '[::1]'])

export const dashboardRoutes = new Hono<AppEnv>()

/**
 * ダッシュボードを所有者だけに限定する。
 *
 * 保護は 2 段で成り立つ（ADR 0007 の決定 5）。
 *
 * 1. Cloudflare Access の self-hosted アプリケーションが `befold.degino.com/dashboard`
 *    と `/dashboard/*` の 2 本を保護する（ワイルドカードは親パスを含まないため
 *    2 本必要）。
 * 2. Worker 側が `Cf-Access-Jwt-Assertion` を検証する。Access を張っても Worker が
 *    素通しでは、Access を経由しない経路で無防備になる。
 *
 * 旧ホスト（workers.dev）では 404 を返す。旧ホストは出荷済みアプリの更新経路の
 * ために恒久的に生かすが（同決定 1）、ダッシュボードは新ドメイン専用とし、
 * 保護面を 1 つに畳む。301 で送らないのは、保護対象の入口を 2 つに増やさない
 * ため。
 *
 * かつてここは Basic 認証（シークレット `DASHBOARD_PASSWORD`）だった。当時の
 * コメントは「workers.dev には Access を設定できない」を根拠に挙げていたが、
 * これは誤り（Cloudflare のドキュメントは workers.dev URL への Access 有効化
 * 手順を明記している）。旧ホストで Access を張らないのは技術的な不可能性では
 * なく、上の「保護面を 1 つに畳む」という判断による。
 */
dashboardRoutes.use('*', async (c, next) => {
  const host = new URL(c.req.url).host

  if (host === LEGACY_HOST || host === LEGACY_STAGING_HOST) {
    // ASSETS への委譲（app.notFound）に落とさず、ここで確定的に 404 を返す。
    return c.text('not found', 404)
  }

  const teamDomain = c.env.ACCESS_TEAM_DOMAIN
  const aud = c.env.ACCESS_AUD
  if (
    teamDomain === undefined ||
    teamDomain.length === 0 ||
    aud === undefined ||
    aud.length === 0
  ) {
    // 設定が無い状態では閉じる。素通しにすると、設定漏れが「動いている」形で
    // 表に出てしまう。ローカル開発（wrangler dev）だけは、ホストも
    // localhost であることを併せて確かめたうえで通す。設定済みの本番では
    // ホストに関わらずこの分岐に入らない。
    if (LOCAL_HOSTS.has(host.split(':')[0] ?? '')) return await next()
    return c.text('Cloudflare Access is not configured', 503)
  }

  const token = c.req.header(ACCESS_JWT_HEADER)
  if (token === undefined || token.length === 0) {
    return c.text('missing Cloudflare Access assertion', 401)
  }

  const claims = await verifyAccessJwt(token, { teamDomain, aud })
  if (claims === undefined) {
    return c.text('invalid Cloudflare Access assertion', 403)
  }

  return await next()
})

/**
 * 面ごとの描画。**面の追加はここへ 1 エントリ足すだけで済ませない。**
 *
 * 実体は `DASHBOARD_PAGES`（analytics.ts）で、ルートの生成もナビゲーションも
 * クエリ本数の上限テストもその配列を読む。ここは `Record<DashboardPageKey, ...>`
 * なので、面を足して描画を書き忘れると型で落ちる。
 */
const RENDERERS: Record<
  DashboardPage['key'],
  (c: Context<AppEnv>, page: DashboardPage) => Promise<Response>
> = {
  overview: async (c, page) => {
    const summary = await summarizeOverview(c.env.DB, Date.now())
    // 概要面だけが SSE に接続する。lastId を渡すことがその意思表示になる。
    const lastId = await maxEventId(c.env.DB)
    return c.html(
      <DashboardPageShell page={page} windowDays={summary.windowDays} lastId={lastId}>
        <OverviewSections summary={summary} />
      </DashboardPageShell>,
    )
  },
  users: async (c, page) => {
    const summary = await summarizeUsers(c.env.DB, Date.now())
    return c.html(
      <DashboardPageShell page={page} windowDays={summary.windowDays}>
        <UsersSections summary={summary} />
      </DashboardPageShell>,
    )
  },
  traffic: async (c, page) => {
    const summary = await summarizeTraffic(c.env.DB)
    return c.html(
      <DashboardPageShell page={page}>
        <TrafficSections summary={summary} />
      </DashboardPageShell>,
    )
  },
  delivery: async (c, page) => {
    const summary = await summarizeDelivery(c.env.DB, Date.now())
    return c.html(
      <DashboardPageShell page={page}>
        <DeliverySections summary={summary} />
      </DashboardPageShell>,
    )
  },
  events: async (c, page) => {
    // ページ送りの基準はクエリから読む。読めない値は基準無し（最新のページ）に
    // 倒すので、URL を手で書き換えても 500 にはならない。
    const cursor = parseEventCursor({ before: c.req.query('before'), after: c.req.query('after') })
    const events = await eventPage(c.env.DB, cursor)
    return c.html(
      <DashboardPageShell page={page}>
        <EventsSections page={events} />
      </DashboardPageShell>,
    )
  },
}

for (const page of DASHBOARD_PAGES) {
  dashboardRoutes.get(page.path, async (c) => await RENDERERS[page.key](c, page))
}

dashboardRoutes.get('/stream', (c) => {
  // 再接続時は Last-Event-ID、初回はクエリの after から再開位置を決める。
  const resumeFrom = c.req.header('Last-Event-ID') ?? c.req.query('after') ?? '0'
  // parseInt ではなく Number を使う。'12abc' のような値を 12 として受け取らず
  // NaN にして下の判定で 0 へ倒すため（再開位置には自前で発行した id しか来ない）。
  let lastId = Math.trunc(Number(resumeFrom))
  if (!Number.isFinite(lastId) || lastId < 0) lastId = 0

  const db = c.env.DB
  const encoder = new TextEncoder()
  const deadline = Date.now() + MAX_STREAM_MS

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      controller.enqueue(encoder.encode(': connected\n\n'))

      try {
        // ポーリングは 1 周ずつ順に進める。await を並行化する余地は無く（次の周期の
        // 開始位置が前の周期の結果で決まる）、間隔を空けること自体が目的なので、
        // このループでは no-await-in-loop を止める。
        /* oxlint-disable eslint/no-await-in-loop */
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
          lastId = events.length === STREAM_LIMIT ? lastEventId : Math.max(latestId, lastEventId)
          // 集計は summarize() の再実行結果をそのまま流す。D1 クエリを伴うため
          // 新着があったポーリング周期でのみ行う。data 行は改行を含められないので
          // HTML は JSON 文字列にして送る。
          if (arrived) {
            const html = renderOverviewSections(await summarizeOverview(db, Date.now()))
            controller.enqueue(encoder.encode(`event: summary\ndata: ${JSON.stringify(html)}\n\n`))
          }
          // 接続維持用のコメント（プロキシのアイドルタイムアウト対策）。
          controller.enqueue(encoder.encode(': keep-alive\n\n'))
          await new Promise((resolve) => {
            setTimeout(resolve, POLL_INTERVAL_MS)
          })
        }
        /* oxlint-enable eslint/no-await-in-loop */
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
