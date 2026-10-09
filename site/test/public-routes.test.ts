import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { afterEach, describe, expect, it, vi } from 'vitest'

import app from '../src/index'
import { SITE_PAGES } from '../src/lib/pages'
import { downloadHref } from '../src/views/shared'
import {
  APPCAST_DEVELOP_URL,
  APPCAST_URL,
  APPCAST_XML,
  bodyOf,
  call,
  cleanupAfterEach,
  DEVELOP_XML,
  IP,
  latestEvent,
  LATEST_RELEASE_URL,
  mockUpstream,
  UA,
} from './public-helpers'

afterEach(cleanupAfterEach)

describe('GET /', () => {
  it('LP を返し visit を記録する', async () => {
    const response = await call('/')

    expect(response.status).toBe(200)
    const body = await response.text()
    expect(body).toContain('befold')
    expect(body).toContain(`href="${downloadHref('/')}"`)

    const event = await latestEvent()
    expect(event?.kind).toBe('visit')
    expect(event?.country).toBe('JP')
    expect(event?.page).toBe('/')
  })
})

describe('QuickLook の訴求ブロック', () => {
  it.each([
    ['/', 'スペースキーを押すだけで'],
    ['/en', 'Press Space and read it'],
  ])('%s に動画つきの独立ブロックがあり、機能一覧と同じ文を繰り返さない', async (path, lead) => {
    const body = await (await call(path)).text()

    expect(body).toContain(lead)
    expect(body).toContain('src="/images/quicklook-demo.mp4"')
    expect(body).toContain('src="/quicklook-demo.js"')
    // 「対応してます」の一文は独立ブロックへ移した。冒頭文に残すと二重の訴求になる。
    expect(body).not.toContain('Quick Look にも対応してます')
    expect(body).not.toContain('supports Quick Look, too')
  })
})

describe('参照元の記録', () => {
  it('?ref= が付いていればその値を記録する', async () => {
    await call('/?ref=gh-pages')

    expect((await latestEvent())?.referrer).toBe('gh-pages')
  })

  it('?ref= が無ければ Referer のオリジンだけを記録する', async () => {
    await call('/', { Referer: 'https://news.ycombinator.com/item?id=123' })

    expect((await latestEvent())?.referrer).toBe('https://news.ycombinator.com')
  })

  it('自サイト内の遷移は参照元として記録しない', async () => {
    await call('/', { Referer: 'https://befold.example/' })

    expect((await latestEvent())?.referrer).toBeNull()
  })

  it('参照元が無い直接アクセスでもイベント自体は記録される', async () => {
    await call('/')

    const event = await latestEvent()
    expect(event?.kind).toBe('visit')
    expect(event?.referrer).toBeNull()
  })
})

describe('接続元組織（ASN）の記録', () => {
  it('request.cf.asOrganization があれば記録する', async () => {
    await call('/', {}, { asOrganization: 'Google LLC' } as IncomingRequestCfProperties)

    expect((await latestEvent())?.as_org).toBe('Google LLC')
  })

  it('request.cf が無い（ローカル・テスト相当）環境でもイベント自体は記録される', async () => {
    const response = await call('/')

    expect(response.status).toBe(200)
    expect((await latestEvent())?.as_org).toBeNull()
  })
})

describe('GET /download', () => {
  it('最新リリースの DMG へ 302 リダイレクトし download を記録する', async () => {
    mockUpstream({
      [LATEST_RELEASE_URL]: Response.json({
        tag_name: 'v1.2.3',
        assets: [
          { name: 'befold-v1.2.3.dmg', browser_download_url: 'https://example.test/befold.dmg' },
        ],
      }),
    })

    const response = await call('/download')

    expect(response.status).toBe(302)
    expect(response.headers.get('Location')).toBe('https://example.test/befold.dmg')

    const event = await latestEvent('download')
    expect(event?.kind).toBe('download')
    expect(event?.version).toBe('v1.2.3')
    expect(event?.channel).toBe('stable')
  })

  it('GitHub API が失敗してもリリース一覧へリダイレクトする', async () => {
    mockUpstream({ [LATEST_RELEASE_URL]: new Response('boom', { status: 500 }) })

    const response = await call('/download')

    expect(response.status).toBe(302)
    expect(response.headers.get('Location')).toBe(
      'https://github.com/YTommy109/befold/releases/latest',
    )
    expect((await latestEvent())?.version).toBeNull()
  })

  it('R2 に最新ポインタがあれば DMG を直接返し source=lp を記録する', async () => {
    await env.DIST.put(
      'releases/latest.json',
      JSON.stringify({ version: 'v1.2.3', file: 'befold-v1.2.3.dmg' }),
    )
    await env.DIST.put('releases/v1.2.3/befold-v1.2.3.dmg', 'DMG-BODY')

    const response = await call('/download')

    expect(response.status).toBe(200)
    expect(await response.text()).toBe('DMG-BODY')
    expect(response.headers.get('Content-Disposition')).toContain('befold-v1.2.3.dmg')

    const event = await latestEvent('download')
    expect(event?.kind).toBe('download')
    expect(event?.version).toBe('v1.2.3')
    expect(event?.source).toBe('lp')
  })

  it('latest.json が壊れていれば GitHub 解決へ落とす', async () => {
    await env.DIST.put('releases/latest.json', '{"version":"not-a-tag"}')
    mockUpstream({ [LATEST_RELEASE_URL]: new Response('boom', { status: 500 }) })

    const response = await call('/download')

    expect(response.status).toBe(302)
    expect((await latestEvent())?.source).toBe('lp')
  })
})

describe('GET /dl/:tag/:file', () => {
  it('R2 の DMG を返し source=sparkle を記録する', async () => {
    await env.DIST.put('releases/v1.2.3/befold-v1.2.3.dmg', 'DMG-BODY')

    const response = await call('/dl/v1.2.3/befold-v1.2.3.dmg')

    expect(response.status).toBe(200)
    expect(await response.text()).toBe('DMG-BODY')

    const event = await latestEvent('download')
    expect(event?.kind).toBe('download')
    expect(event?.version).toBe('v1.2.3')
    expect(event?.channel).toBe('stable')
    expect(event?.source).toBe('sparkle')
  })

  it('dev タグは develop チャンネルとして記録する', async () => {
    await env.DIST.put('releases/v1.2.3-dev.1/befold-v1.2.3-dev.1.dmg', 'DMG-BODY')

    const response = await call('/dl/v1.2.3-dev.1/befold-v1.2.3-dev.1.dmg')

    expect(response.status).toBe(200)
    expect((await latestEvent())?.channel).toBe('develop')
  })

  it('R2 に無ければ 404 ではなく GitHub Releases へ 302 する', async () => {
    const response = await call('/dl/v1.2.3/befold-v1.2.3.dmg')

    // Sparkle は enclosure の 404 を更新失敗として扱うため、404 は返さない。
    expect(response.status).toBe(302)
    expect(response.headers.get('Location')).toBe(
      'https://github.com/YTommy109/befold/releases/download/v1.2.3/befold-v1.2.3.dmg',
    )
  })

  it('DMG 以外のオブジェクトはパス検証で弾き R2 を読まない', async () => {
    await env.DIST.put('releases/latest.json', '{"version":"v1.2.3","file":"befold-v1.2.3.dmg"}')

    const response = await call('/dl/v1.2.3/..%2Flatest.json')

    expect(response.status).toBe(302)
    expect(await response.text()).not.toContain('v1.2.3')
  })

  it('タグの形が合わないリクエストは R2 を読まない', async () => {
    await env.DIST.put('releases/v1.2.3/befold-v1.2.3.dmg', 'DMG-BODY')

    const response = await call('/dl/appcast/befold-v1.2.3.dmg')

    expect(response.status).toBe(302)
    expect(await response.text()).not.toBe('DMG-BODY')
  })
})

describe('appcast プロキシ', () => {
  it('/appcast.xml が GitHub の appcast を返し update_check を記録する', async () => {
    mockUpstream({ [APPCAST_URL]: new Response(APPCAST_XML) })

    const response = await call('/appcast.xml', { 'User-Agent': 'befold/1.2.3 Sparkle/2.6.4' })

    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toContain('xml')
    expect(await response.text()).toBe(APPCAST_XML)

    const event = await latestEvent('update_check')
    expect(event?.kind).toBe('update_check')
    expect(event?.channel).toBe('stable')
    expect(event?.ua_summary).toBe('Sparkle')
  })

  it('稼働中のアプリバージョンを app_version に記録する（TASK-491.1）', async () => {
    mockUpstream({ [APPCAST_URL]: new Response(APPCAST_XML) })

    // Sparkle 2.9.4 が実際に送る形（実測、2026-08-16）。
    await call('/appcast.xml', { 'User-Agent': 'befold/1.13.2-dev.4 Sparkle/2.9.4' })

    const event = await latestEvent('update_check')
    expect(event?.app_version).toBe('1.13.2-dev.4')
    // version は download の対象タグ用。update_check では埋めない。
    expect(event?.version).toBeNull()
  })

  it('パースできない UA でも記録は成功し app_version は NULL になる', async () => {
    mockUpstream({ [APPCAST_URL]: new Response(APPCAST_XML) })

    const response = await call('/appcast.xml', { 'User-Agent': 'curl/8.7.1' })

    expect(response.status).toBe(200)
    const event = await latestEvent('update_check')
    expect(event?.kind).toBe('update_check')
    expect(event?.app_version).toBeNull()
  })

  it('/appcast-develop.xml が develop チャンネルとして記録される', async () => {
    mockUpstream({ [APPCAST_DEVELOP_URL]: new Response(APPCAST_XML) })

    const response = await call('/appcast-develop.xml')

    expect(response.status).toBe(200)
    expect((await latestEvent())?.channel).toBe('develop')
  })

  it('上流が失敗したら 502 を返す', async () => {
    mockUpstream({ [APPCAST_URL]: new Response('nope', { status: 404 }) })

    const response = await call('/appcast.xml')

    expect(response.status).toBe(502)
  })

  it('R2 に appcast があれば GitHub を読まずにそちらを返す', async () => {
    const r2Body = '<?xml version="1.0"?><rss><channel><title>from-r2</title></channel></rss>'
    await env.DIST.put('appcast.xml', r2Body)
    // GitHub への fetch が起きたらこのスタブが例外を投げる。
    mockUpstream({})

    const response = await call('/appcast.xml')

    expect(response.status).toBe(200)
    expect(await response.text()).toBe(r2Body)
    expect((await latestEvent())?.kind).toBe('update_check')
  })

  it('develop チャンネルも R2 の appcast-develop.xml を見る', async () => {
    await env.DIST.put('appcast-develop.xml', APPCAST_XML)
    mockUpstream({})

    const response = await call('/appcast-develop.xml')

    expect(response.status).toBe(200)
    expect((await latestEvent())?.channel).toBe('develop')
  })

  it('2 回目は Worker 側キャッシュから返し R2 を読まない', async () => {
    await env.DIST.put('appcast.xml', APPCAST_XML)
    mockUpstream({})

    expect((await call('/appcast.xml')).status).toBe(200)

    const get = vi.spyOn(env.DIST, 'get')
    const second = await call('/appcast.xml')

    expect(second.status).toBe(200)
    expect(await second.text()).toBe(APPCAST_XML)
    expect(get).not.toHaveBeenCalled()
  })

  it('キャッシュヒット時も update_check を記録する', async () => {
    await env.DIST.put('appcast.xml', APPCAST_XML)
    mockUpstream({})

    await call('/appcast.xml')
    await call('/appcast.xml')

    const count = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM events WHERE kind = 'update_check'",
    ).first<{ n: number }>()
    expect(count?.n).toBe(2)
  })

  it('チャンネルごとに別のキャッシュを持つ', async () => {
    await env.DIST.put('appcast.xml', APPCAST_XML)
    await env.DIST.put('appcast-develop.xml', DEVELOP_XML)
    mockUpstream({})

    await call('/appcast.xml')
    const develop = await call('/appcast-develop.xml')

    expect(await develop.text()).toBe(DEVELOP_XML)
  })
})

describe('計測の best-effort 性', () => {
  it('D1 が失敗してもレスポンスは成功する', async () => {
    const brokenEnv = {
      ...env,
      DB: {
        prepare() {
          throw new Error('D1 unavailable')
        },
      } as unknown as D1Database,
    }
    const request = new Request('https://befold.example/', { headers: { 'User-Agent': UA } })
    const ctx = createExecutionContext()

    const response = await app.fetch(request, brokenEnv, ctx)
    await waitOnExecutionContext(ctx)

    expect(response.status).toBe(200)
    expect(await latestEvent()).toBeNull()
  })
})

describe('プライバシー', () => {
  it('生 IP と完全 UA は保存しない', async () => {
    await call('/')

    const event = await latestEvent()
    const stored = JSON.stringify(event)
    expect(stored).not.toContain(IP)
    expect(stored).not.toContain('AppleWebKit')
    expect(event?.os).toBe('macOS 14.5')
    expect(event?.ua_summary).toBe('Safari')
    expect(event?.visitor_token).toMatch(/^[0-9a-f]{64}$/u)
  })
})

describe('OGP メタタグ', () => {
  it('og:image と og:url をリクエストの origin から絶対 URL で出す', async () => {
    const html = await (await call('/')).text()

    expect(html).toContain(
      '<meta property="og:image" content="https://befold.example/images/ogp.png"/>',
    )
    expect(html).toContain('<meta property="og:url" content="https://befold.example/"/>')
  })

  it('twitter:card は大判カードにする', async () => {
    const html = await (await call('/')).text()

    expect(html).toContain('<meta name="twitter:card" content="summary_large_image"/>')
  })

  it('ホストが変わっても og:url がそのホストを指す（ハードコードしない）', async () => {
    const request = new Request('https://befold-staging.example/', {
      headers: { 'User-Agent': UA, 'CF-Connecting-IP': IP, 'CF-IPCountry': 'JP' },
    })
    const ctx = createExecutionContext()
    const html = await (await app.fetch(request, env, ctx)).text()
    await waitOnExecutionContext(ctx)

    expect(html).toContain('<meta property="og:url" content="https://befold-staging.example/"/>')
    expect(html).toContain(
      '<meta property="og:image" content="https://befold-staging.example/images/ogp.png"/>',
    )
  })

  it('og:title と og:description は title / description と同じ文字列にする', async () => {
    const html = await (await call('/')).text()

    const title = html.match(/<title>(.*?)<\/title>/u)?.[1]
    const description = html.match(/<meta name="description" content="(.*?)"\/>/u)?.[1]

    expect(title).toBeTruthy()
    expect(description).toBeTruthy()
    expect(html).toContain(`<meta property="og:title" content="${title}"/>`)
    expect(html).toContain(`<meta property="og:description" content="${description}"/>`)
  })
})

describe('対象 OS の明示', () => {
  it('ファーストビューのリード文で Mac 専用だと分かる（各言語の URL で）', async () => {
    const ja = (await (await call('/')).text()).match(
      /<section class="hero">([\s\S]*?)<\/section>/u,
    )?.[1]
    const en = (await (await call('/en')).text()).match(
      /<section class="hero">([\s\S]*?)<\/section>/u,
    )?.[1]

    expect(ja).toContain('Mac 専用')
    expect(en).toContain('Mac-only')
    // 言語ごとに URL が分かれた以上、片方の本文にもう片方の言語は出ない。
    expect(ja).not.toContain('Mac-only')
    expect(en).not.toContain('Mac 専用')
  })

  it('ダウンロードボタンの近辺で macOS 14 以降だと分かる', async () => {
    for (const [path, note] of [
      ['/', 'macOS 14 (Sonoma) 以降が必要です'],
      ['/en', 'Requires macOS 14 (Sonoma) or later'],
    ]) {
      const html = await (await call(path as string)).text()
      const hero = html.match(/<section class="hero">([\s\S]*?)<\/section>/u)?.[1] ?? ''

      expect(hero, path).toContain(note)
      // 注記はボタンより後ろに置き、クリック前に目に入るようにする。
      expect(hero.indexOf('btn-primary'), path).toBeLessThan(hero.indexOf('hero-note'))
    }
  })
})

describe('構造化データ (JSON-LD)', () => {
  it('SoftwareApplication として macOS 専用・ダウンロード先を示す', async () => {
    const html = await (await call('/')).text()
    const json = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/u)?.[1]

    expect(json).toBeTruthy()
    const data = JSON.parse(json as string)
    expect(data['@type']).toBe('SoftwareApplication')
    expect(data.operatingSystem).toBe('macOS 14 (Sonoma) or later')
    expect(data.applicationCategory).toBe('DeveloperApplication')
    expect(data.downloadUrl).toBe('https://befold.example/download')
    expect(data.url).toBe('https://befold.example/')
  })

  it('description は <meta name="description"> と同じ文字列にする', async () => {
    const html = await (await call('/')).text()
    const description = html.match(/<meta name="description" content="(.*?)"\/>/u)?.[1]
    const json = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/u)?.[1]

    expect(JSON.parse(json as string).description).toBe(description)
  })
})

describe('robots.txt / sitemap.xml', () => {
  it('robots.txt は 200 / text/plain で dashboard を除外し sitemap を指す', async () => {
    const response = await call('/robots.txt')

    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toContain('text/plain')
    const body = await response.text()
    expect(body).toContain('Disallow: /dashboard')
    expect(body).toContain('Sitemap: https://befold.example/sitemap.xml')
  })

  it('sitemap.xml は 200 / application/xml で公開ページのみ列挙する', async () => {
    const response = await call('/sitemap.xml')

    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toContain('application/xml')
    const body = await response.text()
    // SITE_PAGES の全バリアントが載る。ここが表とずれると、追加した言語ページが
    // クロールされないまま気づけない。
    for (const entry of SITE_PAGES) {
      expect(body, entry.path).toContain(`<loc>https://befold.example${entry.path}</loc>`)
    }
    expect(body.match(/<loc>/gu)).toHaveLength(SITE_PAGES.length)
    expect(body).not.toContain('/dashboard')
    expect(body).not.toContain('/healthz')
  })

  it('robots.txt / sitemap.xml はアクセスを visit として記録しない', async () => {
    await call('/robots.txt')
    await call('/sitemap.xml')

    expect(await latestEvent()).toBeNull()
  })
})

describe('GET /features', () => {
  it('200 を返し、機能・対応ファイルタイプ・ショートカット・FAQ を含む', async () => {
    const response = await call('/features')

    expect(response.status).toBe(200)
    const body = await response.text()
    expect(body).toContain('対応ファイルタイプ')
    expect(body).toContain('キーボードショートカット')
    expect(body).toContain('よくある質問')
  })

  it('英語版は /en/features にあり、日本語の本文は出ない', async () => {
    const response = await call('/en/features')

    expect(response.status).toBe(200)
    const body = bodyOf(await response.text())
    expect(body).toContain('Supported File Types')
    expect(body).toContain('Keyboard Shortcuts')
    expect(body).toContain('Frequently Asked Questions')
    expect(body).not.toContain('対応ファイルタイプ')
  })

  it('日本語版の本文に英語の文面は出ない', async () => {
    // head は判定に含めない。hreflang / og:locale:alternate が相手言語を指すのは
    // 正しい状態で、本文の混在とは別物。
    const body = bodyOf(await (await call('/features')).text())

    expect(body).not.toContain('Supported File Types')
    expect(body).not.toContain('Keyboard Shortcuts')
    // hidden で隠す旧方式が復活していないことも同時に見る。
    expect(body).not.toMatch(/lang="en"[^>]*hidden/u)
  })

  it('対応ファイルタイプ表に主要な拡張子が並ぶ', async () => {
    const body = await (await call('/features')).text()

    for (const extension of ['.mmd', '.md', '.svg', '.html', '.csv', '.tsv', '.pdf', '.swift']) {
      expect(body, `${extension} が表に無い`).toContain(extension)
    }
  })

  it('canonical と og:url が /features を指す', async () => {
    const body = await (await call('/features')).text()

    expect(body).toContain('<link rel="canonical" href="https://befold.example/features"/>')
    expect(body).toContain('content="https://befold.example/features"')
  })

  it('FAQPage の JSON-LD を出力する', async () => {
    const body = await (await call('/features')).text()
    const json = body.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/u)?.[1]

    expect(json).toBeTruthy()
    const data = JSON.parse(json as string)
    expect(data['@type']).toBe('FAQPage')
    expect(Array.isArray(data.mainEntity)).toBe(true)
    expect(data.mainEntity.length).toBeGreaterThan(0)

    for (const entry of data.mainEntity) {
      expect(entry['@type']).toBe('Question')
      expect(entry.name.length).toBeGreaterThan(0)
      expect(entry.acceptedAnswer['@type']).toBe('Answer')
      // 構造化データの答えはページ上に見えている必要がある。
      expect(body).toContain(entry.acceptedAnswer.text.slice(0, 40))
    }
  })

  it('page=/features の visit として記録する', async () => {
    await call('/features')

    const event = await latestEvent()
    expect(event?.kind).toBe('visit')
    expect(event?.page).toBe('/features')
  })

  it('キャッシュに載せない（載ると Worker を通らず計上できない）', async () => {
    const response = await call('/features')

    // ヘッダを外すだけでは足りない。Cache-Control も Expires も無い 200 応答は
    // ブラウザのヒューリスティックキャッシュに載り得るため、明示して固定する。
    expect(response.headers.get('Cache-Control')).toBe('no-store')
  })
})

describe('ブラウザ言語設定の記録', () => {
  it('Accept-Language の第一タグを ja / en / other に丸めて記録する', async () => {
    const cases: [string, string][] = [
      ['ja,en-US;q=0.9', 'ja'],
      ['en-US,en;q=0.9', 'en'],
      ['fr-FR,fr;q=0.9', 'other'],
    ]

    for (const [header, expected] of cases) {
      await call('/', { 'Accept-Language': header })
      expect((await latestEvent())?.browser_lang, header).toBe(expected)
    }
  })

  it('Accept-Language が無いリクエストでは NULL になる', async () => {
    // Sparkle の自動更新はこのヘッダを送らない。記録処理自体は止めない。
    await call('/dl/v1.0.0/befold-1.0.0.dmg', { 'Accept-Language': '' })

    const event = await latestEvent('download')
    expect(event?.kind).toBe('download')
    expect(event?.browser_lang).toBeNull()
  })

  it('visit 以外の kind では page が NULL になる', async () => {
    await call('/dl/v1.0.0/befold-1.0.0.dmg')

    const event = await latestEvent('download')
    expect(event?.kind).toBe('download')
    expect(event?.page).toBeNull()
  })
})
