/**
 * イベント面（EventsSections）。人間のアクセスだけを新しい順に並べるページ送り付きの一覧。
 * 他の面のセクションは置かない。
 */
import type { FC } from 'hono/jsx'

import type { EventPage } from '../../analytics'
import { EVENTS_PAGE_LIMIT } from '../../analytics'
import { EventTable } from './parts'

/**
 * イベント面のセクション。人間のアクセスだけを新しい順に 1 ページ 100 件で並べる。
 *
 * ページ送りは id を基準にしたカーソル（`?before=` / `?after=`）で、`OFFSET` は
 * 使わない。ページを見ている間に新しいイベントが入っても境界がずれないため、
 * 送っている途中で同じ行が 2 度出たり抜けたりしない。
 *
 * この面は開いた時点のスナップショットで SSE に接続しない。過去を見ている最中に
 * 先頭へ行が挿し込まれると、読んでいる位置がずれるため。
 */
export const EventsSections: FC<{ page: EventPage }> = ({ page }) => (
  <section class="block">
    <h2>イベント（人間のアクセスのみ・新しい順）</h2>
    <p class="note">
      1 ページ {EVENTS_PAGE_LIMIT} 件。ロボットとデータセンターからのアクセスは
      集計と同じ条件で除いている。
    </p>
    {page.events.length === 0 ? (
      <p class="empty">該当するイベントはありません。</p>
    ) : (
      <EventTable events={page.events} />
    )}
    <nav class="pager">
      {page.newerCursor === undefined ? (
        <span class="pager-disabled">← 新しい 100 件</span>
      ) : (
        <a href={`/dashboard/events?after=${page.newerCursor}`}>← 新しい 100 件</a>
      )}
      {page.olderCursor === undefined ? (
        <span class="pager-disabled">古い 100 件 →</span>
      ) : (
        <a href={`/dashboard/events?before=${page.olderCursor}`}>古い 100 件 →</a>
      )}
    </nav>
  </section>
)
