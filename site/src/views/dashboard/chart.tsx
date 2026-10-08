/**
 * インライン SVG のグループ化バーグラフと凡例。面に依らない描画部品で、
 * 表・カードは parts.tsx、ページ固有の系列の組み立ては各ページのファイルに置く。
 */
import type { FC } from 'hono/jsx'

/** 棒グラフの内部座標。viewBox で拡大縮小するため単位は px ではない。 */
const CHART = { width: 960, height: 220, labelGap: 22, topGap: 18, groupGap: 10, barGap: 1 }

/** 1 グループ内に 1 本ずつ並ぶ系列。values は labels と同じ長さ・同じ並び。 */
export type Series = { label: string; unit: string; values: number[] }

/**
 * インライン SVG のグループ化バーグラフ。
 *
 * クライアント JS で描かないのは、SSE が #summary を innerHTML で丸ごと
 * 置き換えるため（views/dashboard/shell.tsx の STREAM_SCRIPT）。サーバ側で
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
export const SeriesChart: FC<{ title: string; labels: string[]; series: Series[] }> = ({
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
