import { Hono } from 'hono'
import type { Context } from 'hono'
import type { AppEnv } from '../index'
import { recordEvent } from '../events'
import { Landing } from '../views/landing'
import {
  APPCAST_UPSTREAM,
  latestDMG,
  releaseAssetURL,
  RELEASES_LATEST_URL,
  type Channel,
} from '../lib/github'
import { APPCAST_KEY, LATEST_KEY, latestPointerSchema, resolveDMGKey } from '../lib/dist'

export const publicRoutes = new Hono<AppEnv>()

publicRoutes.get('/', (c) => {
  recordEvent(c, { kind: 'visit' })
  return c.html(<Landing origin={new URL(c.req.url).origin} />)
})

/**
 * 配布 LP のダウンロードボタンの宛先。stable の最新 DMG を R2 から返す。
 *
 * `/dl` へリダイレクトはしない。経路ごとに 1 回だけ記録する形にしておかないと、
 * LP からの新規獲得と Sparkle の自動更新が二重計上・混在するため。
 */
publicRoutes.get('/download', async (c) => {
  const pointer = await readLatestPointer(c)

  if (pointer === null) {
    // R2 に最新ポインタが無い（移行前・put 失敗・stable 未リリース）。
    // 導線は途切れさせず、従来どおり GitHub 側の解決へ落とす。
    const dmg = await latestDMG()
    recordEvent(c, { kind: 'download', version: dmg?.version ?? null, channel: 'stable', source: 'lp' })
    return c.redirect(dmg?.url ?? RELEASES_LATEST_URL, 302)
  }

  recordEvent(c, { kind: 'download', version: pointer.version, channel: 'stable', source: 'lp' })
  return serveDMG(c, pointer.version, pointer.file)
})

/**
 * appcast の enclosure が指す配信ルート。Sparkle の自動更新がここを通る。
 *
 * タグとファイル名は `resolveDMGKey` で検証してから R2 キーにする。
 * リクエストのパスをそのままキーへ連結すると、バケット内の配信対象でない
 * オブジェクト（latest.json など）まで読み出せてしまう。
 */
publicRoutes.get('/dl/:tag/:file', async (c) => {
  const tag = c.req.param('tag')
  const file = c.req.param('file')
  const channel = tag.includes('-') ? 'develop' : 'stable'

  recordEvent(c, { kind: 'download', version: tag, channel, source: 'sparkle' })
  return serveDMG(c, tag, file)
})

/** R2 の DMG を返す。無ければ GitHub Releases の同名アセットへ 302 する。 */
async function serveDMG(c: Context<AppEnv>, tag: string, file: string): Promise<Response> {
  const key = resolveDMGKey(tag, file)
  const object = key === null ? null : await c.env.DIST.get(key)

  if (object === null) {
    return c.redirect(releaseAssetURL(tag, file), 302)
  }

  return new Response(object.body, {
    status: 200,
    headers: {
      'Content-Type': 'application/x-apple-diskimage',
      'Content-Length': String(object.size),
      'Content-Disposition': `attachment; filename="${file}"`,
      // 成果物はタグごとに不変なので長期キャッシュしてよい。
      'Cache-Control': 'public, max-age=31536000, immutable',
      ETag: object.httpEtag,
    },
  })
}

/** stable の最新バージョンを指す R2 上のポインタを読む。壊れていれば null。 */
async function readLatestPointer(c: Context<AppEnv>) {
  const object = await c.env.DIST.get(LATEST_KEY)
  if (object === null) return null

  const parsed = latestPointerSchema.safeParse(await object.json().catch(() => null))
  return parsed.success ? parsed.data : null
}

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

/**
 * appcast を返しつつ update_check を記録する。
 *
 * R2 を正とし、そこに無いときだけ GitHub をプロキシする。フォールバックは
 * 移行期の経路であって恒常的な二重の真実ではない（リリースワークフローは
 * R2 への put が失敗したらジョブごと失敗する）。
 *
 * 応答は caches.default に 300 秒入れる。Cache-Control だけではクライアント／
 * 中間キャッシュにしか効かず、アップデートチェックのたびに R2 のクラス B
 * 操作が発生するため。記録はキャッシュ判定より前に必ず行う（先にキャッシュを
 * 返すとアップデート確認数が過小になる）。
 */
async function proxyAppcast(c: Context<AppEnv>, channel: Channel): Promise<Response> {
  recordEvent(c, { kind: 'update_check', channel })

  const cacheKey = new Request(new URL(c.req.url).toString(), { method: 'GET' })
  const cached = await caches.default.match(cacheKey)
  if (cached !== undefined) return cached

  const response = await loadAppcast(c, channel)
  if (response.status === 200) {
    c.executionCtx.waitUntil(caches.default.put(cacheKey, response.clone()))
  }
  return response
}

/** appcast の本体を R2（無ければ GitHub）から読む。キャッシュ判定は呼び出し側。 */
async function loadAppcast(c: Context<AppEnv>, channel: Channel): Promise<Response> {
  const object = await c.env.DIST.get(APPCAST_KEY[channel])
  if (object !== null) {
    return new Response(object.body, {
      status: 200,
      headers: {
        'Content-Type': 'application/xml; charset=utf-8',
        'Cache-Control': 'public, max-age=300',
        ETag: object.httpEtag,
      },
    })
  }

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
