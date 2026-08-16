import { Hono } from 'hono'

import { recordEvent } from './events'
import { REDIRECT_TARGET_ORIGIN, REDIRECTED_PATHS } from './lib/hosts'
import { dashboardRoutes } from './routes/dashboard'
import { publicRoutes } from './routes/public'
import { notFoundResponse } from './views/not-found'

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
 *
 * 301 は `legacy_redirect` として記録する。旧ホストの HTML ページに来た人間は
 * 全員ここで送り出されるため、記録しないと旧ホストへの人間のアクセスが
 * ダッシュボードから完全に消える（ADR 0007 の停止条件の判断材料になる）。
 * visit として記録してはならない——301 を追った先の正規ホストでも visit が
 * 記録され、ページアクセス数が二重に数えられる。
 */
app.use('*', async (c, next) => {
  const url = new URL(c.req.url)
  const target = REDIRECT_TARGET_ORIGIN.get(url.host)

  if (target === undefined || !REDIRECTED_PATHS.has(url.pathname)) {
    return await next()
  }

  recordEvent(c, { kind: 'legacy_redirect' })
  return c.redirect(`${target}${url.pathname}${url.search}`, 301)
})

app.get('/healthz', (c) => c.text('ok'))
app.route('/dashboard', dashboardRoutes)
app.route('/', publicRoutes)

/**
 * Worker がルートを持たないパスは静的アセット（public/）に委譲し、そこにも
 * 無ければ LP と同じ意匠の 404 ページを返す（TASK-497）。
 *
 * **アセットの応答が 404 のときだけ差し替える。** 先に自前の 404 を返す形にすると
 * /style.css・/images/* が配信されなくなる。判定は「ASSETS が 404 を返したか」と
 * いう事実で行い、パスの形（拡張子の有無・/en 接頭辞）からは推測しない。
 *
 * 旧ホストの /dashboard はここへ来ない（routes/dashboard.tsx が確定的に 404 を
 * 返す）。あちらは人間向けのページではないので素の text のままでよい。
 */
app.notFound(async (c) => {
  const asset = await c.env.ASSETS.fetch(c.req.raw)
  return asset.status === 404 ? await notFoundResponse(c) : asset
})

export default app
