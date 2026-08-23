import { Hono } from 'hono'
import type { Context } from 'hono'
import type { HtmlEscapedString } from 'hono/utils/html'

import { recordEvent } from '../events'
import type { AppEnv } from '../index'
import {
  DRAFT_PAGE,
  articleLangs,
  articlePath,
  draftArticles,
  draftPath,
  publishedArticles,
  type Article,
} from '../lib/articles'
import {
  APPCAST_KEY,
  archiveDMGKey,
  isDMGFileName,
  isStableTag,
  LATEST_KEY,
  latestPointerSchema,
  resolveDMGKey,
} from '../lib/dist'
import {
  APPCAST_UPSTREAM,
  latestDMG,
  releaseAssetURL,
  RELEASES_LATEST_URL,
  stableReleases,
  type Channel,
} from '../lib/github'
import { FIXED_PAGES, SITE_PAGES, variantsOf, type FixedPage, type SitePage } from '../lib/pages'
import { ArticlePage, articleBody } from '../views/article'
import { Features } from '../views/features'
import { Landing } from '../views/landing'
import { notFoundResponse } from '../views/not-found'
import { Releases, type ReleaseListing } from '../views/releases'
import { Usecases } from '../views/usecases'

export const publicRoutes = new Hono<AppEnv>()

/**
 * LP と詳細ページを、日本語・英語それぞれの URL で登録する。
 *
 * ルートを 4 本手書きしない。`SITE_PAGES` を唯一の対応表にしておかないと、
 * パスの追加・変更のたびにルート登録・計測・sitemap・hreflang・旧ホストからの
 * 301 の 5 箇所が別々に直る形になる（`lib/pages.ts` の doc を参照）。
 *
 * `Cache-Control: no-store` は 4 本すべてに付ける。キャッシュに載った応答は
 * Worker を通らず計上できないため、付け忘れたページだけ計測が環境依存で欠ける。
 * ヘッダを外すだけでは足りない——Cache-Control も Expires も無い 200 応答は
 * ブラウザのヒューリスティックキャッシュに載り得る。
 */
for (const entry of FIXED_PAGES) {
  publicRoutes.get(entry.path, async (c) => {
    // display_lang は配信するビューの言語そのもの。パスの形からは導出しない。
    recordEvent(c, { kind: 'visit', page: entry.page, displayLang: entry.lang })
    // c.header は後続の c.html に反映されるため、本文を作る前に設定する。
    c.header('Cache-Control', 'no-store')

    const origin = new URL(c.req.url).origin
    return c.html(await PAGE_VIEWS[entry.page](origin, entry))
  })
}

/**
 * 記事のルート。固定ページと分けているのは、**本文が記事ごとに違う**ため
 * （`PAGE_VIEWS` のような 1 ページ 1 ビューの対応表に収まらない）。
 *
 * 公開記事とドラフトで違うのは URL と、計測に使う page 値だけ。描画は同じ
 * `ArticlePage` を通す——枠を分けると「ドラフトのときだけ表示が崩れている」に
 * 気づけない。
 *
 * ドラフトの page 値は記事ごとに分けず `DRAFT_PAGE` の 1 つへ畳む。公開前の
 * アクセスは記事ごとの粒度に価値がなく、内訳のカーディナリティだけが増える。
 */
function registerArticle(article: Article, isDraft: boolean): void {
  const body = articleBody(article)
  if (body === null) return

  for (const lang of articleLangs(article)) {
    const path = isDraft ? draftPath(article, lang) : articlePath(article, lang)
    const entry: SitePage = { path, lang, page: article.page }

    publicRoutes.get(path, (c) => {
      recordEvent(c, {
        kind: 'visit',
        page: isDraft ? DRAFT_PAGE : article.page,
        displayLang: lang,
      })
      c.header('Cache-Control', 'no-store')

      const origin = new URL(c.req.url).origin
      return c.html(<ArticlePage origin={origin} entry={entry} article={article} body={body} />)
    })
  }
}

for (const article of publishedArticles()) registerArticle(article, false)
for (const article of draftArticles()) registerArticle(article, true)

/**
 * 論理ページ 1 つを描くもの。**`Record<Page, ...>` にするのが要点。**
 *
 * かつては `entry.page === '/' ? <Landing/> : <Features/>` の三項で、2 ページ
 * しか無いことを前提にしていた。3 ページ目を足すと「どちらでもないものが
 * Features として描かれる」形で静かに壊れるため、ページを足したら型が漏れを
 * 指す形に変えた。
 */
const PAGE_VIEWS: Record<
  FixedPage,
  (origin: string, entry: SitePage) => Promise<HtmlEscapedString>
> = {
  '/': (origin, entry) => Promise.resolve(<Landing origin={origin} entry={entry} />),
  '/features': (origin, entry) => Promise.resolve(<Features origin={origin} entry={entry} />),
  '/releases': async (origin, entry) => {
    // 取得できなければ null のまま渡す。ビュー側が「取得できなかった」と
    // 「まだ 1 件も無い」を別の文面で出し分ける。
    const releases: ReleaseListing = await stableReleases()
    return <Releases origin={origin} entry={entry} releases={releases} />
  },
  '/usecases': (origin, entry) => Promise.resolve(<Usecases origin={origin} entry={entry} />),
}

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
    recordEvent(c, { kind: 'github_fallback', fallback: 'release-api' })
    recordEvent(c, {
      kind: 'download',
      version: dmg?.version ?? null,
      channel: 'stable',
      source: 'lp',
    })
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
publicRoutes.get('/dl/:tag/:file', (c) => {
  const tag = c.req.param('tag')
  const file = c.req.param('file')
  const channel = tag.includes('-') ? 'develop' : 'stable'

  recordEvent(c, { kind: 'download', version: tag, channel, source: 'sparkle' })
  return serveDMG(c, tag, file)
})

/**
 * 旧バージョン一覧（/releases）からの配信。
 *
 * `/dl` を流用しない。理由は 2 つあり、どちらも記録の意味に関わる。
 * (1) `/dl` は Sparkle 専用で `source: 'sparkle'` 固定であり、人間が旧版へ
 * 戻した行為を自動アップデートとして数えてしまう。(2) `/dl` の
 * `resolveDMGKey` はファイル名を現在の規約（`befold-<tag>.dmg`）に固定して
 * いるが、v1.3.3 以前の実アセット名は `mmdview-<tag>.dmg` で、正常な配信が
 * まるごと `dmg-invalid`（＝配布対象でないリクエスト）として記録される。
 *
 * 配るのは stable だけ。タグの形の検証だけでは `-dev.N` を通してしまい、
 * 一覧に出していない開発版が URL 直打ちで配れる。
 */
publicRoutes.get('/releases/:tag/:file', async (c) => {
  const tag = c.req.param('tag')
  const file = c.req.param('file')

  if (!isStableTag(tag) || !isDMGFileName(file)) return notFoundResponse(c)

  const key = archiveDMGKey(tag, file)
  const object = await c.env.DIST.get(key)

  recordEvent(c, { kind: 'download', version: tag, channel: 'stable', source: 'archive' })

  if (object === null) {
    // 旧版が R2 に無いのは配置漏れではない（R2 へ置き始める前のタグは GitHub に
    // しか実体が無い）。`dmg` と混ぜると「配布の穴」の系列が旧版のダウンロードで
    // 埋まるため、必ず別の値で記録する。
    recordEvent(c, { kind: 'github_fallback', fallback: 'archive-dmg', version: tag })
    return c.redirect(releaseAssetURL(tag, file), 302)
  }

  return dmgResponse(object, file)
})

/**
 * R2 の DMG を返す。無ければ GitHub Releases の同名アセットへ 302 する。
 *
 * 302 する理由は 2 つあり、**記録では必ず分ける**。`resolveDMGKey` が弾いた
 * （`dmg-invalid`）のは配布対象でないリクエストで、R2 の欠落（`dmg`）ではない。
 * 同じ 302 という応答の形で丸めると、パス探索の類いが「配布の穴」として数えられ、
 * GitHub 経路を止めてよいかの判断（ADR 0007 / TASK-489）が読めなくなる。
 * 応答自体はどちらも従来どおり GitHub へ送る（導線を途切れさせない）。
 */
async function serveDMG(c: Context<AppEnv>, tag: string, file: string): Promise<Response> {
  const key = resolveDMGKey(tag, file)
  const object = key === null ? null : await c.env.DIST.get(key)

  if (object === null) {
    const fallback = key === null ? 'dmg-invalid' : 'dmg'
    recordEvent(c, { kind: 'github_fallback', fallback, version: tag })
    return c.redirect(releaseAssetURL(tag, file), 302)
  }

  return dmgResponse(object, file)
}

/**
 * R2 から読んだ DMG の応答。Sparkle 経路と旧バージョン経路で共有する。
 *
 * 応答の形（ヘッダの組）を経路ごとに書くと、片方だけ Content-Disposition を
 * 落とすような差が黙って入る。記録の意味は経路ごとに違うが、応答は同じ。
 */
function dmgResponse(object: R2ObjectBody, file: string): Response {
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

/** sitemap の priority / changefreq。LP を最上位に置く。 */
const priorityOf = (page: string): string => (page === '/' ? '1.0' : '0.8')
const changefreqOf = (page: string): string => (page === '/' ? 'weekly' : 'monthly')

/**
 * sitemap。`SITE_PAGES` の全バリアントを列挙し、相互の対応を xhtml:link で示す。
 *
 * 各 URL に**自分自身を含む**全バリアントの alternate を書く。検索エンジンは
 * 「各版が自分自身を含む全版を相互に指す」ことを対応関係の成立条件にしており、
 * 自己参照を落とすと対応が成立しない（head の hreflang と同じ規則）。
 */
publicRoutes.get('/sitemap.xml', (c) => {
  const { origin } = new URL(c.req.url)
  const entries = SITE_PAGES.map((entry) => {
    const alternates = variantsOf(entry.page)
      .map(
        (variant) =>
          `<xhtml:link rel="alternate" hreflang="${variant.lang}" href="${origin}${variant.path}"/>`,
      )
      .join('')
    return (
      `  <url><loc>${origin}${entry.path}</loc>${alternates}` +
      `<changefreq>${changefreqOf(entry.page)}</changefreq>` +
      `<priority>${priorityOf(entry.page)}</priority></url>\n`
    )
  }).join('')
  const body =
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"' +
    ' xmlns:xhtml="http://www.w3.org/1999/xhtml">\n' +
    entries +
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
 * `github_fallback`（R2 に appcast が無く GitHub をプロキシした）の記録は
 * `loadAppcast` の中で行う。キャッシュに当たった周期はそこを通らないため、
 * この経路のフォールバック数は最大 300 秒ぶん過小に出る。update_check 自体は
 * キャッシュ判定より前に記録するのでこの影響を受けない。
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

  recordEvent(c, { kind: 'github_fallback', fallback: 'appcast', channel })
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
