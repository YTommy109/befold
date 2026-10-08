import { env } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'

import { DASHBOARD_PAGES, EVENTS_PAGE_LIMIT, summarizeOverview } from '../src/analytics'
import { LEGACY_HOST, LEGACY_STAGING_HOST } from '../src/lib/hosts'
import { renderOverviewSections } from '../src/views/dashboard'
import { AUTH_HEADERS, PAGE, call, seed, signJwt, useDashboardFixtures } from './dashboard-helpers'

useDashboardFixtures()

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
    // 概要面に残るダウンロード指標は新規とアップデートのみ。内訳とアップデート確認は流入面へ移した。
    expect(overview).toContain('<span class="value" id="count-download-new">2</span>')
    expect(overview).not.toContain('id="count-update_check"')
    expect(traffic).toContain('<span class="value" id="traffic-download">2</span>')
    expect(traffic).toContain('<span class="value" id="traffic-update_check">1</span>')
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
      body.indexOf('ページビュー: 接続元組織別'),
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

    // 並びは KIND_LABELS の順（ページビュー → アップデート確認 → ダウンロード系）。
    const visitOS = body.indexOf('ページビュー: OS 別')
    const updateOS = body.indexOf('アップデート確認: OS 別')
    const downloadOS = body.indexOf('ダウンロード（LP）: OS 別')
    expect(visitOS).toBeGreaterThan(-1)
    expect(updateOS).toBeGreaterThan(visitOS)
    expect(downloadOS).toBeGreaterThan(updateOS)
    // 各指標の表には、その指標のイベントの OS だけが現れる
    expect(body.slice(visitOS, updateOS)).toContain('macOS 14.5')
    expect(body.slice(visitOS, updateOS)).not.toContain('macOS 15.0')
    expect(body.slice(updateOS, downloadOS)).toContain('macOS 13.6')
    expect(body.slice(updateOS, downloadOS)).not.toContain('macOS 15.0')
    expect(body.slice(downloadOS)).toContain('macOS 15.0')
  })

  it('接続元組織別が 3 指標それぞれに分かれて集計される', async () => {
    await seed('visit', { asOrg: 'IIJ Internet' })
    await seed('download', { asOrg: 'NTT Communications' })
    await seed('update_check', { asOrg: 'KDDI CORPORATION' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    const visitOrg = body.indexOf('ページビュー: 接続元組織別')
    const updateOrg = body.indexOf('アップデート確認: 接続元組織別')
    const downloadOrg = body.indexOf('ダウンロード（LP）: 接続元組織別')
    expect(visitOrg).toBeGreaterThan(-1)
    expect(updateOrg).toBeGreaterThan(visitOrg)
    expect(downloadOrg).toBeGreaterThan(updateOrg)
    expect(body.slice(visitOrg, updateOrg)).toContain('IIJ Internet')
    expect(body.slice(visitOrg, updateOrg)).not.toContain('NTT Communications')
    expect(body.slice(updateOrg, downloadOrg)).toContain('KDDI CORPORATION')
    expect(body.slice(downloadOrg)).toContain('NTT Communications')
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
