/**
 * 配信面（DeliverySections）。配布ホストと旧経路のフォールバック。
 * 他の面のセクションは置かない。
 */
import type { FC } from 'hono/jsx'

import type { DeliverySummary } from '../../analytics'
import { DELIVERY_RECENT_DAYS, DELIVERY_WINDOW_DAYS, UNRECORDED_LABEL } from '../../analytics'
import { CANONICAL_HOST, LEGACY_HOST } from '../../lib/hosts'
import { SeriesChart } from './chart'
import { RouteTable } from './parts'

/**
 * リクエスト先ホストの記録を始めた日（TASK-488.3）。これより前の行はどのホストで
 * 応答したかを復元できない。
 */
const HOST_COLUMN_START = '2026-08-16'

/**
 * 配信面のセクション。配布ホストと旧経路のフォールバック。
 */
export const DeliverySections: FC<{ summary: DeliverySummary }> = ({ summary }) => {
  return (
    <>
      <section class="block">
        <h2>配布ホストと旧経路</h2>
        <p class="note">
          旧ホスト（{LEGACY_HOST}）と GitHub へのフォールバックを止めてよいかの判断材料 （ADR
          0007）。ホスト別は kind を問わない全イベントが対象で、0 件のホストも 行として残す（「まだ
          0」と「計測していない」を区別するため）。 ホスト列の導入前（{HOST_COLUMN_START}
          ）に記録された行は、どのホストで応答したかを 復元できないので「{UNRECORDED_LABEL}
          」に入る。
        </p>
        <p class="note">
          旧ホストの HTML ページ（LP・機能紹介）は正規ホストへ 301 で送るため、 その到達は visit
          ではなく「旧ホストからの 301」として数える（301 を追った先で 正規ホスト側の visit
          も記録されるので、visit にすると二重に数えられる）。
          機械向けの経路（appcast・/dl/・/download）は 301 せず素通しなので、旧ホストの
          ままホスト別に出る。旧ホストの静的アセットと /healthz は元々記録していない。
        </p>
        <p class="note">
          GitHub フォールバックは R2 に目的のオブジェクトが無かった回数。ここが 0 でない うちは
          GitHub 側の経路を止められない。appcast の行だけは caches.default（300
          秒）に当たった周期を数えられないため、実際より小さく出る。
        </p>
        <p class="note">
          <strong>累計だけでは止めてよいかを判断できない。</strong>
          一度発生すると累計は二度と減らないため、クローラが旧タグを一斉に舐めた跡が
          いつまでも「まだ落ちている」ように見える（実測 2026-09-04: GitHub フォールバック 266
          件のうち 262 件が 8/19〜8/26 のボット由来）。 判断は
          <strong>直近 {DELIVERY_WINDOW_DAYS} 日の人間の件数</strong>と
          <strong>人間の最終発生</strong>で読み、累計は参考値として置く。
        </p>
        <p class="note">
          <strong>最終発生を人間とロボットで分けている。</strong>
          停止条件は人間が来なくなったかで決まるのに、両者を混ぜた最終発生は
          ロボットが作り続ける（実測 2026-09-04: 旧ホストの直近の発生は Googlebot・
          Meta-ExternalAgent で、Sparkle は 08-21 が最後）。 一度も発生していない経路は 「—」で、0
          件と「大昔に 1 度だけ」を混同させない。
        </p>
        <p class="note">
          「{UNRECORDED_LABEL}」行の最終発生は出さない。ホスト列は導入後の全行に入るので、
          この行が示すのは<strong>列を入れた時期</strong>であって経路の生死ではない。
        </p>
        <p class="note">
          なお <code>dmg-invalid</code> は R2 の欠落ではなく、配布対象でないタグ・ファイル名を
          弾いた（＝いたずら半分のパス探索を含む）リクエストなので、
          停止判断の材料には数えない。この値の導入前に記録された <code>dmg</code>{' '}
          行は両者の混合で、遡って分離できない。
        </p>
        <div class="grid">
          <RouteTable
            title="リクエスト先ホスト別"
            rows={summary.hosts}
            windowDays={DELIVERY_WINDOW_DAYS}
            recentDays={DELIVERY_RECENT_DAYS}
          />
          <RouteTable
            title="GitHub フォールバックの経路別"
            rows={summary.fallbacks}
            windowDays={DELIVERY_WINDOW_DAYS}
            recentDays={DELIVERY_RECENT_DAYS}
          />
        </div>
      </section>

      <section class="block">
        <h2>停止判断の対象経路の推移（直近 {DELIVERY_WINDOW_DAYS} 日）</h2>
        <p class="note">
          一過性のスパイクと定常的な流入を分けて読むための図。人間の棒が途切れて
          ロボットの棒だけが続いているなら、その経路は<strong>もう人間には使われていない</strong>。
          正規ホスト（{CANONICAL_HOST}）は停止判断の対象ではないので描かない。
        </p>
        <div class="grid">
          <section>
            <h3>旧ホスト（{LEGACY_HOST}）へのアクセス</h3>
            <SeriesChart
              title={`旧ホストへのアクセス（直近 ${DELIVERY_WINDOW_DAYS} 日）`}
              labels={summary.dailyRoutes.map((point) => point.day.slice(5))}
              series={[
                {
                  label: '人間',
                  unit: '件',
                  values: summary.dailyRoutes.map((point) => point.legacyHuman),
                },
                {
                  label: 'ロボット',
                  unit: '件',
                  values: summary.dailyRoutes.map((point) => point.legacyBot),
                },
              ]}
            />
          </section>
          <section>
            <h3>GitHub フォールバック</h3>
            <SeriesChart
              title={`GitHub フォールバック（直近 ${DELIVERY_WINDOW_DAYS} 日）`}
              labels={summary.dailyRoutes.map((point) => point.day.slice(5))}
              series={[
                {
                  label: '人間',
                  unit: '件',
                  values: summary.dailyRoutes.map((point) => point.fallbackHuman),
                },
                {
                  label: 'ロボット',
                  unit: '件',
                  values: summary.dailyRoutes.map((point) => point.fallbackBot),
                },
              ]}
            />
          </section>
        </div>
      </section>
    </>
  )
}
