import { env } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'

import {
  DOWNLOAD_METRICS,
  newDownloads,
  updateDownloads,
  KIND_LABELS,
  OVERVIEW_METRICS,
  summarizeOverview,
} from '../src/analytics'
import { formatJst } from '../src/lib/jst'
import { renderOverviewSections } from '../src/views/dashboard'
import {
  AUTH_HEADERS,
  EMPTY_COUNTS,
  PAGE,
  call,
  seed,
  useDashboardFixtures,
} from './dashboard-helpers'

useDashboardFixtures()

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
    expect(body).not.toContain('アプリ（develop）: 稼働バージョン別')
    expect(body).toContain('1.13.1')
    // develop は表そのものを出さないので、その版はどこにも現れない。
    expect(countTable(body, 'アプリ（stable）: 稼働バージョン別')).not.toContain('1.13.2-dev.4')
  })

  it('何を 1 と数えているかが画面に書かれている', async () => {
    await seed('update_check', { appVersion: '1.13.1', uaSummary: 'Sparkle' })

    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()

    expect(body).toContain('アップデート確認を送ってきたアクセス元の異なり数')
    expect(body).toContain('確認の延べ回数ではない')
  })

  it('旧バージョンのダウンロードが、どの版へ戻したかまで読める', async () => {
    // 「どのバージョンが旧版として落とされたか」がダッシュボードから分かること
    // （TASK-506）。LP の新規ダウンロードと同じ表に混ぜない。
    await seed('download', { source: 'archive', version: 'v1.12.0' })
    await seed('download', { source: 'lp', version: 'v1.13.2' })

    const body = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    expect(countTable(body, 'ダウンロード（旧バージョン）: バージョン別')).toContain('v1.12.0')
    expect(countTable(body, 'ダウンロード（旧バージョン）: バージョン別')).not.toContain('v1.13.2')
    expect(countTable(body, 'ダウンロード（LP）: バージョン別')).toContain('v1.13.2')
  })

  it('ダウンロード対象タグ別の集計と取り違えない説明がある', async () => {
    await seed('update_check', { appVersion: '1.13.1', uaSummary: 'Sparkle' })

    const body = await (await call(PAGE.users, AUTH_HEADERS)).text()

    expect(body).toContain('ダウンロード（LP）: バージョン別')
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
    expect(body).not.toContain('アプリ（develop）: 稼働バージョン別')
    expect(body).toContain('アプリ（チャネル未記録）: 稼働バージョン別')
  })
})

describe('SSE ストリーム', () => {
  /**
   * ポーリング 1 周期ぶんを読む。周期の終端は末尾の `event: cursor` で判る。
   *
   * 終端の目印を周期末のブロックに置いているので、events / summary を出す順序を
   * 入れ替えても「1 周期ぶん読めた」の意味が変わらない。
   */
  async function readCycle(path: string): Promise<string> {
    const response = await call(path, AUTH_HEADERS)
    expect(response.status).toBe(200)
    const reader = response.body!.getReader()
    const decoder = new TextDecoder()
    let received = ''
    while (!received.includes('event: cursor')) {
      const { value, done } = await reader.read()
      if (done) break
      received += decoder.decode(value, { stream: true })
    }
    await reader.cancel()
    return received
  }

  it('after より新しいイベントを push する', async () => {
    const oldId = await seed('visit')
    await seed('download', { version: 'v1.10.0' })

    const response = await call(`/dashboard/stream?after=${oldId}`, AUTH_HEADERS)

    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toContain('text/event-stream')

    const reader = response.body!.getReader()
    const decoder = new TextDecoder()
    let received = ''
    // 初回ポーリング分（接続コメント＋差分＋周期末の cursor）が届くまで読む。
    while (!received.includes('event: cursor')) {
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
    while (!received.includes('event: cursor')) {
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
    expect(html).toContain('<span class="value" id="count-download-new">1</span>')
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
    while (!received.includes('event: cursor')) {
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

  it('ロボットしか来なかった周期でも再開位置をクライアントへ伝える', async () => {
    // ここが今回の本題（TASK-555）。`event: event` はロボットの行を流さないので、
    // 行ごとの `id:` だけに頼ると **クライアントの Last-Event-ID が一度も進まない**。
    // すると 10 分で切れて再接続するたび、サーバは「ページを開いた時刻からの差分」を
    // 見て `arrived` を真と判定し、いちばん重い経路（summarizeOverview 4 本 +
    // 概要面の全再描画）を接続の 1 周期目で毎回走らせることになる。
    const oldId = await seed('visit')
    const botId = await seed('visit', { uaSummary: 'bot:GPTBot' })

    const received = await readCycle(`/dashboard/stream?after=${oldId}`)

    expect(received).not.toContain('event: event')
    expect(received).toContain(`id: ${botId}\nevent: cursor`)
  })

  it('新着が無い周期でも毎周期 cursor を出す（再開位置が古いまま固まらない）', async () => {
    const lastId = await seed('visit')

    const received = await readCycle(`/dashboard/stream?after=${lastId}`)

    expect(received).toContain(`id: ${lastId}\nevent: cursor`)
  })

  it('新着イベントが無いポーリング周期では summary を配信しない', async () => {
    const lastId = await seed('visit')

    const response = await call(`/dashboard/stream?after=${lastId}`, AUTH_HEADERS)
    const reader = response.body!.getReader()
    const decoder = new TextDecoder()
    let received = ''
    while (!received.includes('event: cursor')) {
      const { value, done } = await reader.read()
      if (done) break
      received += decoder.decode(value, { stream: true })
    }
    await reader.cancel()

    expect(received).not.toContain('event: summary')
  })
})

/** `<h3>見出し` の表 1 枚ぶんを切り出す（内訳の表は同じ `<h2>` 節に並ぶ）。 */
const countTable = (html: string, heading: string): string => {
  const start = html.indexOf(`<h3>${heading}</h3>`)
  expect(start, heading).toBeGreaterThanOrEqual(0)
  const rest = html.slice(start)
  const end = rest.indexOf('</section>')
  return end === -1 ? rest : rest.slice(0, end)
}

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
    // 系列の本数は面ごとに違う。概要面は人のアクセス中心（OVERVIEW_METRICS +
    // 新規ダウンロードとアップデートの 2 本）、時間帯分布は KIND_LABELS の全指標。どちらも
    // literal で固定しない（固定すると指標追加のたびにここが落ち、「1 枚に
    // まとめてあるか」という本題と関係のない修正が要る）。ユニークは母集団が
    // 違うので別節へ分けてある。色は --series-1..5 の 5 スロットが上限。
    for (const [chart, series] of [
      [daily, OVERVIEW_METRICS.size + 2],
      [hourly, KIND_LABELS.length],
    ] as const) {
      expect(series).toBeLessThanOrEqual(5)
      expect(chart).toContain(`chart-bar-${series}`)
      expect(chart).not.toContain(`chart-bar-${series + 1}`)
    }
  })

  it('チャートを持つ節には凡例があり、表は置かない', async () => {
    await seed('visit')
    await seed('download', { version: 'v1.10.0', country: 'JP', os: 'macOS 15.0' })

    const daily = section(await (await call(PAGE.overview, AUTH_HEADERS)).text(), '日毎の推移')
    const hourly = section(await (await call(PAGE.users, AUTH_HEADERS)).text(), '時間帯分布')

    expect(daily).toContain('<ul class="legend">')
    expect(daily).toContain('<span class="swatch swatch-2"')
    expect(hourly).toContain('<ul class="legend">')
    expect(hourly).toContain('<span class="swatch swatch-4"')
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

  /** 「配布ホストと旧経路」セクション（表の 2 つ）だけを切り出す。 */
  function hostSection(body: string): string {
    return body.slice(
      body.indexOf('<h2>配布ホストと旧経路'),
      body.indexOf('<h2>停止判断の対象経路の推移'),
    )
  }

  /** 日次推移のセクションだけを切り出す。 */
  function trendSection(body: string): string {
    return body.slice(body.indexOf('<h2>停止判断の対象経路の推移'))
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

  it('経路別に最後に発生した時刻を、人間とロボットで分けて出す', async () => {
    // 累計は一度発生すると減らないので、止めてよいかは最終発生時刻でしか読めない。
    // かつ停止条件は人間で決まるのに、混ぜた最終発生はロボットが作り続ける。
    const at = Date.parse('2026-08-08T03:00:00Z')
    await env.DB.prepare('INSERT INTO events (timestamp, kind, host, fallback) VALUES (?, ?, ?, ?)')
      .bind(at, 'github_fallback', 'befold.degino.com', 'dmg')
      .run()

    const hostHtml = hostSection(await (await call(PAGE.delivery, AUTH_HEADERS)).text())

    expect(hostHtml).toContain('人間 最終 (JST)')
    expect(hostHtml).toContain('ロボット 最終 (JST)')
    expect(hostHtml).toContain(formatJst(at))
  })

  it('一度も発生していない経路の最終発生は 0 ではなく「—」で出す', async () => {
    // formatJst(0) は 1970 年を描く。0 件の既知ホストは必ず行として残る設計なので、
    // ここを 0 にすると「大昔に来た」に化ける。
    await insertRow('visit', 'befold.degino.com')

    const hostHtml = hostSection(await (await call(PAGE.delivery, AUTH_HEADERS)).text())
    const legacyCell = hostHtml.indexOf('<td>befold.tommy109.workers.dev</td>')

    expect(hostHtml.slice(legacyCell, legacyCell + 200)).toContain('—')
    expect(hostHtml).not.toContain('1970-')
  })

  it('直近の窓の件数を累計と並べて出す', async () => {
    await insertRow('update_check', 'befold.tommy109.workers.dev')

    const hostHtml = hostSection(await (await call(PAGE.delivery, AUTH_HEADERS)).text())

    expect(hostHtml).toContain('人間 30日')
    expect(hostHtml).toContain('人間 7日')
  })

  it('停止判断の対象経路だけを日次推移に描く', async () => {
    await insertRow('update_check', 'befold.tommy109.workers.dev')
    await insertRow('github_fallback', 'befold.degino.com', 'dmg')

    const trendHtml = trendSection(await (await call(PAGE.delivery, AUTH_HEADERS)).text())

    expect(trendHtml).toContain('旧ホスト（befold.tommy109.workers.dev）へのアクセス')
    expect(trendHtml).toContain('GitHub フォールバック')
    // 正規ホストは停止判断の対象ではないので系列に出さない。
    expect(trendHtml).not.toContain('<h3>befold.degino.com')
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

describe('ダウンロード系指標の見せ方', () => {
  /** カード 1 枚のラベル。id から引く（並び順ではなく対応で見る）。 */
  function labelOf(html: string, id: string): string | null {
    const marker = `id="${id}">`
    const start = html.indexOf(marker)
    if (start === -1) return null
    const rest = html.slice(start)
    const match = /<span class="label">([^<]+)<\/span>/u.exec(rest)
    return match?.[1] ?? null
  }

  it.each([
    ['累計（全期間）', 'count'],
    ['本日（JST 0 時から）', 'today'],
  ])('%s のカードに出るダウンロード指標は新規とアップデートのみ', async (heading, prefix) => {
    // 報告された状態そのもの: LP 1 件に対し、旧バージョンが 6 件。概要面は
    // 合計だけを出すので、内訳が本体を上回って見える形にならない（TASK-551）。
    await seed('download', { source: 'lp' })
    for (let i = 0; i < 6; i += 1) await seed('download', { source: 'archive' })
    await seed('download', { source: 'sparkle' })
    await seed('download', { source: 'sparkle' })

    const block = section(await (await call(PAGE.overview, AUTH_HEADERS)).text(), heading)

    expect(block).toContain(`<span class="value" id="${prefix}-download-new">1</span>`)
    expect(labelOf(block, `${prefix}-download-new`)).toBe('新規ダウンロード数')
    expect(block).toContain(`<span class="value" id="${prefix}-download-update">2</span>`)
    expect(labelOf(block, `${prefix}-download-update`)).toBe('アップデート数')
    for (const metric of ['download', 'update_download', 'archive_download']) {
      expect(labelOf(block, `${prefix}-${metric}`)).toBe(null)
    }
  })

  it('概要面から外した指標は流入面の内訳で読める（黙って消えていない）', async () => {
    // 「移動先が空」を検出するための担保。移す先を用意せずカードだけ消すと、
    // ここが落ちる。
    await seed('download', { source: 'archive' })
    await seed('update_check')

    const traffic = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    expect(traffic).toContain('<span class="value" id="traffic-archive_download">1</span>')
    expect(labelOf(traffic, 'traffic-archive_download')).toBe('ダウンロード（旧バージョン）')
    expect(traffic).toContain('<span class="value" id="traffic-update_check">1</span>')
    expect(labelOf(traffic, 'traffic-update_check')).toBe('アップデート確認')
  })

  it('流入面の内訳カードは合計の直前に内訳 3 つが連続して並ぶ', async () => {
    const traffic = await (await call(PAGE.traffic, AUTH_HEADERS)).text()

    const order = [...traffic.matchAll(/id="traffic-([a-z_-]+)"/gu)].map((match) => match[1])
    const first = order.indexOf('download')

    expect(first).toBeGreaterThanOrEqual(0)
    // 内訳 3 つが連続する。間に別の指標が割り込むと、どこまでが
    // ダウンロードの内訳なのかが読めなくなる。
    expect(order.slice(first, first + 3)).toEqual([
      'download',
      'update_download',
      'archive_download',
    ])
  })

  it('新規ダウンロードは LP のみで、旧バージョン経由（ボット直接取得が大半）を含めない', () => {
    // archive を新規へ混ぜると、ページビューより新規ダウンロードが多い並びになる
    // （実測: 10/5 は PV 38 に対し LP 5 + archive 48）。
    const downloads = KIND_LABELS.filter((entry) => DOWNLOAD_METRICS.has(entry.kind))

    expect(downloads.map((entry) => entry.kind)).toEqual([
      'download',
      'update_download',
      'archive_download',
    ])
    const counts = { ...EMPTY_COUNTS, download: 1, archive_download: 6, update_download: 2 }
    expect(newDownloads(counts)).toBe(1)
    expect(updateDownloads(counts)).toBe(2)
  })
})
