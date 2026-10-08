/**
 * ダッシュボード全体の外枠。HTML の骨組み・CSS・SSE 受信スクリプト・面の導線を置く。
 * 面ごとの中身（セクション）と汎用の描画部品は置かない。
 */
import { html, raw } from 'hono/html'
import type { FC } from 'hono/jsx'

import type { DashboardPage, DashboardPageKey } from '../../analytics'
import { DASHBOARD_PAGES } from '../../analytics'

/**
 * SSE で配信される集計 HTML をそのまま差し替える。
 *
 * 集計は summarize() だけが持ち、クライアントは描画済み HTML を置くだけにする
 * （JST 日付バケットや上位 N 件の並べ替えを JS に二重実装しないため）。
 */
const STREAM_SCRIPT = `
(function () {
  var source = new EventSource('/dashboard/stream?after=' + document.body.dataset.lastId);
  var summary = document.getElementById('summary');
  var status = document.getElementById('stream-status');

  source.addEventListener('open', function () { status.textContent = 'live'; });
  source.addEventListener('error', function () { status.textContent = 'reconnecting…'; });

  source.addEventListener('summary', function (message) {
    summary.innerHTML = JSON.parse(message.data);
  });
})();
`

const STYLE = `
:root { color-scheme: light dark;
  --series-1: #2a78d6; --series-2: #eb6834; --series-3: #1baf7a;
  --series-4: #eda100; --series-5: #e87ba4; }
@media (prefers-color-scheme: dark) {
  :root { --series-1: #3987e5; --series-2: #d95926; --series-3: #199e70;
    --series-4: #c98500; --series-5: #d55181; }
}
body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
  margin: 0 auto; max-width: 76rem; padding: 2rem 1rem; line-height: 1.6; }
h1 { font-size: 1.5rem; margin-bottom: 0.25rem; }
.status { font-size: 0.85rem; opacity: 0.7; margin-bottom: 1.5rem; }
.nav { display: flex; flex-wrap: wrap; gap: 1rem; margin: 0.5rem 0 1rem; font-size: 0.95rem; }
.nav a { color: inherit; }
.nav-current { font-weight: 600; text-decoration: underline; text-underline-offset: 0.3rem; }
.totals { display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
  margin-bottom: 2rem; }
.card { border: 1px solid rgba(128,128,128,0.3); border-radius: 0.5rem; padding: 1rem; }
.card .value { font-size: 2rem; font-weight: 600; display: block; }
.card .label { font-size: 0.8rem; opacity: 0.7; }
.grid { display: grid; gap: 2rem; grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr)); }
table { border-collapse: collapse; width: 100%; font-size: 0.9rem; }
th, td { text-align: left; padding: 0.3rem 0.5rem; border-bottom: 1px solid rgba(128,128,128,0.2); }
h2 { font-size: 1.1rem; margin: 0 0 0.75rem; padding-bottom: 0.25rem;
  border-bottom: 1px solid rgba(128,128,128,0.3); }
h3 { font-size: 0.95rem; margin: 0 0 0.5rem; font-weight: 600; }
.block { margin-bottom: 2.5rem; }
.block .totals { margin-bottom: 0; }
.empty { opacity: 0.6; font-size: 0.9rem; }
.unit { font-size: 0.75rem; opacity: 0.6; }
.note { font-size: 0.8rem; opacity: 0.7; margin: 0 0 1rem; }
.pager { display: flex; justify-content: space-between; gap: 1rem; margin-top: 1rem;
  font-size: 0.9rem; }
.pager a { color: inherit; }
.pager-disabled { opacity: 0.35; }
.chart { width: 100%; height: auto; margin-bottom: 0.5rem; overflow: visible; display: block; }
.chart-bar { fill: currentColor; }
.chart-bar-1 { fill: var(--series-1); }
.chart-bar-2 { fill: var(--series-2); }
.chart-bar-3 { fill: var(--series-3); }
.chart-bar-4 { fill: var(--series-4); }
.chart-bar-5 { fill: var(--series-5); }
.chart-axis { stroke: currentColor; opacity: 0.35; }
.chart-peak { stroke: currentColor; opacity: 0.2; stroke-dasharray: 4 4; }
.chart-label { fill: currentColor; opacity: 0.7; font-size: 13px; }
.chart-peak-label { fill: currentColor; opacity: 0.55; font-size: 12px; }
.legend { display: flex; flex-wrap: wrap; gap: 0.25rem 1.25rem; list-style: none;
  margin: 0 0 0.5rem; padding: 0; font-size: 0.85rem; }
.legend li { display: flex; align-items: center; gap: 0.4rem; }
.legend .swatch { width: 0.85rem; height: 0.85rem; border-radius: 0.15rem; flex: none; }
.legend .order { opacity: 0.55; font-variant-numeric: tabular-nums; }
.swatch-1 { background: var(--series-1); }
.swatch-2 { background: var(--series-2); }
.swatch-3 { background: var(--series-3); }
.swatch-4 { background: var(--series-4); }
.swatch-5 { background: var(--series-5); }
`

/**
 * 面をまたぐ導線。`DASHBOARD_PAGES` から引くので、面を足しても書き写す場所が増えない。
 *
 * `base` はダッシュボードのルート（`/dashboard`）。面の `path` はその配下の相対パス。
 */
const Nav: FC<{ current: DashboardPageKey }> = ({ current }) => (
  <nav class="nav">
    {DASHBOARD_PAGES.map((page) => {
      const href = page.path === '/' ? '/dashboard' : `/dashboard${page.path}`
      return page.key === current ? (
        <span class="nav-current" aria-current="page">
          {page.title}
        </span>
      ) : (
        <a href={href}>{page.title}</a>
      )
    })}
  </nav>
)

/**
 * 面に共通の外枠（Cloudflare Access の背後）。
 *
 * `lastId` を渡した面だけが SSE に接続する。渡さない面ではストリーム用の
 * スクリプトも状態表示も出さない。出すと「更新され続けている」と読めてしまい、
 * 実際には静止しているスナップショットとの区別が付かなくなる。
 */
export const DashboardPageShell: FC<{
  page: DashboardPage
  windowDays?: number
  lastId?: number
  children?: unknown
}> = ({ page, windowDays, lastId, children }) => (
  <html lang="ja">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>befold analytics · {page.title}</title>
      {html`<style>
        ${raw(STYLE)}
      </style>`}
    </head>
    <body {...(lastId === undefined ? {} : { 'data-last-id': String(lastId) })}>
      <h1>befold analytics</h1>
      <Nav current={page.key} />
      <p class="status">
        {lastId === undefined ? (
          <>この面は開いた時点のスナップショット（自動更新しない）</>
        ) : (
          <>
            SSE: <span id="stream-status">connecting…</span>
          </>
        )}{' '}
        · 日付・時刻はすべて JST (UTC+9) 基準
        {windowDays === undefined ? '' : ` · 期間は直近 ${windowDays} 日`}
      </p>

      <div id="summary">{children}</div>

      {lastId === undefined
        ? ''
        : html`<script>
            ${raw(STREAM_SCRIPT)}
          </script>`}
    </body>
  </html>
)
