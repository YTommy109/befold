import { Hono } from 'hono'
import { dashboardRoutes } from './routes/dashboard'
import { publicRoutes } from './routes/public'

/**
 * Worker のバインディング型。`Env` は wrangler types が
 * worker-configuration.d.ts に生成する（wrangler.toml が唯一の定義元）。
 */
export type AppEnv = { Bindings: Env }

const app = new Hono<AppEnv>()

app.get('/healthz', (c) => c.text('ok'))
app.route('/dashboard', dashboardRoutes)
app.route('/', publicRoutes)

export default app
