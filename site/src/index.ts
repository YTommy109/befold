import { Hono } from 'hono'

/**
 * Worker のバインディング型。`Env` は wrangler types が
 * worker-configuration.d.ts に生成する（wrangler.toml が唯一の定義元）。
 */
export type AppEnv = { Bindings: Env }

const app = new Hono<AppEnv>()

// 公開ルート（LP / download / appcast）とダッシュボードは TASK-182.2 以降で実装する。
app.get('/healthz', (c) => c.text('ok'))

export default app
