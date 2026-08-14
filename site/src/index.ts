import { Hono } from 'hono'
import { REDIRECT_TARGET_ORIGIN, REDIRECTED_PATHS } from './lib/hosts'
import { dashboardRoutes } from './routes/dashboard'
import { publicRoutes } from './routes/public'

/**
 * Worker のバインディング型。`Env` は wrangler types が
 * worker-configuration.d.ts に生成する（wrangler.toml が唯一の定義元）。
 */
export type AppEnv = { Bindings: Env }

const app = new Hono<AppEnv>()

/**
 * 旧 workers.dev ホストの HTML ページだけを新ドメインへ 301 で送る。
 *
 * 対象は `REDIRECTED_PATHS` の**肯定列挙**で、それ以外のパスは素通しする
 * （ADR 0007 の決定 2）。旧ホストは恒久的に生かし続ける必要があり
 * （出荷済みアプリの Sparkle フィードと配信済み appcast の enclosure が
 * 依存している）、「appcast と /dl/ を除く」という否定列挙にすると新しい
 * 機械向けパスを足したときに黙って壊れる。肯定列挙なら列挙漏れは
 * 「リダイレクトされない」= 安全側に倒れる。
 *
 * ルート登録より前に置く。後ろに置くとリダイレクト対象のパスが先に本文を
 * 返してしまい、301 が効かない。
 */
app.use('*', async (c, next) => {
  const url = new URL(c.req.url)
  const target = REDIRECT_TARGET_ORIGIN.get(url.host)

  if (target === undefined || !REDIRECTED_PATHS.has(url.pathname)) {
    return await next()
  }

  return c.redirect(`${target}${url.pathname}${url.search}`, 301)
})

app.get('/healthz', (c) => c.text('ok'))
app.route('/dashboard', dashboardRoutes)
app.route('/', publicRoutes)

// Worker がルートを持たないパスは静的アセット（public/）に委譲する。
app.notFound((c) => c.env.ASSETS.fetch(c.req.raw))

export default app
