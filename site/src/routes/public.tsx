import { Hono } from 'hono'
import type { Context } from 'hono'
import type { AppEnv } from '../index'
import { recordEvent } from '../events'
import { Landing } from '../views/landing'
import { APPCAST_UPSTREAM, latestDMG, RELEASES_LATEST_URL, type Channel } from '../lib/github'

export const publicRoutes = new Hono<AppEnv>()

publicRoutes.get('/', (c) => {
  recordEvent(c, { kind: 'visit' })
  return c.html(<Landing origin={new URL(c.req.url).origin} />)
})

publicRoutes.get('/download', async (c) => {
  const dmg = await latestDMG()
  recordEvent(c, { kind: 'download', version: dmg?.version ?? null, channel: 'stable' })
  // アセットを解決できないときも導線は途切れさせず、リリース一覧へ送る。
  return c.redirect(dmg?.url ?? RELEASES_LATEST_URL, 302)
})

// クロールさせるのは公開 LP だけ。/dashboard は認証付きの管理画面、
// /healthz と appcast は人間向けのページではないので列挙しない。
publicRoutes.get('/robots.txt', (c) => {
  const { origin } = new URL(c.req.url)
  const lines = ['User-agent: *', 'Allow: /', 'Disallow: /dashboard', '']
  const body = `${lines.join('\n')}Sitemap: ${origin}/sitemap.xml\n`
  return c.text(body, 200, { 'Cache-Control': 'public, max-age=3600' })
})

publicRoutes.get('/sitemap.xml', (c) => {
  const { origin } = new URL(c.req.url)
  const body =
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    `  <url><loc>${origin}/</loc><changefreq>weekly</changefreq><priority>1.0</priority></url>\n` +
    '</urlset>\n'
  return new Response(body, {
    status: 200,
    headers: {
      'Content-Type': 'application/xml; charset=utf-8',
      'Cache-Control': 'public, max-age=3600',
    },
  })
})

publicRoutes.get('/appcast.xml', (c) => proxyAppcast(c, 'stable'))
publicRoutes.get('/appcast-develop.xml', (c) => proxyAppcast(c, 'develop'))

/** GitHub 上の appcast をそのまま返しつつ update_check を記録する。 */
async function proxyAppcast(c: Context<AppEnv>, channel: Channel): Promise<Response> {
  recordEvent(c, { kind: 'update_check', channel })

  const upstream = await fetch(APPCAST_UPSTREAM[channel], {
    headers: { 'User-Agent': 'befold-site' },
    cf: { cacheTtl: 300, cacheEverything: true },
  }).catch(() => null)

  if (upstream === null || !upstream.ok) {
    return c.text('appcast upstream unavailable', 502)
  }

  return new Response(upstream.body, {
    status: 200,
    headers: {
      'Content-Type': 'application/xml; charset=utf-8',
      'Cache-Control': 'public, max-age=300',
    },
  })
}
