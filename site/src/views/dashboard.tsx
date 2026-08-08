import type { FC } from 'hono/jsx'
import { html, raw } from 'hono/html'
import type { Count, Summary } from '../analytics'
import { formatJst } from '../lib/jst'

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
:root { color-scheme: light dark; }
body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
  margin: 0 auto; max-width: 60rem; padding: 2rem 1rem; line-height: 1.6; }
h1 { font-size: 1.5rem; margin-bottom: 0.25rem; }
.status { font-size: 0.85rem; opacity: 0.7; margin-bottom: 1.5rem; }
.totals { display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
  margin-bottom: 2rem; }
.card { border: 1px solid rgba(128,128,128,0.3); border-radius: 0.5rem; padding: 1rem; }
.card .value { font-size: 2rem; font-weight: 600; display: block; }
.card .label { font-size: 0.8rem; opacity: 0.7; }
.grid { display: grid; gap: 2rem; grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr)); }
table { border-collapse: collapse; width: 100%; font-size: 0.9rem; }
th, td { text-align: left; padding: 0.3rem 0.5rem; border-bottom: 1px solid rgba(128,128,128,0.2); }
h2 { font-size: 1rem; margin: 0 0 0.5rem; }
.empty { opacity: 0.6; font-size: 0.9rem; }
`

const CountTable: FC<{ title: string; rows: Count[] }> = ({ title, rows }) => (
  <section>
    <h2>{title}</h2>
    {rows.length === 0 ? (
      <p class="empty">データなし</p>
    ) : (
      <table>
        <tbody>
          {rows.map((row) => (
            <tr>
              <td>{row.label}</td>
              <td>{row.count}</td>
            </tr>
          ))}
        </tbody>
      </table>
    )}
  </section>
)

/**
 * 集計セクション（合計カード・各集計表・最新イベント）。
 *
 * 初期レンダリングと SSE 配信の両方がこれを使う。
 */
export const SummarySections: FC<{ summary: Summary }> = ({ summary }) => (
  <>
    <div class="totals">
      {summary.perKind.map((entry) => (
        <div class="card">
          <span class="value" id={`count-${entry.kind}`}>
            {entry.total}
          </span>
          <span class="label">{entry.label}</span>
        </div>
      ))}
      <div class="card">
        <span class="value">{summary.cumulative.visitorDays}</span>
        <span class="label">延べ訪問者（累計・訪問者 × 日）</span>
      </div>
      <div class="card">
        <span class="value">{summary.today.uniqueVisitors}</span>
        <span class="label">本日のユニーク訪問者（JST）</span>
      </div>
    </div>

    <div class="grid">
      <CountTable
        title={`日別ダウンロード（${summary.windowDays} 日・JST）`}
        rows={summary.daily.map((point) => ({
          label: point.day,
          count: point.counts.download,
        }))}
      />
      <CountTable title="クライアント種別" rows={summary.byUA} />
      <CountTable title="バージョン別ダウンロード" rows={summary.byVersion} />
      <CountTable title="国別" rows={summary.byCountry} />
      <CountTable title="参照元別" rows={summary.byReferrer} />
      {summary.perKind.map((entry) => [
        <CountTable title={`${entry.label}: OS 別`} rows={entry.byOS} />,
        <CountTable title={`${entry.label}: 接続元組織別`} rows={entry.byAsOrg} />,
      ])}
    </div>

    <section>
      <h2>最新イベント</h2>
      <table>
        <thead>
          <tr>
            <th>時刻 (JST)</th>
            <th>種別</th>
            <th>バージョン</th>
            <th>国</th>
            <th>OS</th>
          </tr>
        </thead>
        <tbody id="recent-body">
          {summary.recent.map((event) => (
            <tr>
              <td>{formatJst(event.ts)}</td>
              <td>{event.kind}</td>
              <td>{event.version ?? ''}</td>
              <td>{event.country ?? ''}</td>
              <td>{event.os ?? ''}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  </>
)

/** 集計セクションを HTML 文字列にする（SSE 配信用）。 */
export const renderSummarySections = (summary: Summary): string =>
  (<SummarySections summary={summary} />).toString()

/** 所有者だけが見る分析ダッシュボード（Cloudflare Access の背後）。 */
export const Dashboard: FC<{ summary: Summary; lastId: number }> = ({ summary, lastId }) => (
  <html lang="ja">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>befold analytics</title>
      {html`<style>
        ${raw(STYLE)}
      </style>`}
    </head>
    <body data-last-id={String(lastId)}>
      <h1>befold analytics</h1>
      <p class="status">
        SSE: <span id="stream-status">connecting…</span>
      </p>

      <div id="summary">
        <SummarySections summary={summary} />
      </div>

      {html`<script>
        ${raw(STREAM_SCRIPT)}
      </script>`}
    </body>
  </html>
)
