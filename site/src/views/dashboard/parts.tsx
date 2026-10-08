/**
 * 面に依らない表・カードの描画部品。ページ固有の文言や集計の選択は置かない。
 * グラフは chart.tsx、面ごとのセクションは各ページのファイルに置く。
 */
import type { FC } from 'hono/jsx'

import type { Count, KindCounts, MetricKey, RecentEvent, RouteSplit, Split } from '../../analytics'
import { DOWNLOAD_METRICS, KIND_LABELS, newDownloads, updateDownloads } from '../../analytics'
import { formatJst } from '../../lib/jst'

/**
 * `Split[]` を人間側または自動アクセス側の `Count[]` にする。
 *
 * 0 件の区分は落とす。ページ別・言語別は取りうる値がすべて出そろうため、
 * 落とさないと「自動アクセス: 表示言語別」に 0 の行が並んで内訳が読めなくなる。
 */
export function splitRows(splits: Split[], nonHuman: boolean): Count[] {
  return splits
    .map((split) => ({ label: split.label, count: nonHuman ? split.nonHuman : split.human }))
    .filter((row) => row.count > 0)
}

export const CountTable: FC<{ title: string; rows: Count[] }> = ({ title, rows }) => (
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
 * 停止判断の対象になる経路の表。旧ホスト別と GitHub フォールバック別で共有する。
 *
 * 人間と自動アクセスを 2 列並べるだけの汎用の表にしない。累計だけの表では
 * 「一度発生した経路」と「いま落ち続けている経路」が同じ見え方になり、経路を
 * 止めてよいかの判断（ADR 0007 / TASK-489）に使えない。
 *
 * **列は人間側に厚く、ロボット側に薄い。** 停止条件は人間の有無で決まるので、
 * 人間は累計・直近 2 つの窓・最終発生まで出し、ロボットは累計と最終発生だけに
 * する。ロボットの推移は日次グラフで読む（両方を対称に並べると 9 列になる）。
 */
export const RouteTable: FC<{
  title: string
  rows: RouteSplit[]
  windowDays: number
  recentDays: number
}> = ({ title, rows, windowDays, recentDays }) => (
  <section>
    <h3>{title}</h3>
    {rows.length === 0 ? (
      <p class="empty">データなし</p>
    ) : (
      <table>
        <thead>
          <tr>
            <th></th>
            <th>人間 累計</th>
            <th>人間 {windowDays}日</th>
            <th>人間 {recentDays}日</th>
            <th>人間 最終 (JST)</th>
            <th>ロボット 累計</th>
            <th>ロボット 最終 (JST)</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr>
              <td>{row.label}</td>
              <td>{row.human}</td>
              <td>{row.humanRecent}</td>
              <td>{row.humanLatest}</td>
              <td>{formatLastSeen(row.lastSeenHumanAt)}</td>
              <td>{row.nonHuman}</td>
              <td>{formatLastSeen(row.lastSeenBotAt)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    )}
  </section>
)

/**
 * 最終発生の表示。**発生が無い経路は 0 ではなく「—」にする。**
 *
 * `formatJst(0)` は 1970 年を描いてしまい、「一度も来ていない」が
 * 「大昔に来た」に化ける。0 件の既知ホストは行として残す設計なので、この行は必ず出る。
 */
function formatLastSeen(at: number | null): string {
  return at === null ? '—' : formatJst(at)
}

/**
 * 指標カードの並び。ダウンロード系は合計を先頭に置いた 1 かたまりにする。
 *
 * `metrics` は**必須引数**。面ごとに出す指標が違う（概要面は人のアクセス中心で
 * `OVERVIEW_METRICS` のみ）ため絞れる必要があるが、デフォルト引数を置くと次に
 * 指標を足した人が渡し忘れても通り、概要面へ静かに復活する（TASK-551）。
 * 新規ダウンロードとアップデートの 2 枚は面に依らず出す。概要面に残すダウンロード指標はこの 2 つのみ。
 *
 * 累計と本日で同じ関数を通す。片方だけ合計を足すと、同じ画面の上下で
 * 「ダウンロード」の意味が変わってしまう。新規は `newDownloads` が
 * `DOWNLOAD_METRICS` から導くので、経路を足しても漏れない。
 */
export function metricCards(counts: KindCounts, idPrefix: string, metrics: ReadonlySet<MetricKey>) {
  const first = KIND_LABELS.findIndex((entry) => DOWNLOAD_METRICS.has(entry.kind))
  const cards: { value: number; label: string; id?: string }[] = []

  for (const [index, entry] of KIND_LABELS.entries()) {
    if (index === first) {
      cards.push(
        {
          value: newDownloads(counts),
          label: '新規ダウンロード数',
          id: `${idPrefix}-download-new`,
        },
        {
          value: updateDownloads(counts),
          label: 'アップデート数',
          id: `${idPrefix}-download-update`,
        },
      )
    }
    if (!metrics.has(entry.kind)) continue
    cards.push({ value: counts[entry.kind], label: entry.label, id: `${idPrefix}-${entry.kind}` })
  }

  return cards
}

export const Cards: FC<{ cards: { value: number; label: string; id?: string }[] }> = ({
  cards,
}) => (
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
 * イベント一覧のテーブル。**概要面の直近 20 件とイベント面の 100 件で共有する。**
 *
 * 列を 2 箇所に書き写さない。どちらも同じ `RecentEvent` を並べるので、片方に
 * 列を足しただけでは気づけない（SELECT 句を `RECENT_COLUMNS` で共有しているのと
 * 同じ理由）。`bodyId` は概要面の tbody を指すためだけのもの。
 */
export const EventTable: FC<{ events: RecentEvent[]; bodyId?: string }> = ({ events, bodyId }) => (
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
    <tbody {...(bodyId === undefined ? {} : { id: bodyId })}>
      {events.map((event) => (
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
)
