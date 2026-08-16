import type { FC } from 'hono/jsx'
import { html, raw } from 'hono/html'
import type { Count, Split, Summary } from '../analytics'
import { UNIQUE_SOURCE_LABELS, UNRECORDED_LABEL } from '../analytics'
import { LEGACY_HOST } from '../lib/hosts'
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
 * ボット分類（TASK-386）を適用した日。過去データは遡って分類できないため、
 * 内訳がこの日以降だけのものであることを画面に明示する。
 */
const BOT_CLASSIFICATION_START = '2026-08-09'

/**
 * LP を言語ごとの URL に分けた日（TASK-496）。これより前の訪問は日英を同じ HTML で
 * 出していたため、表示言語が確定しない。過去データは遡って埋められない。
 */
const LANGUAGE_URL_START = '2026-08-16'

/**
 * リクエスト先ホストの記録を始めた日（TASK-488.3）。これより前の行はどのホストで
 * 応答したかを復元できない。
 */
const HOST_COLUMN_START = '2026-08-16'

/**
 * 接続元組織（as_org）の記録を始めた日（migrations/20260730022424_add_as_org.sql）。
 * データセンター判定はこの列だけを見るため、この日以降は遡って効く。
 */
const AS_ORG_COLUMN_START = '2026-07-30'

/**
 * `Split[]` を人間側または自動アクセス側の `Count[]` にする。
 *
 * 0 件の区分は落とす。ページ別・言語別は取りうる値がすべて出そろうため、
 * 落とさないと「自動アクセス: 表示言語別」に 0 の行が並んで内訳が読めなくなる。
 */
function splitRows(splits: Split[], nonHuman: boolean): Count[] {
  return splits
    .map((split) => ({ label: split.label, count: nonHuman ? split.nonHuman : split.human }))
    .filter((row) => row.count > 0)
}

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

/**
 * 人間と自動アクセスを 2 列で並べる表。**0 件の行も落とさない。**
 *
 * `CountTable` + `splitRows` は 0 を落とす（取りうる値がすべて出そろう軸で
 * 0 の行が並ぶのを避けるため）。ホストと GitHub フォールバックはその逆で、
 * 「0 であること」の確認が目的なので、行が消えると「まだ 0」と「そもそも
 * 計測していない」が区別できなくなる。
 */
const SplitTable: FC<{ title: string; rows: Split[] }> = ({ title, rows }) => (
  <section>
    <h3>{title}</h3>
    {rows.length === 0 ? (
      <p class="empty">データなし</p>
    ) : (
      <table>
        <thead>
          <tr>
            <th></th>
            <th>人間</th>
            <th>自動アクセス</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr>
              <td>{row.label}</td>
              <td>{row.human}</td>
              <td>{row.nonHuman}</td>
            </tr>
          ))}
        </tbody>
      </table>
    )}
  </section>
)

/** 棒グラフの内部座標。viewBox で拡大縮小するため単位は px ではない。 */
const CHART = { width: 960, height: 220, labelGap: 22, topGap: 18, groupGap: 10, barGap: 1 }

/** 1 グループ内に 1 本ずつ並ぶ系列。values は labels と同じ長さ・同じ並び。 */
type Series = { label: string; unit: string; values: number[] }

/**
 * インライン SVG のグループ化バーグラフ。
 *
 * クライアント JS で描かないのは、SSE が #summary を innerHTML で丸ごと
 * 置き換えるため（views/dashboard.tsx の STREAM_SCRIPT）。サーバ側で
 * SVG を描いておけば、置き換わる HTML そのものがグラフになり、再描画の
 * フックを別に用意する必要がなくなる（書き忘れれば静かに消える類の穴を作らない）。
 *
 * 色（--series-1..5）は系列の宣言順にスロットを固定で割り当て、順番で回さない。
 * 色は補助の手掛かりでしかなく、系列の同定は「凡例の並び順 = 1 グループ内の
 * バーの並び順」と各バーの <title>（系列名と値）で色に依らず取れるようにしてある。
 * 5 スロットを超える系列を足すときは色を生成せず、指標側をまとめること。
 */
const GroupedBarChart: FC<{ labels: string[]; series: Series[]; title: string }> = ({
  labels,
  series,
  title,
}) => {
  const max = series.reduce(
    (peak, entry) => entry.values.reduce((inner, value) => Math.max(inner, value), peak),
    0,
  )
  // 全値 0 のときに高さを value / max で出すと 0 除算になる。棒を描かず軸だけ残す。
  const plotHeight = CHART.height - CHART.labelGap
  // 最大値の目盛りを最も高い棒に重ねないよう、上端に topGap ぶんの余白を残す。
  const barHeight = plotHeight - CHART.topGap
  const slot = labels.length === 0 ? 0 : CHART.width / labels.length
  const groupWidth = Math.max(slot - CHART.groupGap, 1)
  const lane = groupWidth / Math.max(series.length, 1)
  const barWidth = Math.max(lane - CHART.barGap, 0.5)

  return (
    <svg
      class="chart"
      viewBox={`0 0 ${CHART.width} ${CHART.height}`}
      role="img"
      aria-label={`${title}（最大 ${max}）`}
    >
      <line
        x1="0"
        y1={plotHeight}
        x2={CHART.width}
        y2={plotHeight}
        class="chart-axis"
        vector-effect="non-scaling-stroke"
      />
      {max === 0 ? null : (
        <>
          <line
            x1="0"
            y1={CHART.topGap}
            x2={CHART.width}
            y2={CHART.topGap}
            class="chart-peak"
            vector-effect="non-scaling-stroke"
          />
          <text class="chart-peak-label" x="2" y={CHART.topGap - 4}>
            {`最大 ${max}`}
          </text>
        </>
      )}
      {max === 0
        ? null
        : series.map((entry, seriesIndex) =>
            entry.values.map((value, index) => {
              const height = (value / max) * barHeight
              const x = index * slot + CHART.groupGap / 2 + seriesIndex * lane + CHART.barGap / 2
              return (
                <rect
                  class={`chart-bar chart-bar-${seriesIndex + 1}`}
                  x={x}
                  y={plotHeight - height}
                  width={barWidth}
                  height={height}
                >
                  <title>{`${labels[index]}｜${entry.label}: ${value} ${entry.unit}`}</title>
                </rect>
              )
            }),
          )}
      {labels.map((label, index) => (
        <text
          class="chart-label"
          x={index * slot + slot / 2}
          y={CHART.height - 4}
          text-anchor="middle"
        >
          {label}
        </text>
      ))}
    </svg>
  )
}

/** 系列名と色の対応。並び順は 1 グループ内のバーの並び順と一致させる。 */
const Legend: FC<{ series: Series[] }> = ({ series }) => (
  <ul class="legend">
    {series.map((entry, index) => (
      <li>
        <span class={`swatch swatch-${index + 1}`} aria-hidden="true" />
        <span class="order">{index + 1}.</span>
        <span>
          {entry.label}
          <span class="unit"> {entry.unit}</span>
        </span>
      </li>
    ))}
  </ul>
)

/**
 * ゼロ埋め済みの系列を、凡例 + グループ化バーグラフ 1 枚で見せる。
 * 期間内に 1 件も無いときだけ「データなし」にする。
 */
const SeriesChart: FC<{ title: string; labels: string[]; series: Series[] }> = ({
  title,
  labels,
  series,
}) => {
  const total = series.reduce(
    (sum, entry) => entry.values.reduce((inner, value) => inner + value, sum),
    0,
  )

  if (total === 0) return <p class="empty">期間内のデータなし</p>

  return (
    <>
      <Legend series={series} />
      <GroupedBarChart title={title} labels={labels} series={series} />
    </>
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
 * 初期レンダリングと SSE 配信の両方がこれを使う。JST 基準の明示など
 * 毎周期送り直す必要のない静的テキストは、この外（ヘッダー）に置く。
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
              label: '延べアクセス元（アクセス元 × 日）',
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
            { value: summary.today.uniqueVisitors, label: 'ユニークアクセス元（全種別）' },
          ]}
        />
      </section>

      <section class="block">
        <h2>日毎の推移（{windowLabel}）</h2>
        <SeriesChart
          title={`日毎の推移（${windowLabel}）`}
          labels={summary.daily.map((point) => point.day.slice(5))}
          series={summary.perKind.map((entry) => ({
            label: entry.label,
            unit: '件',
            values: summary.daily.map((point) => point.counts[entry.kind]),
          }))}
        />
      </section>

      <section class="block">
        <h2>日別のユニークアクセス元（{windowLabel}）</h2>
        <p class="note">
          利用者数そのものではなく近似。数えているのは「その日に記録されたアクセス元の
          異なり数」で、アクセス元は接続元 IP と User-Agent の組をその日のうちだけ
          同一視できるハッシュ（visitor_token）。同じ人でも回線が変われば別々に数えるため
          モバイル回線・VPN では過大に振れ、逆に同じ回線・同じ端末構成の複数台は
          1 として数えるため NAT の内側では過小に振れる。ハッシュには日付が混ぜて
          あるので日をまたぐ同一人物は追えず、ここに出るのは常に「その日の」異なり数。
          通算のユニーク利用者数は出せない（出さない）。
        </p>
        <p class="note">
          サイト訪問（visit）とアプリ（アップデート確認）は母集団が違うので合算しない。
          アプリ側はアプリを起動して appcast を取りに来た端末で、stable と develop を
          分けている（develop には開発機が含まれるため、混ぜると利用者の規模を
          過大に見積もる）。サイト訪問はページを問わず数えるので、LP だけを数える
          「ページアクセス」の指標とは母数が違う。ロボットの除外は他の集計と同じ条件だが、
          curl のような自動アクセスはボット判定に当たらずここに残る。
        </p>
        <SeriesChart
          title={`日別のユニークアクセス元（${windowLabel}）`}
          labels={summary.daily.map((point) => point.day.slice(5))}
          series={UNIQUE_SOURCE_LABELS.map(({ key, label }) => ({
            label,
            unit: '件',
            values: summary.daily.map((point) => point.uniqueSources[key]),
          }))}
        />
      </section>

      <section class="block">
        <h2>時間帯分布（{windowLabel}・JST）</h2>
        <SeriesChart
          title={`時間帯分布（${windowLabel}・JST）`}
          labels={summary.hourly.map((point) => String(point.hour).padStart(2, '0'))}
          series={summary.perKind.map((entry) => ({
            label: entry.label,
            unit: '件',
            values: summary.hourly.map((point) => point.counts[entry.kind]),
          }))}
        />
      </section>

      <section class="block">
        <h2>内訳（全期間の累計）</h2>
        <div class="grid">
          <CountTable title="バージョン別ダウンロード" rows={summary.byVersion} />
          <CountTable title="国別" rows={summary.byCountry} />
          <CountTable title="参照元別" rows={summary.byReferrer} />
          {summary.perKind.map((entry) => [
            <CountTable title={`${entry.label}: OS 別`} rows={entry.byOS} />,
            <CountTable title={`${entry.label}: 接続元組織別`} rows={entry.byAsOrg} />,
          ])}
        </div>
      </section>

      <section class="block">
        <h2>ページ別の訪問（全期間の累計）</h2>
        <p class="note">
          ページアクセスの指標は LP（/）だけを数えているため、ここの合計とは一致しない。
          この表は visit のみが対象で、ダウンロードやアップデート確認は元々ページを持たない。
          ページ列を導入する前に記録された訪問はページが記録されていないが、当時計上して
          いたのは LP だけなので「/」に数えている。
        </p>
        <div class="grid">
          <CountTable title="人間: ページ別" rows={splitRows(summary.visits.byPage, false)} />
          <CountTable title="自動アクセス: ページ別" rows={splitRows(summary.visits.byPage, true)} />
        </div>
      </section>

      <section class="block">
        <h2>言語別の訪問（全期間の累計）</h2>
        <p class="note">
          「表示言語」は実際に配信したページの言語で、URL（/ と /en）が決める。
          「ブラウザ言語設定」は Accept-Language の第一希望を ja / en / other に丸めたもので、
          <strong>ブラウザの設定であって実際に読まれた言語ではない</strong>。 2
          つを並べているのは、英語を求めて来た人が英語ページへ辿り着けたかを見るため（
          ブラウザ言語設定が en で表示言語が ja なら、辿り着けていない）。
          言語ごとに URL を分ける前（{LANGUAGE_URL_START}）に記録された訪問は、日英を同じ
          HTML で出していたため表示言語が確定せず「{UNRECORDED_LABEL}」になる。遡って
          分類し直す材料は無い。
        </p>
        <div class="grid">
          <CountTable
            title="人間: 表示言語別"
            rows={splitRows(summary.visits.byDisplayLang, false)}
          />
          <CountTable
            title="自動アクセス: 表示言語別"
            rows={splitRows(summary.visits.byDisplayLang, true)}
          />
          <CountTable
            title="人間: ブラウザ言語設定別"
            rows={splitRows(summary.visits.byBrowserLang, false)}
          />
          <CountTable
            title="自動アクセス: ブラウザ言語設定別"
            rows={splitRows(summary.visits.byBrowserLang, true)}
          />
        </div>
      </section>

      <section class="block">
        <h2>配布ホストと旧経路（全期間の累計）</h2>
        <p class="note">
          旧ホスト（{LEGACY_HOST}）と GitHub へのフォールバックを止めてよいかの判断材料
          （ADR 0007）。ホスト別は kind を問わない全イベントが対象で、0 件のホストも
          行として残す（「まだ 0」と「計測していない」を区別するため）。
          ホスト列の導入前（{HOST_COLUMN_START}）に記録された行は、どのホストで応答したかを
          復元できないので「{UNRECORDED_LABEL}」に入る。
        </p>
        <p class="note">
          旧ホストの HTML ページ（LP・機能紹介）は正規ホストへ 301 で送るため、
          その到達は visit ではなく「旧ホストからの 301」として数える（301 を追った先で
          正規ホスト側の visit も記録されるので、visit にすると二重に数えられる）。
          機械向けの経路（appcast・/dl/・/download）は 301 せず素通しなので、旧ホストの
          ままホスト別に出る。旧ホストの静的アセットと /healthz は元々記録していない。
        </p>
        <p class="note">
          GitHub フォールバックは R2 に目的のオブジェクトが無かった回数。ここが 0 でない
          うちは GitHub 側の経路を止められない。appcast の行だけは
          caches.default（300 秒）に当たった周期を数えられないため、実際より小さく出る。
        </p>
        <div class="grid">
          <SplitTable title="リクエスト先ホスト別" rows={summary.hosts} />
          <SplitTable title="GitHub フォールバックの経路別" rows={summary.fallbacks} />
        </div>
      </section>

      <section class="block">
        <h2>人間の訪問と自動アクセス（全期間の累計）</h2>
        <Cards
          cards={[
            { value: summary.traffic.totals.human, label: '人間のクライアント' },
            { value: summary.traffic.totals.bot, label: 'ロボット（クローラ）' },
            { value: summary.traffic.totals.datacenter, label: 'データセンター由来' },
          ]}
        />
        <p class="note">
          このセクション以外の集計（累計・本日・推移・時間帯・内訳・最新イベント）は、
          ロボットとデータセンター由来の<strong>両方</strong>を除いた数。判定の軸はふたつある（ADR 0008）。
        </p>
        <p class="note">
          <strong>ロボット</strong>は User-Agent のトークンで判定する（ADR 0004）。完全な UA は
          保存していないため、分類を適用した {BOT_CLASSIFICATION_START} より前に記録された
          イベントは<strong>遡って分類できず</strong>、当時のクローラの巡回は「other」に含まれた
          まま人間側に数えられている。この日をまたぐ推移は連続していない。「bot:other」は既知
          トークンに当たらなかったボットで、ここが増え続けるなら分類漏れ。
        </p>
        <p class="note">
          <strong>データセンター由来</strong>は接続元組織（as_org）で判定する。UA はふつうの
          ブラウザだが接続元がクラウド・ホスティング・スキャン業者であるアクセスで、UA の軸では
          人間として数えられていたもの。as_org は {AS_ORG_COLUMN_START} 以降のすべての行に
          記録されているため、この判定は<strong>全期間に遡って効く</strong>（ロボット側と非対称）。
          {AS_ORG_COLUMN_START} より前の行は as_org が無いので人間側に残る。
        </p>
        <p class="note">
          判定できない接続元（as_org が NULL）は人間側に残す。プライバシー中継（iCloud Private
          Relay・WARP の出口）と VPN・Tor の出口は、人間の可能性があるのでデータセンターに
          含めない。誤って人間を落とすと、まだ使われている配布経路を止めてしまうため
          （ADR 0007 の停止判断にこの数字を使う）。
        </p>
        <div class="grid">
          <CountTable title="人間: クライアント種別" rows={summary.traffic.breakdowns.human} />
          <CountTable title="ロボット: 種類別" rows={summary.traffic.breakdowns.bot} />
          <CountTable
            title="データセンター: 接続元組織別"
            rows={summary.traffic.breakdowns.datacenter}
          />
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
              <th>ページ</th>
            </tr>
          </thead>
          <tbody id="recent-body">
            {summary.recent.map((event) => (
              <tr>
                <td>{formatJst(event.timestamp)}</td>
                <td>{event.kind}</td>
                <td>{event.version ?? ''}</td>
                <td>{event.country ?? ''}</td>
                <td>{event.os ?? ''}</td>
                {/* visit 以外の kind は元々ページを持たないので空欄にする。
                    ここで '/' を補うと、ダウンロードが LP の訪問に見える。 */}
                <td>{event.page ?? ''}</td>
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

      <div id="summary">
        <SummarySections summary={summary} />
      </div>

      {html`<script>
        ${raw(STREAM_SCRIPT)}
      </script>`}
    </body>
  </html>
)
