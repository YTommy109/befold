/**
 * 概要面（OverviewSections）。全期間と当日の総数、日毎の推移、最新イベント。
 * 他の面のセクションは置かない。
 */
import type { FC } from 'hono/jsx'

import type { OverviewSummary } from '../../analytics'
import { KIND_LABELS, newDownloads, OVERVIEW_METRICS, updateDownloads } from '../../analytics'
import { SeriesChart } from './chart'
import { Cards, EventTable, metricCards } from './parts'

/**
 * 概要面のセクション。全期間と当日の総数、日毎の推移、最新イベント。
 *
 * 初期レンダリングと SSE 配信の両方がこれを使う。JST 基準の明示など
 * 毎周期送り直す必要のない静的テキストは、この外（ヘッダー）に置く。
 */
export const OverviewSections: FC<{ summary: OverviewSummary }> = ({ summary }) => {
  const windowLabel = `直近 ${summary.windowDays} 日`

  return (
    <>
      <section class="block">
        <h2>累計（全期間）</h2>
        <Cards
          cards={[
            ...metricCards(summary.cumulative.counts, 'count', OVERVIEW_METRICS),
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
            ...metricCards(summary.today.counts, 'today', OVERVIEW_METRICS),
            { value: summary.today.uniqueVisitors, label: 'ユニークアクセス元（全種別）' },
          ]}
        />
      </section>

      <section class="block">
        <h2>日毎の推移（{windowLabel}）</h2>
        <p class="note">
          ページビューはサイト全体（LP・機能紹介・リリース・活用例・記事）への訪問で、
          ボットとデータセンター経由を除いた数。LP（/）単独の数は流入面の
          <a href="/dashboard/traffic">「ページ別の訪問」</a>で読む。 ダウンロードの内訳（自動更新 /
          旧バージョン）とアップデート確認も、同じ面の 「内訳（全期間の累計）」に出る。
        </p>
        <SeriesChart
          title={`日毎の推移（${windowLabel}）`}
          labels={summary.daily.map((point) => point.day.slice(5))}
          series={[
            ...KIND_LABELS.filter((entry) => OVERVIEW_METRICS.has(entry.kind)).map((entry) => ({
              label: entry.label,
              unit: '件',
              values: summary.daily.map((point) => point.counts[entry.kind]),
            })),
            {
              label: '新規ダウンロード数',
              unit: '件',
              values: summary.daily.map((point) => newDownloads(point.counts)),
            },
            {
              label: 'アップデート数',
              unit: '件',
              values: summary.daily.map((point) => updateDownloads(point.counts)),
            },
          ]}
        />
      </section>

      <section class="block">
        <h2>最新イベント（直近 20 件）</h2>
        <p class="note">
          <a href="/dashboard/events">すべてのイベントを見る（100 件ずつ過去へ遡る）</a>
        </p>
        <EventTable events={summary.recent} bodyId="recent-body" />
      </section>
    </>
  )
}

/** 集計セクションを HTML 文字列にする（SSE 配信用。概要面だけがライブ更新される）。 */
export const renderOverviewSections = (summary: OverviewSummary): string =>
  (<OverviewSections summary={summary} />).toString()
