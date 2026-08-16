import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest'

import { DASHBOARD_PAGES, EVENTS_PAGE_LIMIT, summarizeOverview } from '../src/analytics'

/** 面ごとの URL。`DASHBOARD_PAGES` の path と対になる。 */
const PAGE = {
  overview: '/dashboard',
  users: '/dashboard/users',
  traffic: '/dashboard/traffic',
  delivery: '/dashboard/delivery',
  events: '/dashboard/events',
} as const
import app from '../src/index'
import { LEGACY_HOST, LEGACY_STAGING_HOST } from '../src/lib/hosts'
import { formatJst } from '../src/lib/jst'
import { renderOverviewSections } from '../src/views/dashboard'
import { installAccessKeys, removeAccessKeys } from './access-helpers'

/**
 * Access が付ける JWT ヘッダ。中身は beforeAll で埋める（署名に鍵生成が要る）。
 * 参照は同じオブジェクトのまま各テストへ渡るので、ここを書き換えれば全体に効く。
 */
const AUTH_HEADERS: Record<string, string> = {}

let signJwt: (claims: Record<string, unknown>) => Promise<string>

beforeAll(async () => {
  const access = await installAccessKeys()
  signJwt = access.sign
  Object.assign(AUTH_HEADERS, await access.headers())
})

afterAll(() => {
  removeAccessKeys()
})

async function call(
  path: string,
  headers: Record<string, string> = {},
  overrides: Partial<Env> = {},
  origin = 'https://befold.degino.com',
): Promise<Response> {
  const request = new Request(`${origin}${path}`, { headers })
  const ctx = createExecutionContext()
  const response = await app.fetch(request, { ...env, ...overrides }, ctx)
  await waitOnExecutionContext(ctx)
  return response
}

/** テスト用のイベントを 1 件投入し、その id を返す。 */
async function seed(
  kind: string,
  extra: {
    version?: string
    country?: string
    os?: string
    visitorDay?: string
    channel?: string | null
    ts?: number
    referrer?: string
    asOrg?: string
    uaSummary?: string
    page?: string
    displayLang?: string
    browserLang?: string
    appVersion?: string | null
  } = {},
): Promise<number> {
  const result = await env.DB.prepare(
    'INSERT INTO events' +
      ' (timestamp, kind, version, channel, country, os, ua_summary, visitor_token, referrer,' +
      ' as_org, page, display_lang, browser_lang, app_version)' +
      ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id',
  )
    .bind(
      extra.ts ?? Date.now(),
      kind,
      extra.version ?? null,
      extra.channel === undefined ? 'stable' : extra.channel,
      extra.country ?? null,
      extra.os ?? null,
      extra.uaSummary ?? 'Safari',
      extra.visitorDay ?? 'hash-a',
      extra.referrer ?? null,
      extra.asOrg ?? null,
      extra.page ?? null,
      extra.displayLang ?? null,
      extra.browserLang ?? null,
      extra.appVersion ?? null,
    )
    .first<{ id: number }>()

  return result?.id ?? 0
}

afterEach(async () => {
  await env.DB.prepare('DELETE FROM events').run()
})

describe('Cloudflare Access による保護', () => {
  it('JWT が無ければ 401 を返す', async () => {
    expect((await call('/dashboard')).status).toBe(401)
    expect((await call('/dashboard/stream')).status).toBe(401)
  })

  it('署名が壊れた JWT は 403 を返す', async () => {
    const token = await signJwt({})
    const tampered = { 'Cf-Access-Jwt-Assertion': `${token.slice(0, -4)}AAAA` }

    expect((await call('/dashboard', tampered)).status).toBe(403)
  })

  it('別アプリ向けの AUD を持つ JWT は 403 を返す', async () => {
    const headers = { 'Cf-Access-Jwt-Assertion': await signJwt({ aud: ['other-app'] }) }

    expect((await call('/dashboard', headers)).status).toBe(403)
  })

  it('発行者が team domain と違う JWT は 403 を返す', async () => {
    const headers = {
      'Cf-Access-Jwt-Assertion': await signJwt({ iss: 'https://evil.cloudflareaccess.com' }),
    }

    expect((await call('/dashboard', headers)).status).toBe(403)
  })

  it('期限切れの JWT は 403 を返す', async () => {
    const expired = Math.floor(Date.now() / 1000) - 60
    const headers = { 'Cf-Access-Jwt-Assertion': await signJwt({ exp: expired }) }

    expect((await call('/dashboard', headers)).status).toBe(403)
  })

  it('Access が未設定なら 503 で閉じる（素通しさせない）', async () => {
    const response = await call('/dashboard', AUTH_HEADERS, {
      ACCESS_AUD: '',
    } as Partial<Env>)

    expect(response.status).toBe(503)
  })

  it('未設定でも localhost 以外は素通ししない', async () => {
    const response = await call('/dashboard', AUTH_HEADERS, { ACCESS_AUD: '' } as Partial<Env>)

    expect(response.status).not.toBe(200)
  })

  it('ローカル開発（localhost かつ未設定）だけは素通しする', async () => {
    const response = await call(
      '/dashboard',
      {},
      { ACCESS_TEAM_DOMAIN: '', ACCESS_AUD: '' } as Partial<Env>,
      'http://localhost:8787',
    )

    expect(response.status).toBe(200)
  })

  it('有効な JWT なら 200 を返す', async () => {
    expect((await call('/dashboard', AUTH_HEADERS)).status).toBe(200)
  })

  it('旧ホストの /dashboard と /dashboard/* は 404 を返す', async () => {
    for (const host of [LEGACY_HOST, LEGACY_STAGING_HOST]) {
      const origin = `https://${host}`

      expect((await call('/dashboard', AUTH_HEADERS, {}, origin)).status).toBe(404)
      expect((await call('/dashboard/stream', AUTH_HEADERS, {}, origin)).status).toBe(404)
    }
  })

  it('公開ルートは JWT が無くても 200 のままである', async () => {
    expect((await call('/')).status).toBe(200)
  })
})

describe('面ごとのルート', () => {
  /** `DASHBOARD_PAGES` の path をダッシュボード配下の URL にする。 */
  const urlOf = (path: string): string => (path === '/' ? '/dashboard' : `/dashboard${path}`)

  it.each(DASHBOARD_PAGES.map((page) => [page.key, urlOf(page.path)] as const))(
    '%s（%s）が認証済みで開ける',
    async (_key, url) => {
      expect((await call(url, AUTH_HEADERS)).status).toBe(200)
    },
  )

  it.each(DASHBOARD_PAGES.map((page) => [page.key, urlOf(page.path)] as const))(
    '%s（%s）は JWT が無ければ 401',
    async (_key, url) => {
      expect((await call(url)).status).toBe(401)
    },
  )

  it.each(DASHBOARD_PAGES.map((page) => [page.key, urlOf(page.path)] as const))(
    '%s（%s）は JWT が壊れていれば 403',
    async (_key, url) => {
      const tampered = {
        'Cf-Access-Jwt-Assertion': `${AUTH_HEADERS['Cf-Access-Jwt-Assertion'] ?? ''}x`,
      }
      expect((await call(url, tampered)).status).toBe(403)
    },
  )

  it.each(DASHBOARD_PAGES.map((page) => [page.key, urlOf(page.path)] as const))(
    '%s（%s）は旧ホストでは 404',
    async (_key, url) => {
      expect((await call(url, AUTH_HEADERS, {}, `https://${LEGACY_HOST}`)).status).toBe(404)
    },
  )

  it('どの面からも他のすべての面へ移動できる', async () => {
    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    for (const page of DASHBOARD_PAGES) expect(body).toContain(page.title)
    // 現在地はリンクにしない（押しても同じ場所なので）。
    expect(body).toContain('aria-current="page"')
  })

  it('ライブ更新しない面には SSE の状態表示を出さない', async () => {
    const overview = await (await call('/dashboard', AUTH_HEADERS)).text()
    const users = await (await call(PAGE.users, AUTH_HEADERS)).text()
    // イベント面もスナップショット。過去を見ている最中に先頭へ行が挿さると
    // 読んでいる位置がずれるので、ライブ追記しないことを固定する。
    const events = await (await call(PAGE.events, AUTH_HEADERS)).text()

    expect(overview).toContain('id="stream-status"')
    for (const body of [users, events]) {
      expect(body).not.toContain('id="stream-status"')
      expect(body).toContain('スナップショット')
    }
  })
})

describe('イベント面', () => {
  it('概要面からイベント面への導線がある', async () => {
    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('href="/dashboard/events"')
  })

  it('イベントが 1 件も無ければその旨を出す（空の表を出さない）', async () => {
    const body = await (await call(PAGE.events, AUTH_HEADERS)).text()

    expect(body).toContain('該当するイベントはありません')
  })

  it('先頭ページでは古い側へのリンクだけが出る', async () => {
    // 上限 + 1 件入れて 2 ページにする。
    for (let index = 0; index <= EVENTS_PAGE_LIMIT; index += 1) {
      // seed は 1 件ずつ id を返す（並行にすると id の並びが読めなくなる）。
      await seed('visit', { page: '/' })
    }

    const body = await (await call(PAGE.events, AUTH_HEADERS)).text()

    expect(body).toContain('?before=')
    expect(body).not.toContain('?after=')
  })

  it('カーソルを指定すると新しい側へ戻るリンクが出る', async () => {
    const first = await seed('visit', { page: '/' })
    const second = await seed('visit', { page: '/features' })

    const body = await (await call(`${PAGE.events}?before=${second}`, AUTH_HEADERS)).text()

    expect(body).toContain(`?after=${first}`)
    // 基準より古い行だけが載る（基準の行そのものは前のページに出ている）。
    expect(body).toContain('<td>/</td>')
    expect(body).not.toContain('<td>/features</td>')
  })

  it('壊れたカーソルでも 500 にせず最新のページを出す', async () => {
    await seed('visit', { page: '/' })

    const response = await call(`${PAGE.events}?before=abc`, AUTH_HEADERS)

    expect(response.status).toBe(200)
    expect(await response.text()).toContain('<td>/</td>')
  })
})

describe('集計の表示', () => {
  it('日付・時刻が JST 基準であることが画面に明示される', async () => {
    await seed('visit')

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('日付・時刻はすべて JST (UTC+9) 基準')
  })

  it('JST 基準の明示は SSE の差し替え範囲（#summary）の外に置く', async () => {
    await seed('visit')

    const summaryHtml = renderOverviewSections(await summarizeOverview(env.DB, Date.now()))

    // #summary は SSE が毎周期 innerHTML で丸ごと置き換えるため、
    // 静的なテキストを含めない（含めると毎回同じ文字列を送り直すことになる）。
    expect(summaryHtml).not.toContain('日付・時刻はすべて JST (UTC+9) 基準')
  })

  it('種別ごとの合計・バージョン別・国別・OS 別が描画される', async () => {
    await seed('visit', { country: 'JP', os: 'macOS 14.5' })
    await seed('visit', { country: 'US', os: 'macOS 15.0', visitorDay: 'hash-b' })
    await seed('download', { version: 'v1.10.0', country: 'JP', os: 'macOS 14.5' })
    await seed('download', { version: 'v1.10.0', country: 'JP', os: 'macOS 14.5' })
    await seed('update_check', { country: 'JP', os: 'macOS 14.5' })

    const overview = await (await call(PAGE.overview, AUTH_HEADERS)).text()
    const users = await (await call(PAGE.users, AUTH_HEADERS)).text()
    const traffic = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    expect(overview).toContain('<span class="value" id="count-visit">2</span>')
    expect(overview).toContain('<span class="value" id="count-download">2</span>')
    expect(overview).toContain('<span class="value" id="count-update_check">1</span>')
    // 延べ訪問者は visitor_token の異なり数（hash-a / hash-b）
    expect(overview).toContain('<span class="value">2</span>')
    expect(traffic).toContain('v1.10.0')
    expect(traffic).toContain('macOS 15.0')
    // セクション見出しから集計期間が読み取れる。面をまたいでも読み取れることを、
    // 面ごとに確かめる（1 ページに全部あった頃の担保を落とさない）。
    expect(overview).toContain('<h2>累計（全期間）</h2>')
    expect(overview).toContain('<h2>本日（JST 0 時から）</h2>')
    expect(overview).toContain('<h2>日毎の推移（直近 14 日）</h2>')
    expect(users).toContain('<h2>時間帯分布（直近 14 日・JST）</h2>')
    expect(traffic).toContain('<h2>内訳（全期間の累計）</h2>')
  })

  it('参照元別が上位順で描画され、参照元なしは集計から除かれる', async () => {
    await seed('visit', { referrer: 'gh-pages' })
    await seed('visit', { referrer: 'gh-pages' })
    await seed('visit', { referrer: 'https://news.ycombinator.com' })
    await seed('visit')

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    expect(body).toContain('参照元別')
    expect(body).toContain('gh-pages')
    expect(body).toContain('https://news.ycombinator.com')
    expect(body.indexOf('gh-pages')).toBeLessThan(body.indexOf('https://news.ycombinator.com'))
  })

  it('接続元組織別が上位順で描画され、組織なしは集計から除かれる', async () => {
    await seed('visit', { asOrg: 'IIJ Internet' })
    await seed('visit', { asOrg: 'IIJ Internet' })
    await seed('visit', { asOrg: 'NTT Communications' })
    await seed('visit')

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    expect(body).toContain('接続元組織別')
    expect(body).toContain('IIJ Internet')
    expect(body).toContain('NTT Communications')
    expect(body.indexOf('IIJ Internet')).toBeLessThan(body.indexOf('NTT Communications'))
  })

  it('人間の訪問とロボットの巡回が分離して描画され、ロボットは種類別に見える', async () => {
    await seed('visit', { uaSummary: 'bot:GPTBot' })
    await seed('visit', { uaSummary: 'bot:GPTBot' })
    await seed('visit', { uaSummary: 'bot:other' })
    await seed('visit', { uaSummary: 'Safari' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    expect(body).toContain('<h2>人間の訪問と自動アクセス（全期間の累計）</h2>')
    expect(body).toContain(
      '<span class="value">3</span><span class="label">ロボット（クローラ）</span>',
    )
    expect(body).toContain(
      '<span class="value">1</span><span class="label">人間のクライアント</span>',
    )

    const humanTable = body.indexOf('人間: クライアント種別')
    const botTable = body.indexOf('ロボット: 種類別')
    expect(humanTable).toBeGreaterThan(-1)
    expect(botTable).toBeGreaterThan(humanTable)
    // 種類は人間側の表に混ざらず、ロボット側の表にだけ現れる。
    expect(body.slice(humanTable, botTable)).not.toContain('bot:GPTBot')
    expect(body.slice(botTable)).toContain('bot:GPTBot')
    expect(body.slice(botTable)).toContain('bot:other')
  })

  it('ページ別の訪問が人間とロボットに分かれて描画される', async () => {
    await seed('visit', { page: '/' })
    await seed('visit', { page: '/features' })
    await seed('visit', { page: '/features', uaSummary: 'bot:GPTBot' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    expect(body).toContain('<h2>ページ別の訪問（全期間の累計）</h2>')

    const humanTable = body.indexOf('人間: ページ別')
    const botTable = body.indexOf('自動アクセス: ページ別')
    expect(humanTable).toBeGreaterThan(-1)
    expect(botTable).toBeGreaterThan(humanTable)
    // 人間側には / と /features が 1 件ずつ、ロボット側には /features だけが出る。
    const human = body.slice(humanTable, botTable)
    expect(human).toContain('<td>/</td><td>1</td>')
    expect(human).toContain('<td>/features</td><td>1</td>')
    const bot = body.slice(botTable, body.indexOf('<h2>言語別の訪問'))
    expect(bot).toContain('<td>/features</td><td>1</td>')
    expect(bot).not.toContain('<td>/</td>')
  })

  it('visit 以外の kind はページ別の内訳に入らない', async () => {
    // download / update_check には元々ページが無い。COALESCE(page,'/') が kind の
    // 条件から外れると、これらが LP の訪問として数えられてしまう。
    await seed('download')
    await seed('update_check')

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()
    const section = body.slice(body.indexOf('<h2>ページ別の訪問'), body.indexOf('<h2>言語別の訪問'))

    expect(section).toContain('データなし')
    expect(section).not.toContain('<td>/</td>')
  })

  it('表示言語とブラウザ言語設定が別々の表として描画される', async () => {
    // 英語設定のブラウザが日本語ページを見ている状態。両方を出さないと
    // 「英語を求めて来た人が英語ページへ辿り着けたか」が読めない。
    await seed('visit', { page: '/', displayLang: 'ja', browserLang: 'en' })
    await seed('visit', { page: '/en', displayLang: 'en', browserLang: 'en' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    expect(body).toContain('<h2>言語別の訪問（全期間の累計）</h2>')
    const section = body.slice(
      body.indexOf('<h2>言語別の訪問'),
      body.indexOf('<h2>人間の訪問と自動アクセス'),
    )
    expect(section).toContain('人間: 表示言語別')
    expect(section).toContain('人間: ブラウザ言語設定別')
    expect(section).toContain('自動アクセス: 表示言語別')
    expect(section).toContain('自動アクセス: ブラウザ言語設定別')

    const display = section.slice(
      section.indexOf('人間: 表示言語別'),
      section.indexOf('自動アクセス: 表示言語別'),
    )
    expect(display).toContain('<td>ja</td><td>1</td>')
    expect(display).toContain('<td>en</td><td>1</td>')

    const browser = section.slice(section.indexOf('人間: ブラウザ言語設定別'))
    expect(browser).toContain('<td>en</td><td>2</td>')
  })

  it('言語の内訳がブラウザ設定と実表示の別を注記で示す', async () => {
    await seed('visit', { page: '/', displayLang: 'ja', browserLang: 'en' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()
    const section = body.slice(
      body.indexOf('<h2>言語別の訪問'),
      body.indexOf('<h2>人間の訪問と自動アクセス'),
    )

    // 指標の意味を取り違えたまま読まれるのが一番まずいので、注記の存在を固定する。
    expect(section).toContain('ブラウザの設定であって実際に読まれた言語ではない')
    // 遡って埋められない行があることも示す。
    expect(section).toContain('2026-08-16')
    expect(section).toContain('未記録')
  })

  it('言語ごとの URL を分ける前に記録された訪問は未記録として出る', async () => {
    await seed('visit', { page: '/' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()
    const section = body.slice(
      body.indexOf('人間: 表示言語別'),
      body.indexOf('自動アクセス: 表示言語別'),
    )

    expect(section).toContain('<td>未記録</td><td>1</td>')
  })

  it('最新イベント表で / と /features の visit が見分けられる', async () => {
    await seed('visit', { page: '/features' })

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()
    const section = body.slice(body.indexOf('<h2>最新イベント'))

    expect(section).toContain('<th>ページ</th>')
    expect(section).toContain('<td>/features</td>')
  })

  it('ページを持たない kind は最新イベント表で空欄になる', async () => {
    // '/' を補うと、ダウンロードが LP の訪問に見える。
    await seed('download')

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()
    const section = body.slice(body.indexOf('<h2>最新イベント'))

    expect(section).toContain('<td>download</td>')
    expect(section).not.toContain('<td>/</td>')
  })

  it('過去データを遡って分類できないことが注記から読み取れる', async () => {
    await seed('visit', { uaSummary: 'bot:GPTBot' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    expect(body).toContain('2026-08-09')
    expect(body).toContain('イベントは<strong>遡って分類できず</strong>')
  })

  it('ふたつの判定軸で遡及の効き方が違うことが注記から読み取れる', async () => {
    // UA 分類は適用日以降しか効かず、接続元組織の判定は全期間に効く（ADR 0008）。
    // 片方だけを読むと、同じ日の数字が前に見たときと違う理由が分からなくなる。
    await seed('visit', { uaSummary: 'bot:GPTBot' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()
    const section = body.slice(body.indexOf('<h2>人間の訪問と自動アクセス'))

    expect(section).toContain('イベントは<strong>遡って分類できず</strong>')
    expect(section).toContain('<strong>全期間に遡って効く</strong>')
    // as_org 列を足した日より前は判定材料が無いことも示す。
    expect(section).toContain('2026-07-30')
  })

  it('データセンター由来を分けて数え、接続元組織の内訳が読める', async () => {
    // UA だけを見ていた頃はこれらが「人間の訪問」に入っていた（TASK-490）。
    await seed('visit', { asOrg: 'Amazon Data Services Northern Virginia' })
    await seed('visit', { asOrg: 'Driftnet Ltd' })
    await seed('visit', { asOrg: 'IIJ Internet' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    expect(body).toContain(
      '<span class="value">2</span><span class="label">データセンター由来</span>',
    )
    expect(body).toContain(
      '<span class="value">1</span><span class="label">人間のクライアント</span>',
    )

    // 除外した量が画面から消えないよう、接続元組織の内訳を出す。
    const table = body.indexOf('データセンター: 接続元組織別')
    expect(table).toBeGreaterThan(-1)
    expect(body.slice(table)).toContain('Driftnet Ltd')
    // 人間側の「接続元組織別」からは外れる（HUMAN_ONLY が効いている）。
    const humanOrg = body.slice(
      body.indexOf('ページアクセス: 接続元組織別'),
      body.indexOf('<h2>人間の訪問と自動アクセス'),
    )
    expect(humanOrg).toContain('IIJ Internet')
    expect(humanOrg).not.toContain('Driftnet Ltd')
  })

  it('他の集計がロボットを除いた数であることが注記から読み取れる', async () => {
    await seed('visit', { uaSummary: 'bot:GPTBot' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    expect(body).toContain('ロボットとデータセンター由来の<strong>両方</strong>を除いた数')
  })

  it('OS 別が 3 指標それぞれに分かれて集計される', async () => {
    await seed('visit', { os: 'macOS 14.5' })
    await seed('download', { os: 'macOS 15.0' })
    await seed('update_check', { os: 'macOS 13.6' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    const visitOS = body.indexOf('ページアクセス: OS 別')
    const downloadOS = body.indexOf('ダウンロード: OS 別')
    const updateOS = body.indexOf('アップデート確認: OS 別')
    expect(visitOS).toBeGreaterThan(-1)
    expect(downloadOS).toBeGreaterThan(visitOS)
    expect(updateOS).toBeGreaterThan(downloadOS)
    // 各指標の表には、その指標のイベントの OS だけが現れる
    expect(body.slice(visitOS, downloadOS)).toContain('macOS 14.5')
    expect(body.slice(visitOS, downloadOS)).not.toContain('macOS 15.0')
    expect(body.slice(downloadOS, updateOS)).toContain('macOS 15.0')
    expect(body.slice(downloadOS, updateOS)).not.toContain('macOS 13.6')
    expect(body.slice(updateOS)).toContain('macOS 13.6')
  })

  it('接続元組織別が 3 指標それぞれに分かれて集計される', async () => {
    await seed('visit', { asOrg: 'IIJ Internet' })
    await seed('download', { asOrg: 'NTT Communications' })
    await seed('update_check', { asOrg: 'KDDI CORPORATION' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    const visitOrg = body.indexOf('ページアクセス: 接続元組織別')
    const downloadOrg = body.indexOf('ダウンロード: 接続元組織別')
    const updateOrg = body.indexOf('アップデート確認: 接続元組織別')
    expect(visitOrg).toBeGreaterThan(-1)
    expect(downloadOrg).toBeGreaterThan(visitOrg)
    expect(updateOrg).toBeGreaterThan(downloadOrg)
    expect(body.slice(visitOrg, downloadOrg)).toContain('IIJ Internet')
    expect(body.slice(visitOrg, downloadOrg)).not.toContain('NTT Communications')
    expect(body.slice(downloadOrg, updateOrg)).toContain('NTT Communications')
    expect(body.slice(updateOrg)).toContain('KDDI CORPORATION')
  })

  it('イベントが無くてもエラーにならない', async () => {
    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('<span class="value" id="count-visit">0</span>')
    expect(body).toContain('データなし')
  })

  it('イベントが無いときページ別・言語別の表は「データなし」になる', async () => {
    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()
    const section = body.slice(
      body.indexOf('<h2>ページ別の訪問'),
      body.indexOf('<h2>人間の訪問と自動アクセス'),
    )

    // 6 つの表（ページ / 表示言語 / ブラウザ言語設定 × 人間 / ロボット）すべてが
    // 空状態を出す。0 の行が並ぶ形にならないこともここで固定する。
    expect(section.match(/データなし/gu)).toHaveLength(6)
    expect(section).not.toContain('<td>0</td>')
  })
})

describe('稼働中のアプリバージョンの表示', () => {
  it('チャネルごとの表に稼働バージョンが出る', async () => {
    await seed('update_check', {
      channel: 'stable',
      appVersion: '1.13.1',
      uaSummary: 'Sparkle',
    })
    await seed('update_check', {
      channel: 'develop',
      appVersion: '1.13.2-dev.4',
      uaSummary: 'Sparkle',
      visitorDay: 'hash-b',
    })

    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()

    expect(body).toContain('アプリ（stable）: 稼働バージョン別')
    expect(body).toContain('アプリ（develop）: 稼働バージョン別')
    expect(body).toContain('1.13.1')
    expect(body).toContain('1.13.2-dev.4')
  })

  it('何を 1 と数えているかが画面に書かれている', async () => {
    await seed('update_check', { appVersion: '1.13.1', uaSummary: 'Sparkle' })

    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()

    expect(body).toContain('アップデート確認を送ってきたアクセス元の異なり数')
    expect(body).toContain('確認の延べ回数ではない')
  })

  it('ダウンロード対象タグ別の集計と取り違えない説明がある', async () => {
    await seed('update_check', { appVersion: '1.13.1', uaSummary: 'Sparkle' })

    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()

    expect(body).toContain('バージョン別ダウンロード')
    expect(body).toContain('どのタグを取りに来たか')
    expect(body).toContain('今どのバージョンが動いているか')
  })

  it('遡って分類できない既存行の扱いが注記されている', async () => {
    await seed('update_check', { appVersion: null, uaSummary: 'Sparkle' })

    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()

    expect(body).toContain('遡って分類できない')
  })

  it('データが無くてもチャネルごとの表は消えない', async () => {
    await seed('visit')

    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()

    expect(body).toContain('アプリ（stable）: 稼働バージョン別')
    expect(body).toContain('アプリ（develop）: 稼働バージョン別')
    expect(body).toContain('アプリ（チャネル未記録）: 稼働バージョン別')
  })
})

describe('SSE ストリーム', () => {
  it('after より新しいイベントを push する', async () => {
    const oldId = await seed('visit')
    await seed('download', { version: 'v1.10.0' })

    const response = await call(`/dashboard/stream?after=${oldId}`, AUTH_HEADERS)

    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toContain('text/event-stream')

    const reader = response.body!.getReader()
    const decoder = new TextDecoder()
    let received = ''
    // 初回ポーリング分（接続コメント＋差分）が届くまで読む。
    while (!received.includes('keep-alive')) {
      const { value, done } = await reader.read()
      if (done) break
      received += decoder.decode(value, { stream: true })
    }
    await reader.cancel()

    expect(received).toContain(': connected')
    expect(received).toContain('event: event')
    expect(received).toContain('"kind":"download"')
    expect(received).toContain('"version":"v1.10.0"')
    // after より前のイベントは含まない
    expect(received).not.toContain('"kind":"visit"')
  })

  it('新着イベントがあれば集計セクションの HTML を summary イベントで配信する', async () => {
    const oldId = await seed('visit')
    await seed('download', { version: 'v1.10.0', country: 'JP', os: 'macOS 15.0' })

    const response = await call(`/dashboard/stream?after=${oldId}`, AUTH_HEADERS)
    const reader = response.body!.getReader()
    const decoder = new TextDecoder()
    let received = ''
    while (!received.includes('keep-alive')) {
      const { value, done } = await reader.read()
      if (done) break
      received += decoder.decode(value, { stream: true })
    }
    await reader.cancel()

    expect(received).toContain('event: summary')
    const dataLine = received.split('event: summary\ndata: ')[1]?.split('\n')[0] ?? ''
    const html = JSON.parse(dataLine) as string
    // サーバー側で描画済みの集計表がそのまま届く（クライアントは差し替えるだけ）。
    expect(html).toContain('<h2>日毎の推移（直近 14 日）</h2>')
    expect(html).toContain('v1.10.0')
    expect(html).toContain('<span class="value" id="count-download">1</span>')
    // data 行は 1 行に収まっている
    expect(html).not.toContain('\n')
  })

  it('ロボットの巡回は event として流さないが、集計は配信し直す', async () => {
    // カーソルを人間の行だけで進めると、ボットしか来なかった周期で位置が進まず
    // 集計（ロボットのセクションを含む）が更新されないままになる。
    const oldId = await seed('visit')
    await seed('visit', { uaSummary: 'bot:GPTBot' })

    const response = await call(`/dashboard/stream?after=${oldId}`, AUTH_HEADERS)
    const reader = response.body!.getReader()
    const decoder = new TextDecoder()
    let received = ''
    while (!received.includes('keep-alive')) {
      const { value, done } = await reader.read()
      if (done) break
      received += decoder.decode(value, { stream: true })
    }
    await reader.cancel()

    expect(received).not.toContain('event: event')
    expect(received).toContain('event: summary')
    const dataLine = received.split('event: summary\ndata: ')[1]?.split('\n')[0] ?? ''
    const html = JSON.parse(dataLine) as string
    // 巡回はページアクセス数に入らない。ロボットの内訳そのものは流入面へ移った
    // ため SSE の配信対象ではなく、ここで確かめるのは「ボットしか来なかった周期でも
    // カーソルが進み、集計が配信し直される」ことに絞る。
    expect(html).toContain('<span class="value" id="count-visit">1</span>')
  })

  it('新着イベントが無いポーリング周期では summary を配信しない', async () => {
    const lastId = await seed('visit')

    const response = await call(`/dashboard/stream?after=${lastId}`, AUTH_HEADERS)
    const reader = response.body!.getReader()
    const decoder = new TextDecoder()
    let received = ''
    while (!received.includes('keep-alive')) {
      const { value, done } = await reader.read()
      if (done) break
      received += decoder.decode(value, { stream: true })
    }
    await reader.cancel()

    expect(received).not.toContain('event: summary')
  })
})

/** `<h2>見出し` から次の `<h2>` 直前までを 1 節として切り出す。 */
const section = (html: string, heading: string): string => {
  const start = html.indexOf(`<h2>${heading}`)
  expect(start).toBeGreaterThanOrEqual(0)
  const rest = html.slice(start)
  const end = rest.indexOf('<h2>', 1)
  return end === -1 ? rest : rest.slice(0, end)
}

describe('グラフ描画', () => {
  it('日毎の推移と時間帯分布がインライン SVG で描画される', async () => {
    await seed('visit')
    await seed('download')

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('<svg class="chart"')
    expect(body).toContain('<rect class="chart-bar chart-bar-1"')
    // 外部ホストへのリクエストを発生させない（インライン化されている）。
    expect(body).not.toMatch(/<(script|link|img)[^>]+(src|href)="https?:/u)
  })

  it('系列ごとに別チャートを並べず、1 節 1 枚のグループ化バーチャートにまとめる', async () => {
    await seed('visit')
    await seed('download')

    const daily = section(await (await call(PAGE.overview, AUTH_HEADERS)).text(), '日毎の推移')
    const hourly = section(await (await call(PAGE.users, AUTH_HEADERS)).text(), '時間帯分布')

    expect(daily.match(/<svg class="chart"/gu)).toHaveLength(1)
    expect(hourly.match(/<svg class="chart"/gu)).toHaveLength(1)
    // 日毎・時間帯とも 4 指標。ユニークは母集団が違うので別節へ分けてある。
    expect(daily).toContain('chart-bar-4')
    expect(daily).not.toContain('chart-bar-5')
    expect(hourly).toContain('chart-bar-4')
    expect(hourly).not.toContain('chart-bar-5')
  })

  it('チャートを持つ節には凡例があり、表は置かない', async () => {
    await seed('visit')
    await seed('download', { version: 'v1.10.0', country: 'JP', os: 'macOS 15.0' })

    const daily = section(await (await call(PAGE.overview, AUTH_HEADERS)).text(), '日毎の推移')
    const hourly = section(await (await call(PAGE.users, AUTH_HEADERS)).text(), '時間帯分布')

    expect(daily).toContain('<ul class="legend">')
    expect(daily).toContain('<span class="swatch swatch-4"')
    expect(hourly).toContain('<ul class="legend">')
    // 色以外の手掛かり（凡例の並び順 = グループ内のバーの並び順）を残す。
    expect(daily).toContain('<span class="order">1.</span>')
    expect(daily).not.toContain('<table>')
    expect(hourly).not.toContain('<table>')
    // チャートを持たない節の表は残す（内訳は流入面、最新イベントは概要面）。
    const traffic = await (await call(PAGE.traffic, AUTH_HEADERS)).text()
    const overview = await (await call(PAGE.overview, AUTH_HEADERS)).text()
    expect(section(traffic, '内訳')).toContain('<table>')
    expect(section(overview, '最新イベント')).toContain('<table>')
  })

  it('ユニークアクセス元は母集団・チャネル別の系列として読める', async () => {
    await seed('visit', { visitorDay: 'hash-visit' })
    await seed('update_check', { visitorDay: 'hash-stable', channel: 'stable' })
    await seed('update_check', { visitorDay: 'hash-develop', channel: 'develop' })

    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()
    const unique = section(body, '日別のユニークアクセス元')

    // 母集団 4 系列（サイト訪問 / stable / develop / チャネル未記録）が 1 枚に並ぶ。
    expect(unique.match(/<svg class="chart"/gu)).toHaveLength(1)
    expect(unique).toContain('サイト訪問')
    expect(unique).toContain('アプリ（stable）')
    expect(unique).toContain('アプリ（develop）')
    expect(unique).toContain('アプリ（チャネル未記録）')
    expect(unique).toContain('chart-bar-4')
    expect(unique).not.toContain('chart-bar-5')
    // 混在させたユニーク系列は日毎の推移（概要面）から外してある。
    const overview = await (await call(PAGE.overview, AUTH_HEADERS)).text()
    expect(section(overview, '日毎の推移')).not.toContain('ユニーク')
  })

  it('ユニークアクセス元が近似であることと振れる条件が同じ節に書いてある', async () => {
    await seed('update_check', { visitorDay: 'hash-stable', channel: 'stable' })

    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()
    const unique = section(body, '日別のユニークアクセス元')

    expect(unique).toContain('近似')
    expect(unique).toContain('過大')
    expect(unique).toContain('過小')
    expect(unique).toContain('通算のユニーク利用者数は出せない')
  })

  it('日付・時間帯のラベルを間引かずに全件描く', async () => {
    await seed('visit')

    const overview = await (await call(PAGE.overview, AUTH_HEADERS)).text()
    const users = await (await call(PAGE.users, AUTH_HEADERS)).text()

    // 直近 14 日 + 24 時間帯。
    expect(section(overview, '日毎の推移').match(/class="chart-label"/gu)).toHaveLength(14)
    expect(section(users, '時間帯分布').match(/class="chart-label"/gu)).toHaveLength(24)
  })

  it('SSE で配信される HTML にもグラフと凡例が含まれる（再描画フックが要らない）', async () => {
    await seed('visit')

    const summaryHtml = renderOverviewSections(await summarizeOverview(env.DB, Date.now()))

    expect(summaryHtml).toContain('<svg class="chart"')
    expect(summaryHtml).toContain('<rect class="chart-bar chart-bar-1"')
    expect(summaryHtml).toContain('<ul class="legend">')
  })

  it('データが 0 件でも描画が壊れない', async () => {
    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    // 全系列が 0 件なので棒は描かれず、空状態の文言になる。
    expect(body).toContain('期間内のデータなし')
    expect(body).not.toContain('NaN')
    expect(body).not.toContain('<rect class="chart-bar')
  })

  it('1 点のみ・全値同一でも棒の高さが NaN にならない', async () => {
    // 同じ日・同じ時刻に同数のイベントを置き、最大値と各値が等しい状況にする。
    await seed('visit')
    await seed('visit')

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).not.toContain('NaN')
    expect(body).toContain('<rect class="chart-bar chart-bar-1"')
    // 最大値と等しい棒は棒の描画高さいっぱいになる（180 = 220 - 22 - 18）。
    expect(body).toContain('height="180"')
  })
})

describe('SSE で配信する集計 HTML', () => {
  it('最新イベントのページ列が含まれる', async () => {
    // SSE は #summary を innerHTML で丸ごと置き換える設計なので、
    // OverviewSections に入っていれば差分配信でも更新される。
    await seed('visit', { page: '/features', displayLang: 'en', browserLang: 'en' })

    const summaryHtml = renderOverviewSections(await summarizeOverview(env.DB, Date.now()))

    expect(summaryHtml).toContain('<th>ページ</th>')
    expect(summaryHtml).toContain('<td>/features</td>')
  })

  it('ライブ更新しない面の内容は配信対象に入らない', async () => {
    // ページ別・言語別は流入面へ移った。SSE は概要面だけを差し替えるので、
    // ここに混ざっていたら「面ごとに集計を分けた」前提が破れている。
    await seed('visit', { page: '/features', displayLang: 'en', browserLang: 'en' })

    const summaryHtml = renderOverviewSections(await summarizeOverview(env.DB, Date.now()))

    expect(summaryHtml).not.toContain('<h2>ページ別の訪問（全期間の累計）</h2>')
    expect(summaryHtml).not.toContain('<h2>言語別の訪問（全期間の累計）</h2>')
  })

  it('ページ別・言語別の内訳は流入面で読める', async () => {
    await seed('visit', { page: '/features', displayLang: 'en', browserLang: 'en' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    expect(body).toContain('<h2>ページ別の訪問（全期間の累計）</h2>')
    expect(body).toContain('<h2>言語別の訪問（全期間の累計）</h2>')
    expect(body).toContain('人間: ブラウザ言語設定別')
  })
})

/**
 * 配布ホストと旧経路のセクション。ADR 0007 の停止条件を画面で判定できることを固定する。
 */
describe('配布ホストと旧経路の表示', () => {
  /** ホスト・fallback・UA を指定して 1 件記録する。 */
  async function insertRow(
    kind: string,
    host: string | null,
    fallback: string | null = null,
    uaSummary: string | null = null,
  ): Promise<void> {
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, host, fallback, ua_summary) VALUES (?, ?, ?, ?, ?)',
    )
      .bind(Date.now(), kind, host, fallback, uaSummary)
      .run()
  }

  /** 「配布ホストと旧経路」セクションだけを切り出す。 */
  function hostSection(body: string): string {
    return body.slice(
      body.indexOf('<h2>配布ホストと旧経路'),
      body.indexOf('<h2>人間の訪問と自動アクセス'),
    )
  }

  it('旧ホストへのアクセスを人間とロボットに分けて出す', async () => {
    await insertRow('update_check', 'befold.tommy109.workers.dev')
    await insertRow('legacy_redirect', 'befold.tommy109.workers.dev', null, 'bot:GPTBot')
    await insertRow('visit', 'befold.degino.com')

    const hostHtml = hostSection(await (await call(PAGE.delivery, AUTH_HEADERS)).text())
    // 冒頭の注記にもホスト名が出るので、表の行（<td>）側を見る。
    const legacyCell = hostHtml.indexOf('<td>befold.tommy109.workers.dev</td>')
    expect(legacyCell).toBeGreaterThan(-1)
    expect(hostHtml.slice(legacyCell, legacyCell + 120)).toMatch(
      /<td>befold\.tommy109\.workers\.dev<\/td>\s*<td>1<\/td>\s*<td>1<\/td>/u,
    )
  })

  it('アクセスの無い既知ホストも 0 の行として残る', async () => {
    // 「まだ 0」と「そもそも計測していない」を画面で区別するため、行を落とさない。
    await insertRow('visit', 'befold.degino.com')

    const hostHtml = hostSection(await (await call(PAGE.delivery, AUTH_HEADERS)).text())

    expect(hostHtml).toContain('befold.tommy109.workers.dev')
    expect(hostHtml).toContain('staging.befold.degino.com')
    expect(hostHtml).toContain('<td>0</td>')
  })

  it('GitHub フォールバックを経路別に出す', async () => {
    await insertRow('github_fallback', 'befold.degino.com', 'appcast')

    const hostHtml = hostSection(await (await call(PAGE.delivery, AUTH_HEADERS)).text())

    expect(hostHtml).toContain('appcast')
  })

  it('経路別に最後に発生した時刻を出す', async () => {
    // 累計は一度発生すると減らないので、止めてよいかは最終発生時刻でしか読めない。
    const at = Date.parse('2026-08-08T03:00:00Z')
    await env.DB.prepare('INSERT INTO events (timestamp, kind, host, fallback) VALUES (?, ?, ?, ?)')
      .bind(at, 'github_fallback', 'befold.degino.com', 'dmg')
      .run()

    const hostHtml = hostSection(await (await call(PAGE.delivery, AUTH_HEADERS)).text())

    expect(hostHtml).toContain('最後に発生 (JST)')
    expect(hostHtml).toContain(formatJst(at))
  })

  it('フォールバックが無ければ経路別は「データなし」になる', async () => {
    await insertRow('visit', 'befold.degino.com')

    const hostHtml = hostSection(await (await call(PAGE.delivery, AUTH_HEADERS)).text())
    const fallbackTable = hostHtml.slice(hostHtml.indexOf('GitHub フォールバックの経路別'))

    expect(fallbackTable).toContain('データなし')
  })
})

/**
 * アップデートの取り込み（TASK-493）。率の分母が読めること、リリース公開日の
 * 代用であること、チャネルが混ざらないことを画面の文言で固定する。
 */
describe('アップデートの取り込みの表示', () => {
  /** 同日・同チャネルの確認と sparkle 更新を 1 組入れる。 */
  async function seedPair(day: string, token: string, channel: string): Promise<void> {
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, channel, visitor_token, ua_summary)' +
        " VALUES (?, 'update_check', ?, ?, 'Sparkle')",
    )
      .bind(Date.parse(`${day}T01:00:00Z`) - 9 * 3600 * 1000, channel, token)
      .run()
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, source, channel, version, visitor_token, ua_summary)' +
        " VALUES (?, 'download', 'sparkle', ?, 'v1.13.0', ?, 'Sparkle')",
    )
      .bind(Date.parse(`${day}T02:00:00Z`) - 9 * 3600 * 1000, channel, token)
      .run()
  }

  it('転換率と一緒に分母の実数が出る', async () => {
    const today = new Date().toISOString().slice(0, 10)
    await seedPair(today, 'converted', 'stable')

    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()
    const block = section(body, '確認から更新への転換')

    expect(block).toContain('<th>確認</th>')
    expect(block).toContain('<th>更新</th>')
    expect(block).toContain('<th>転換率</th>')
    expect(block).toContain('100%')
  })

  it('何を分母に数えたかと、それが利用者の割合でないことが書いてある', async () => {
    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()
    const block = section(body, '確認から更新への転換')

    expect(block).toContain('アクセス元×日')
    expect(block).toContain('「更新した利用者の割合」ではない')
  })

  it('確認の記録がない更新を率に混ぜず別の列に出すことが書いてある', async () => {
    const today = new Date().toISOString().slice(0, 10)
    await seedPair(today, 'converted', 'stable')

    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()
    const block = section(body, '確認から更新への転換')

    expect(block).toContain('<th>確認の記録なし</th>')
    expect(block).toContain('100% を超える')
  })

  it('チャネルごとに表が分かれ、データが無くても消えない', async () => {
    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()
    const block = section(body, '確認から更新への転換')

    for (const label of ['アプリ（stable）', 'アプリ（develop）', 'アプリ（チャネル未記録）']) {
      expect(block).toContain(`${label}: 確認 → 更新`)
    }
  })

  it('0 日目がリリース公開日ではないことと、その限界が書いてある', async () => {
    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()
    const block = section(body, 'リリース後の取り込み')

    expect(block).toContain('リリースの公開日ではない')
    expect(block).toContain('最初に観測した日')
    expect(block).toContain('速く見える')
    // LP からのダウンロードを含めないこと（新規獲得と更新の別）も画面から読める。
    expect(block).toContain('配布 LP からのダウンロードは新規獲得なので含めない')
  })

  it('母数が小さいので率ではなく実数で出すことが書いてある', async () => {
    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()
    const block = section(body, 'リリース後の取り込み')

    expect(block).toContain('1 桁')
    expect(block).toContain('率ではなく実数')
  })

  it('タグごとに初回観測日と経過日数ごとの累積が出る', async () => {
    const today = new Date().toISOString().slice(0, 10)
    await seedPair(today, 'a', 'stable')

    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()
    const block = section(body, 'リリース後の取り込み')

    expect(block).toContain('v1.13.0')
    expect(block).toContain('0日目: 1')
  })
})
