/**
 * 流入面（TrafficSections）。内訳・ページ別・言語別・人間と自動アクセス。
 * 他の面のセクションは置かない。
 */
import type { FC } from 'hono/jsx'

import type { TrafficSummary } from '../../analytics'
import { UNRECORDED_LABEL, VERSION_BREAKDOWN_METRICS } from '../../analytics'
import { Cards, CountTable, splitRows } from './parts'

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
 * 接続元組織（as_org）の記録を始めた日（migrations/20260730022424_add_as_org.sql）。
 * データセンター判定はこの列だけを見るため、この日以降は遡って効く。
 */
const AS_ORG_COLUMN_START = '2026-07-30'

/**
 * 流入面のセクション。内訳・ページ別・言語別・人間と自動アクセス。
 *
 * すべて全期間の累計で見るため窓の表示は持たない。
 */
export const TrafficSections: FC<{ summary: TrafficSummary }> = ({ summary }) => {
  return (
    <>
      <section class="block">
        <h2>内訳（全期間の累計）</h2>
        {/* 概要面はページビューと新規ダウンロード・アップデート数だけを出すので、指標ごとの総数
            （アップデート確認・ダウンロードの内訳）はここでしか読めない。数字は
            概要カードと同じ cumulativeTotals から来ており、クエリは増えない。 */}
        <Cards
          cards={summary.perKind.map((entry) => ({
            value: entry.total,
            label: entry.label,
            id: `traffic-${entry.kind}`,
          }))}
        />
        <div class="grid">
          <CountTable title="国別" rows={summary.byCountry} />
          <CountTable title="参照元別" rows={summary.byReferrer} />
          {/* 上の「参照元別」は全イベントで「どこから来訪したか」を見る軸。こちらは
              ダウンロード（LP）だけに絞り、`?ref=` が運ぶ「どの面のボタンから
              押されたか」を見る（TASK-549）。同じ列を使うが答える問いが違う。 */}
          <CountTable title="ダウンロード（LP）: 参照元別" rows={summary.byDownloadReferrer} />
          {summary.perKind.map((entry) => [
            <CountTable title={`${entry.label}: OS 別`} rows={entry.byOS} />,
            <CountTable title={`${entry.label}: 接続元組織別`} rows={entry.byAsOrg} />,
            // バージョン別はダウンロード系の指標にだけ意味がある（visit や
            // update_check の行では version が常に NULL）。旧バージョンへ戻した
            // 分がどの版へ向かったかは、この表で読む。
            VERSION_BREAKDOWN_METRICS.has(entry.kind) ? (
              <CountTable title={`${entry.label}: バージョン別`} rows={entry.byVersion} />
            ) : null,
          ])}
        </div>
      </section>

      <section class="block">
        <h2>ページ別の訪問（全期間の累計）</h2>
        <p class="note">
          この表は visit のみが対象で、ダウンロードやアップデート確認は元々ページを持たない。
          自動アクセスを含む点が概要面の「ページビュー」と違う（あちらはボットと
          データセンター経由を除く）ので、人間側の合計とも一致するとは限らない。
          ページ列を導入する前に記録された訪問はページが記録されていないが、当時計上して いたのは LP
          だけなので「/」に数えている。
        </p>
        <div class="grid">
          <CountTable title="人間: ページ別" rows={splitRows(summary.visits.byPage, false)} />
          <CountTable
            title="自動アクセス: ページ別"
            rows={splitRows(summary.visits.byPage, true)}
          />
        </div>
      </section>

      <section class="block">
        <h2>言語別の訪問（全期間の累計）</h2>
        <p class="note">
          「表示言語」は実際に配信したページの言語で、URL（/ と /en）が決める。
          「ブラウザ言語設定」は Accept-Language の第一希望を ja / en / other に丸めたもので、
          <strong>ブラウザの設定であって実際に読まれた言語ではない</strong>。 2
          つを並べているのは、英語を求めて来た人が英語ページへ辿り着けたかを見るため（
          ブラウザ言語設定が en で表示言語が ja なら、辿り着けていない）。 言語ごとに URL
          を分ける前（{LANGUAGE_URL_START}）に記録された訪問は、日英を同じ HTML
          で出していたため表示言語が確定せず「{UNRECORDED_LABEL}」になる。遡って
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
          ロボットとデータセンター由来の<strong>両方</strong>を除いた数。判定の軸はふたつある（ADR
          0008）。
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
          含めない。誤って人間を落とすと、まだ使われている配布経路を止めてしまうため （ADR 0007
          の停止判断にこの数字を使う）。
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
    </>
  )
}
