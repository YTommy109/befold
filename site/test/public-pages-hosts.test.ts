import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import app from '../src/index'
import { pathFor, SITE_PAGES } from '../src/lib/pages'
import { pageSchema } from '../src/schema'
import { downloadHref } from '../src/views/shared'
import {
  APPCAST_URL,
  APPCAST_XML,
  bodyOf,
  call,
  cleanupAfterEach,
  DEFAULT_ORIGIN,
  DEVELOP_XML,
  IP,
  latestEvent,
  LATEST_RELEASE_URL,
  mockUpstream,
  RELEASES_LIST_URL,
  UA,
} from './public-helpers'

afterEach(cleanupAfterEach)

/**
 * ヘッダーの共通ナビ（TASK-542）。全ページ・両言語で同じ動線が出ることを、
 * 実際のレスポンス HTML で確かめる。
 */
describe('ヘッダーのナビゲーションバー', () => {
  // `/releases` は意図してナビに出さない（`FIXED_PAGES` の `nav: false`）。
  const NAV_PAGES = ['/', '/features', '/usecases'] as const

  for (const lang of ['ja', 'en'] as const) {
    const pages = SITE_PAGES.filter((entry) => entry.lang === lang)

    for (const entry of pages) {
      it(`${entry.path} のヘッダーに ${lang} の全ナビ項目が出る`, async () => {
        const body = await (await call(entry.path)).text()
        const nav = body.slice(body.indexOf('<nav class="site-nav"'))

        for (const page of NAV_PAGES) {
          expect(nav).toContain(`href="${pathFor(page, lang)}"`)
        }
      })
    }
  }

  it('過去のバージョンはナビに出さない', async () => {
    const body = await (await call('/')).text()
    const nav = body.slice(body.indexOf('<nav class="site-nav"'), body.indexOf('</nav>'))

    expect(nav).not.toContain('href="/releases"')
  })

  it('固定ページでは現在地が aria-current で分かる', async () => {
    const body = await (await call('/features')).text()

    expect(body).toContain(`<a class="site-nav-link" href="/features" aria-current="page">`)
  })

  it('英語ページのナビは /en 配下を指す', async () => {
    const body = await (await call('/en')).text()
    const nav = body.slice(body.indexOf('<nav class="site-nav"'), body.indexOf('</nav>'))

    expect(nav).toContain('href="/en/usecases"')
    expect(nav).not.toContain('href="/usecases"')
  })

  it('トップページから事例一覧へ 1 クリックで到達できる', async () => {
    const body = await (await call('/')).text()

    expect(body).toContain('href="/usecases"')
  })
})

describe('LP から詳細ページへの導線', () => {
  it('LP に /features への内部リンクがある', async () => {
    const body = await (await call('/')).text()

    expect(body).toContain('href="/features"')
  })

  // ナビから外した分、過去バージョンへの動線は LP のインストール章だけが持つ。
  it('LP のインストール章から過去バージョンへ辿れる', async () => {
    const body = await (await call('/')).text()
    const install = body.slice(body.indexOf('<section class="install">'))

    expect(install).toContain('href="/releases"')
    expect(install).toContain('過去バージョンが必要な方はこちら')
  })
})

/**
 * 旧 workers.dev ホストの扱い（ADR 0007 の決定 1・2）。
 *
 * 旧ホストは恒久的に生かし続ける必要がある。出荷済みアプリの Sparkle フィード URL
 * と、配信済み appcast に埋まった enclosure URL は後から変更できないため、
 * `/appcast*.xml` と `/dl/*` が旧ホストで 200 を返さなくなると更新経路が止まる。
 * リダイレクトは HTML ページの肯定列挙のみで行う。
 */
describe('旧ホストからのリダイレクト', () => {
  const LEGACY = 'https://befold.tommy109.workers.dev'
  const LEGACY_STAGING = 'https://befold-staging.tommy109.workers.dev'

  const legacy = (path: string, headers: Record<string, string> = {}) =>
    call(path, headers, undefined, LEGACY)

  it('SITE_PAGES の全ページを新ドメインの同一パスへ 301 で送る', async () => {
    // リダイレクト対象は SITE_PAGES からの導出（lib/hosts.ts）。言語ページを
    // 足したのに旧ホストの列挙だけ取り残される、という形を潰すためのループ。
    for (const entry of SITE_PAGES) {
      const response = await legacy(entry.path)

      expect(response.status, entry.path).toBe(301)
      expect(response.headers.get('Location'), entry.path).toBe(
        `https://befold.degino.com${entry.path}`,
      )
    }
  })

  it('301 を legacy_redirect として記録する（visit にはしない）', async () => {
    // visit として記録すると、301 を追った先の正規ホストでも visit が記録され、
    // ページアクセス数が二重に数えられる。
    const response = await legacy('/')

    expect(response.status).toBe(301)
    const event = await latestEvent()
    expect(event?.kind).toBe('legacy_redirect')
    expect(event?.host).toBe('befold.tommy109.workers.dev')
    expect(event?.page).toBeNull()

    const visits = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM events WHERE kind = 'visit'",
    ).first<{ count: number }>()
    expect(visits?.count).toBe(0)
  })

  it('クエリ文字列は 301 先へ引き継ぐ（?ref= の参照元計測を落とさない）', async () => {
    const response = await legacy('/?ref=gh-pages')

    expect(response.headers.get('Location')).toBe('https://befold.degino.com/?ref=gh-pages')
  })

  it('staging の旧ホストは staging の新ドメインへ送る（本番へ送らない）', async () => {
    const response = await call('/', {}, undefined, LEGACY_STAGING)

    expect(response.status).toBe(301)
    expect(response.headers.get('Location')).toBe('https://staging.befold.degino.com/')
  })

  it('appcast は 301 ではなく 200 を返す（出荷済みアプリの更新経路）', async () => {
    await env.DIST.put('appcast.xml', APPCAST_XML)
    await env.DIST.put('appcast-develop.xml', DEVELOP_XML)

    for (const path of ['/appcast.xml', '/appcast-develop.xml']) {
      const response = await legacy(path)

      expect(response.status).toBe(200)
      expect(response.headers.get('Location')).toBeNull()
    }
  })

  it('/dl/ は 301 ではなく 200 を返す（配信済み appcast の enclosure）', async () => {
    await env.DIST.put('releases/v1.2.3/befold-v1.2.3.dmg', 'DMG-BODY')

    const response = await legacy('/dl/v1.2.3/befold-v1.2.3.dmg')

    expect(response.status).toBe(200)
    expect(await response.text()).toBe('DMG-BODY')
  })

  it('/download はリダイレクトせず source=lp を従来どおり記録する', async () => {
    await env.DIST.put(
      'releases/latest.json',
      JSON.stringify({ version: 'v1.2.3', file: 'befold-v1.2.3.dmg' }),
    )
    await env.DIST.put('releases/v1.2.3/befold-v1.2.3.dmg', 'DMG-BODY')

    const response = await legacy('/download')

    expect(response.status).toBe(200)
    const event = await latestEvent('download')
    expect(event?.kind).toBe('download')
    expect(event?.source).toBe('lp')
  })

  it('列挙外のパスはリダイレクトしない（肯定列挙であることの担保）', async () => {
    for (const path of ['/healthz', '/robots.txt', '/sitemap.xml']) {
      const response = await legacy(path)

      expect(response.status).toBe(200)
    }
  })

  it('新ドメインで来たリクエストはリダイレクトしない', async () => {
    const response = await call('/', {}, undefined, 'https://befold.degino.com')

    expect(response.status).toBe(200)
  })
})

/**
 * 移行期は旧ホストの LP から新ドメインへ遷移する。これは外部からの流入ではないので
 * 参照元の集計に混ぜてはならない（ADR 0007 の決定 6）。resolveReferrer の単体テスト
 * だけでは events.ts の結線漏れを検知できないため、実リクエスト経由でも確かめる。
 */
describe('新旧ホスト間の遷移の計測', () => {
  it('旧ホストからの遷移は参照元として記録しない', async () => {
    await call(
      '/',
      { Referer: 'https://befold.tommy109.workers.dev/' },
      undefined,
      'https://befold.degino.com',
    )

    expect((await latestEvent())?.referrer).toBeNull()
  })

  it('外部サイトからの流入は従来どおり参照元として記録する', async () => {
    await call(
      '/',
      { Referer: 'https://news.ycombinator.com/item?id=1' },
      undefined,
      'https://befold.degino.com',
    )

    expect((await latestEvent())?.referrer).toBe('https://news.ycombinator.com')
  })
})

/**
 * ダウンロード導線は配信ホストに依存しない（ADR 0007 の決定 6）。正規オリジンを
 * 固定すると staging の LP のボタンが本番を指し、staging で download 経路と
 * source:'lp' の計測を確かめられなくなる。
 */
/**
 * ダウンロードが始まった面を `?ref=` で記録する（TASK-549）。
 *
 * download イベントの referrer は、サイト内リンク経由だと Referer が自ホストに
 * なるため `?ref=` が無ければ null になり、集計の `WHERE referrer IS NOT NULL` で
 * 行ごと消える。「素の /download でリンクを書く」形へ戻ると計測が静かに失われる
 * ので、リンク側と記録側の両方をここで固定する。
 */
describe('ダウンロード導線の ?ref=', () => {
  it.each([
    ['/', '/'],
    ['/features', '/features'],
    ['/usecases/medical-expenses', '/usecases/medical-expenses'],
  ] as const)('%s のダウンロードリンクに ?ref= が付く', async (path, page) => {
    const body = await (await call(path)).text()

    expect(body).toContain(`href="${downloadHref(page)}"`)
  })

  /**
   * `downloadHref()` を迂回して素の `/download` を書いた形の検出。href の直後が
   * `"` で終わるものだけを見る（`?ref=` 付きは `?` が続くので一致しない）。
   */
  it.each(['/', '/features', '/usecases/medical-expenses', '/en', '/en/features'])(
    '%s に素の href="/download" が残っていない',
    async (path) => {
      const body = await (await call(path)).text()

      expect(body).not.toContain('href="/download"')
    },
  )

  it('?ref= の値がそのまま download イベントの referrer になる', async () => {
    await call(downloadHref('/usecases/medical-expenses'))

    const event = await latestEvent('download')
    expect(event?.source).toBe('lp')
    expect(event?.referrer).toBe('usecases-medical-expenses')
  })

  /** ref を付けずに直接叩いた場合は従来どおり（自ホスト Referer は null）。 */
  it('?ref= が無ければ referrer は記録されない', async () => {
    await call('/download')

    const event = await latestEvent('download')
    expect(event?.source).toBe('lp')
    expect(event?.referrer).toBeNull()
  })
})

describe('ダウンロード導線のホスト非依存性', () => {
  // 旧ホストの LP と /features は 301 で新ドメインへ送るため（決定 2）、HTML を
  // 描くのは新ドメインと staging。どちらで描いてもホスト名は現れない。
  it.each(['https://befold.degino.com', 'https://staging.befold.degino.com'])(
    '%s で開いても同一ホスト内の /download を指す',
    async (origin) => {
      for (const page of ['/', '/features'] as const) {
        const body = await (await call(page, {}, undefined, origin)).text()

        expect(body).toContain(`href="${downloadHref(page)}"`)
        expect(body).not.toMatch(/href="https?:\/\/[^"]*\/download/u)
      }
    },
  )

  it('JSON-LD の downloadUrl はリクエスト origin から組む', async () => {
    const html = await (await call('/', {}, undefined, 'https://staging.befold.degino.com')).text()
    const json = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/u)?.[1]

    expect(JSON.parse(json as string).downloadUrl).toBe(
      'https://staging.befold.degino.com/download',
    )
  })
})

describe('GET /releases（過去バージョン一覧）', () => {
  /** GitHub API の応答の形をそのまま真似る。除外条件を実データの形で確かめる。 */
  const RELEASES_JSON = [
    {
      tag_name: 'v1.13.3-dev.1',
      published_at: '2026-08-16T13:43:02Z',
      prerelease: true,
      assets: [{ name: 'befold-v1.13.3-dev.1.dmg' }],
    },
    {
      tag_name: 'v1.13.2',
      published_at: '2026-08-16T10:16:56Z',
      prerelease: false,
      assets: [{ name: 'befold-v1.13.2.dmg' }],
    },
    // 版を表さない固定タグ。prerelease ではないので、フラグだけでは弾けない。
    {
      tag_name: 'appcast',
      published_at: '2026-08-16T10:20:00Z',
      prerelease: false,
      assets: [{ name: 'appcast.xml' }],
    },
    // DMG が無いリリース。行にしてもダウンロードできない。
    {
      tag_name: 'v1.0.0',
      published_at: '2026-01-01T00:00:00Z',
      prerelease: false,
      assets: [],
    },
    // 旧名のアセット。現在の命名規約（befold-<tag>.dmg）では導出できない。
    {
      tag_name: 'v1.3.3',
      published_at: '2026-05-01T00:00:00Z',
      prerelease: false,
      assets: [{ name: 'mmdview-v1.3.3.dmg' }],
    },
  ]

  function mockReleases(body: unknown, status = 200): void {
    mockUpstream({ [RELEASES_LIST_URL]: new Response(JSON.stringify(body), { status }) })
  }

  it('stable だけを表に出し、公開日・リリースノート・ダウンロードを並べる', async () => {
    mockReleases(RELEASES_JSON)

    const html = bodyOf(await (await call('/releases')).text())

    expect(html).toContain('v1.13.2')
    expect(html).toContain('2026-08-16')
    expect(html).toContain('https://github.com/YTommy109/befold/releases/tag/v1.13.2')
    expect(html).toContain('/releases/v1.13.2/befold-v1.13.2.dmg')
    // 旧名のアセットも、そのままのファイル名でリンクする。
    expect(html).toContain('/releases/v1.3.3/mmdview-v1.3.3.dmg')
  })

  it('develop・版でないタグ・DMG 無しは一覧に出さない', async () => {
    mockReleases(RELEASES_JSON)

    const html = bodyOf(await (await call('/releases')).text())

    expect(html).not.toContain('dev.1')
    expect(html).not.toContain('appcast')
    expect(html).not.toContain('v1.0.0')
  })

  it('visit を /releases として記録する', async () => {
    mockReleases(RELEASES_JSON)

    await call('/releases')

    const event = await latestEvent('visit')
    expect(event?.page).toBe('/releases')
    expect(event?.display_lang).toBe('ja')
  })

  it('取得に失敗しても 200 で、取得できなかったことを伝える', async () => {
    mockReleases({ message: 'rate limit' }, 403)

    const response = await call('/releases')
    const html = bodyOf(await response.text())

    expect(response.status).toBe(200)
    expect(html).toContain('取得できませんでした')
    // 行き止まりにせず GitHub の一覧へ逃がす。
    expect(html).toContain('https://github.com/YTommy109/befold/releases')
  })

  it('取得できて 0 件のときは「取得できなかった」とは言わない', async () => {
    mockReleases([])

    const html = bodyOf(await (await call('/releases')).text())

    expect(html).toContain('まだありません')
    expect(html).not.toContain('取得できませんでした')
  })

  it('英語版は英語で出す', async () => {
    mockReleases(RELEASES_JSON)

    const html = bodyOf(await (await call('/en/releases')).text())

    expect(html).toContain('Previous versions')
    expect(html).not.toContain('過去のバージョン')
  })
})

describe('GET /releases/:tag/:file（旧バージョンの配信）', () => {
  it('R2 にあれば DMG を返し source=archive を記録する', async () => {
    await env.DIST.put('releases/v1.12.0/befold-v1.12.0.dmg', 'OLD-DMG')

    const response = await call('/releases/v1.12.0/befold-v1.12.0.dmg')

    expect(response.status).toBe(200)
    expect(await response.text()).toBe('OLD-DMG')

    const event = await latestEvent('download')
    expect(event?.source).toBe('archive')
    expect(event?.version).toBe('v1.12.0')
    expect(event?.channel).toBe('stable')
  })

  it('R2 に無ければ GitHub へ 302 し、fallback は dmg と分けて記録する', async () => {
    const response = await call('/releases/v1.3.3/mmdview-v1.3.3.dmg')

    expect(response.status).toBe(302)
    expect(response.headers.get('location')).toBe(
      'https://github.com/YTommy109/befold/releases/download/v1.3.3/mmdview-v1.3.3.dmg',
    )

    // 旧版が R2 に無いのは配置漏れではない。`dmg`（配布の穴）に混ぜない。
    const fallback = await latestEvent('github_fallback')
    expect(fallback?.fallback).toBe('archive-dmg')

    const download = await latestEvent('download')
    expect(download?.source).toBe('archive')
    expect(download?.version).toBe('v1.3.3')
  })

  it('develop タグは配らない（一覧に出していないものを URL 直打ちで取らせない）', async () => {
    await env.DIST.put('releases/v1.13.3-dev.1/befold-v1.13.3-dev.1.dmg', 'DEV-DMG')

    const response = await call('/releases/v1.13.3-dev.1/befold-v1.13.3-dev.1.dmg')

    expect(response.status).toBe(404)
    expect(await latestEvent('download')).toBeNull()
  })

  it('キーを組めない形のファイル名は 404 にする', async () => {
    const response = await call('/releases/v1.12.0/..%2Flatest.json')

    expect(response.status).toBe(404)
    expect(await latestEvent('download')).toBeNull()
  })
})

describe('言語ごとの URL（SITE_PAGES からの導出）', () => {
  // /releases は GitHub API を読む。差し替えないとテストが外部の可用性と
  // レート制限に依存する（応答の中身はここでは見ないので、縮退させておく）。
  beforeEach(() => {
    mockUpstream({ [RELEASES_LIST_URL]: new Response('{}', { status: 503 }) })
  })

  it('表に載っている全ページが 200 を返し、html lang が表と一致する', async () => {
    for (const entry of SITE_PAGES) {
      const response = await call(entry.path)

      expect(response.status, entry.path).toBe(200)
      expect(await response.text(), entry.path).toContain(`<html lang="${entry.lang}">`)
    }
  })

  it('各ページの hreflang が自己参照を含む全バリアントを列挙する', async () => {
    // 自己参照を落とすと検索エンジンから見た対応関係が成立しない。省きやすい
    // ところなので、集合の一致で固定する。
    for (const entry of SITE_PAGES) {
      const html = await (await call(entry.path)).text()
      const found = [...html.matchAll(/<link rel="alternate" hreflang="(\w+)" href="([^"]+)"\/>/gu)]
      const expected = SITE_PAGES.filter((variant) => variant.page === entry.page)

      expect(found.map((match) => match[2]).toSorted(), entry.path).toEqual(
        expected.map((variant) => `https://befold.example${variant.path}`).toSorted(),
      )
      expect(found.map((match) => match[1]).toSorted(), entry.path).toEqual(
        expected.map((variant) => variant.lang).toSorted(),
      )
    }
  })

  it('各ページの canonical が自分自身を指す', async () => {
    for (const entry of SITE_PAGES) {
      const html = await (await call(entry.path)).text()

      expect(html, entry.path).toContain(
        `<link rel="canonical" href="https://befold.example${entry.path}"/>`,
      )
    }
  })

  it('言語ごとに og:locale と og:locale:alternate が入れ替わる', async () => {
    const ja = await (await call('/')).text()
    const en = await (await call('/en')).text()

    expect(ja).toContain('<meta property="og:locale" content="ja_JP"/>')
    expect(ja).toContain('<meta property="og:locale:alternate" content="en_US"/>')
    expect(en).toContain('<meta property="og:locale" content="en_US"/>')
    expect(en).toContain('<meta property="og:locale:alternate" content="ja_JP"/>')
  })

  it('表示した言語が display_lang として記録される', async () => {
    for (const entry of SITE_PAGES) {
      await call(entry.path)
      const event = await latestEvent()

      expect(event?.kind, entry.path).toBe('visit')
      expect(event?.page, entry.path).toBe(entry.page)
      expect(event?.display_lang, entry.path).toBe(entry.lang)
    }
  })

  it('ブラウザ言語設定と表示言語は別々に記録される', async () => {
    // 英語設定のブラウザが日本語ページを見ている、という取りこぼしを測れること。
    // これが分からないと「英語を求めて来た人が英語ページへ辿り着けたか」が出ない。
    await call('/', { 'Accept-Language': 'en-US,en;q=0.9' })

    const event = await latestEvent()
    expect(event?.browser_lang).toBe('en')
    expect(event?.display_lang).toBe('ja')
  })

  it('全 4 ページがキャッシュに載らない', async () => {
    // 1 本でも載ると、そのページの計測だけが環境依存で欠けて日英比率が歪む。
    for (const entry of SITE_PAGES) {
      const response = await call(entry.path)

      expect(response.headers.get('Cache-Control'), entry.path).toBe('no-store')
    }
  })

  it('言語切替リンクが相手言語のページを指し、現在地に aria-current が付く', async () => {
    const html = await (await call('/features')).text()

    expect(html).toContain('href="/en/features"')
    expect(html).toMatch(/<a[^>]*class="lang-btn"[^>]*href="\/features"[^>]*aria-current="page"/u)
  })

  it('SITE_PAGES の page がすべて pageSchema の列挙に含まれる', () => {
    // pageSchema は z.enum のリテラルタプルを保つため手書きのまま残してある
    // （導出すると Page 型が string へ広がり、EventAttributes と METRIC_FILTERS の
    // 型安全が失われる）。その代わり両者のずれをここで検知する。
    for (const entry of SITE_PAGES) {
      expect(() => pageSchema.parse(entry.page), entry.path).not.toThrow()
    }
  })

  it('存在しない言語パスは 200 を返さない', async () => {
    // /en/download は作らない。/download を単一に保たないと LP 由来の
    // ダウンロード計測（source:'lp'）が言語ごとに割れる。
    for (const path of ['/en/download', '/ja', '/ja/features']) {
      expect((await call(path)).status, path).not.toBe(200)
    }
  })
})

/**
 * リクエスト先ホストと、R2 ミスによる GitHub フォールバックの記録。
 *
 * ADR 0007 の「旧ホストと GitHub 経路を止めてよいか」の判断材料になる
 * （旧ホストの appcast を叩くクライアントがゼロか / R2 ミスがゼロか）。
 */
describe('リクエスト先ホストと GitHub フォールバックの記録', () => {
  it('既知のホストはそのまま、それ以外は other として記録する', async () => {
    await call('/', {}, undefined, 'https://befold.degino.com')
    expect((await latestEvent())?.host).toBe('befold.degino.com')

    await call('/', {}, undefined, 'https://staging.befold.degino.com')
    expect((await latestEvent())?.host).toBe('staging.befold.degino.com')

    // 既定オリジンは既知ホストではない（preview URL や wrangler dev に相当）。
    // 生の Host をそのまま入れるとカーディナリティが発散するため 1 つに丸める。
    await call('/')
    expect((await latestEvent())?.host).toBe('other')
  })

  it('旧ホストの appcast はリダイレクトされず、旧ホストのまま記録される', async () => {
    // ここが記録できないと ADR 0007 の停止条件を永久に判定できない。
    await env.DIST.put('appcast.xml', APPCAST_XML)

    const response = await call(
      '/appcast.xml',
      { 'User-Agent': 'befold/1.2.3 Sparkle/2.6.4' },
      undefined,
      'https://befold.tommy109.workers.dev',
    )

    expect(response.status).toBe(200)
    const event = await latestEvent('update_check')
    expect(event?.host).toBe('befold.tommy109.workers.dev')
  })

  it('R2 に appcast が無ければ github_fallback を appcast として記録する', async () => {
    mockUpstream({ [APPCAST_URL]: new Response(APPCAST_XML) })

    await call('/appcast.xml')

    const event = await latestEvent('github_fallback')
    expect(event?.fallback).toBe('appcast')
    expect(event?.channel).toBe('stable')
  })

  it('R2 に appcast があればフォールバックは記録されない', async () => {
    await env.DIST.put('appcast.xml', APPCAST_XML)

    await call('/appcast.xml')

    expect(await latestEvent('github_fallback')).toBeNull()
  })

  it('R2 に DMG が無ければ github_fallback を dmg として記録する', async () => {
    const response = await call('/dl/v1.2.3/befold-v1.2.3.dmg')

    expect(response.status).toBe(302)
    const event = await latestEvent('github_fallback')
    expect(event?.fallback).toBe('dmg')
    expect(event?.version).toBe('v1.2.3')
  })

  it('不正なタグ・ファイル名は dmg ではなく dmg-invalid として記録する', async () => {
    // 検証で弾いたリクエスト（配布対象でない）を R2 の欠落と混ぜない。混ぜると
    // 「配布の穴」を数えているはずの dmg がパス探索でいくらでも増える。
    for (const path of ['/dl/latest/befold-v1.2.3.dmg', '/dl/v1.2.3/latest.json']) {
      const response = await call(path)

      expect(response.status).toBe(302)
      expect((await latestEvent('github_fallback'))?.fallback).toBe('dmg-invalid')
    }
  })

  it('R2 に最新ポインタが無ければ github_fallback を release-api として記録する', async () => {
    mockUpstream({
      [LATEST_RELEASE_URL]: Response.json({
        tag_name: 'v1.2.3',
        assets: [
          {
            name: 'befold-v1.2.3.dmg',
            browser_download_url: 'https://github.com/x/y/releases/download/v1.2.3/a.dmg',
          },
        ],
      }),
    })

    await call('/download')

    const event = await latestEvent('github_fallback')
    expect(event?.fallback).toBe('release-api')
  })

  it('R2 から配れたときはフォールバックを記録しない', async () => {
    await env.DIST.put('releases/latest.json', '{"version":"v1.2.3","file":"befold-v1.2.3.dmg"}')
    await env.DIST.put('releases/v1.2.3/befold-v1.2.3.dmg', 'DMG-BODY')

    const response = await call('/download')

    expect(response.status).toBe(200)
    expect(await latestEvent('github_fallback')).toBeNull()
  })
})

describe('404 ページ', () => {
  /** events の行数。404 が指標へ混ざっていないことは kind ではなく総数で見る。 */
  async function eventCount(): Promise<number> {
    const row = await env.DB.prepare('SELECT COUNT(*) AS n FROM events').first<{ n: number }>()
    return row?.n ?? 0
  }

  it('ルートにも静的アセットにも当たらないパスは LP の意匠の 404 を返す', async () => {
    const response = await call('/en/download')

    expect(response.status).toBe(404)
    expect(response.headers.get('Content-Type')).toContain('text/html')
    const body = await response.text()
    // LP と同じ style.css を読み込み、同じ hero / btn-primary の意匠を使う。
    expect(body).toContain('<link rel="stylesheet" href="/style.css"/>')
    expect(body).toContain('class="hero"')
    expect(body).toContain('404')
  })

  it('日本語ページと英語ページの両方への導線がある', async () => {
    const body = await (await call('/nope')).text()

    // 宛先は SITE_PAGES から導出する。パスを変えたときにテストだけが取り残されないように。
    for (const lang of ['ja', 'en'] as const) {
      expect(bodyOf(body)).toContain(`href="${pathFor('/', lang)}"`)
    }
  })

  it('noindex を付け canonical は出さない', async () => {
    const body = await (await call('/nope')).text()

    expect(body).toContain('<meta name="robots" content="noindex"/>')
    // SITE_PAGES に無いパスなので、正規 URL も言語版の対応関係も主張しない。
    expect(body).not.toContain('rel="canonical"')
    expect(body).not.toContain('hreflang="ja" href=')
  })

  it('events に記録しない（LP の指標に混ざらない）', async () => {
    expect(await eventCount()).toBe(0)

    await call('/nope')
    await call('/en/nope')

    expect(await eventCount()).toBe(0)
  })

  it('実在する静的アセットは 404 に差し替えない', async () => {
    const response = await call('/style.css')

    expect(response.status).toBe(200)
    expect(await response.text()).toContain('.btn-primary')
  })

  it('キャッシュに載せない', async () => {
    const response = await call('/nope')

    expect(response.headers.get('Cache-Control')).toBe('no-store')
  })
})

describe('HEAD 要求の計測', () => {
  /** 本文を取らない HEAD。Hono は GET のハンドラへ流すため、記録側で分ける必要がある。 */
  async function head(path: string): Promise<Response> {
    const request = new Request(`${DEFAULT_ORIGIN}${path}`, {
      method: 'HEAD',
      headers: { 'User-Agent': UA, 'CF-Connecting-IP': IP, 'CF-IPCountry': 'JP' },
      redirect: 'manual',
    })
    const ctx = createExecutionContext()
    const response = await app.fetch(request, env, ctx)
    await waitOnExecutionContext(ctx)
    return response
  }

  async function eventCount(): Promise<number> {
    const row = await env.DB.prepare('SELECT COUNT(*) AS n FROM events').first<{ n: number }>()
    return row?.n ?? 0
  }

  // 3 経路すべてを並べる。1 つだけ直すと、次にダウンロード経路を足したときに
  // 同じ穴が復活する（記録側の絞り込み点で弾いていることをここで固定する）。
  it.each([
    ['/download', 'lp'],
    ['/dl/v1.12.0/befold-v1.12.0.dmg', 'sparkle'],
    ['/releases/v1.12.0/befold-v1.12.0.dmg', 'archive'],
  ])('%s への HEAD は download を記録しない', async (path) => {
    await env.DIST.put('releases/v1.12.0/befold-v1.12.0.dmg', 'OLD-DMG')
    await env.DIST.put('dl/v1.12.0/befold-v1.12.0.dmg', 'DMG')

    await head(path)

    expect(await latestEvent('download')).toBeNull()
  })

  it('LP への HEAD はページアクセスに数えない', async () => {
    await head('/')

    expect(await eventCount()).toBe(0)
  })

  it('GET なら同じ経路で記録される（HEAD の除外が記録全体を止めていない）', async () => {
    await call('/download')

    expect(await latestEvent('download')).not.toBeNull()
  })
})
