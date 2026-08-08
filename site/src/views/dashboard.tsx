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
h2 { font-size: 1.1rem; margin: 0 0 0.75rem; padding-bottom: 0.25rem;
  border-bottom: 1px solid rgba(128,128,128,0.3); }
h3 { font-size: 0.95rem; margin: 0 0 0.5rem; font-weight: 600; }
.block { margin-bottom: 2.5rem; }
.block .totals { margin-bottom: 0; }
.empty { opacity: 0.6; font-size: 0.9rem; }
.unit { font-size: 0.75rem; opacity: 0.6; }
.notice { font-size: 0.8rem; opacity: 0.75; margin: 0 0 1.5rem;
  border-left: 3px solid rgba(128,128,128,0.4); padding: 0.25rem 0 0.25rem 0.75rem; }
`

const CountTable: FC<{ title: string; rows: Count[] }> = ({ title, rows }) => (
  <section>
    <h3>{title}</h3>
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

/** 期間内に 1 件も無いときだけ「データなし」を出す表。ゼロ埋め済みの系列用。 */
const SeriesTable: FC<{ title: string; rows: Count[]; unit: string }> = ({ title, rows, unit }) => {
  const total = rows.reduce((sum, row) => sum + row.count, 0)

  return (
    <section>
      <h3>{title}</h3>
      {total === 0 ? (
        <p class="empty">期間内のデータなし</p>
      ) : (
        <table>
          <tbody>
            {rows.map((row) => (
              <tr>
                <td>{row.label}</td>
                <td>
                  {row.count}
                  <span class="unit"> {unit}</span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  )
}

const Cards: FC<{ cards: { value: number; label: string; id?: string }[] }> = ({ cards }) => (
  <div class="totals">
    {cards.map((card) => (
      <div class="card">
        {card.id === undefined ? (
          <span class="value">{card.value}</span>
        ) : (
          <span class="value" id={card.id}>
            {card.value}
          </span>
        )}
        <span class="label">{card.label}</span>
      </div>
    ))}
  </div>
)

/**
 * 集計セクション（累計 / 本日 / 推移 / 時間帯 / 内訳 / 最新イベント）。
 *
 * 初期レンダリングと SSE 配信の両方がこれを使う。JST 基準の明示と
 * 不連続の注記は毎周期送り直す必要がないため、この外（ヘッダー）に置く。
 */
export const SummarySections: FC<{ summary: Summary }> = ({ summary }) => {
  const windowLabel = `直近 ${summary.windowDays} 日`

  return (
    <>
      <section class="block">
        <h2>累計（全期間）</h2>
        <Cards
          cards={[
            ...summary.perKind.map((entry) => ({
              value: entry.total,
              label: entry.label,
              id: `count-${entry.kind}`,
            })),
            {
              value: summary.cumulative.visitorDays,
              label: '延べ訪問者（訪問者 × 日）',
            },
          ]}
        />
      </section>

      <section class="block">
        <h2>本日（JST 0 時から）</h2>
        <Cards
          cards={[
            ...summary.perKind.map((entry) => ({
              value: summary.today.counts[entry.kind],
              label: entry.label,
              id: `today-${entry.kind}`,
            })),
            { value: summary.today.uniqueVisitors, label: 'ユニーク訪問者' },
          ]}
        />
      </section>

      <section class="block">
        <h2>日毎の推移（{windowLabel}）</h2>
        <div class="grid">
          {summary.perKind.map((entry) => (
            <SeriesTable
              title={entry.label}
              unit="件"
              rows={summary.daily.map((point) => ({
                label: point.day,
                count: point.counts[entry.kind],
              }))}
            />
          ))}
          <SeriesTable
            title="ユニーク訪問者"
            unit="人"
            rows={summary.daily.map((point) => ({
              label: point.day,
              count: point.uniqueVisitors,
            }))}
          />
        </div>
      </section>

      <section class="block">
        <h2>時間帯分布（{windowLabel}・JST）</h2>
        <div class="grid">
          {summary.perKind.map((entry) => (
            <SeriesTable
              title={entry.label}
              unit="件"
              rows={summary.hourly.map((point) => ({
                label: `${String(point.hour).padStart(2, '0')} 時台`,
                count: point.counts[entry.kind],
              }))}
            />
          ))}
        </div>
      </section>

      <section class="block">
        <h2>内訳（全期間の累計）</h2>
        <div class="grid">
          <CountTable title="バージョン別ダウンロード" rows={summary.byVersion} />
          <CountTable title="国別" rows={summary.byCountry} />
          <CountTable title="参照元別" rows={summary.byReferrer} />
          <CountTable title="クライアント種別" rows={summary.byUA} />
          {summary.perKind.map((entry) => [
            <CountTable title={`${entry.label}: OS 別`} rows={entry.byOS} />,
            <CountTable title={`${entry.label}: 接続元組織別`} rows={entry.byAsOrg} />,
          ])}
        </div>
      </section>

      <section class="block">
        <h2>最新イベント（直近 20 件）</h2>
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
}

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
        SSE: <span id="stream-status">connecting…</span> · 日付・時刻はすべて JST (UTC+9) 基準
        · 期間は固定（累計 / 本日 / 直近 {summary.windowDays} 日）
      </p>
      {/* SSE は #summary を丸ごと差し替えるため、毎周期送り直す必要のない
          静的な注記はその外に置く。 */}
      <p class="notice">
        訪問者の識別子は sha256(IP + UA + 日付) で、日付の基準を UTC から JST
        へ変更した。切り替え日より前のデータは UTC 日付で計算されているため、
        その期間のユニーク訪問者は同一人物が二重に数えられ、最大 2 倍に膨らむ。
        過去データの再計算は行っていない。
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
