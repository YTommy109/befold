/**
 * 利用者面（UsersSections）。日別のユニークアクセス元、時間帯分布、稼働バージョン、
 * アップデートの取り込み。他の面のセクションは置かない。
 */
import type { FC } from 'hono/jsx'

import type { UsersSummary } from '../../analytics'
import {
  KIND_LABELS,
  RUNNING_VERSION_LABELS,
  RUNNING_VERSION_TABLE_LABELS,
  TOP_N,
  UNIQUE_SOURCE_LABELS,
} from '../../analytics'
import { SeriesChart } from './chart'
import { CountTable } from './parts'

/**
 * 稼働バージョンの記録を始めた日（TASK-491.1、
 * migrations/20260816064525_add_app_version.sql）。これより前の update_check は
 * どのバージョンから来たかを復元できない。
 */
const APP_VERSION_COLUMN_START = '2026-08-16'

/** 率の表示。分母が 0 の日は率を出さない（0 除算を「0%」と読ませない）。 */
const ratioLabel = (numerator: number, denominator: number): string =>
  denominator === 0 ? '—' : `${Math.round((numerator / denominator) * 100)}%`

/**
 * アップデートの取り込み（転換率と取り込み曲線）。
 *
 * 率だけを大きく出さず、**分母の実数を必ず併記する**。タグ単位に割ると 1 桁に
 * なる規模なので、率だけでは誤読を招く。
 */
const UpdateAdoption: FC<{ summary: UsersSummary; windowLabel: string }> = ({
  summary,
  windowLabel,
}) => (
  <>
    <section class="block">
      <h2>確認から更新への転換（{windowLabel}）</h2>
      <p class="note">
        数えているのは
        <strong>
          その日にアップデート確認を送ってきたアクセス元のうち、
          同じ日に実際に更新まで進んだものの割合
        </strong>
        。 「更新した利用者の割合」ではない。分母 （確認）はアプリが起動時などに自動で飛ばすもので、
        アクセス元は日別ユニークと同じ visitor_token（接続元 IP と User-Agent の組を
        その日のうちだけ同一視するハッシュ）。 単位は「アクセス元×日」の異なり数。
      </p>
      <p class="note">
        「確認の記録なし」は、更新は観測したのに
        <strong>同じ日・同じチャネルの確認が 見つからなかった</strong>
        アクセス元の数。前日に確認して当日落ちてきた場合や、 appcast の取得と DMG の取得で
        User-Agent が変わって別のアクセス元として 数えられた場合に出る。分子へ入れると率が 100%
        を超えるため、率には混ぜず 別の列に出している。
      </p>
      <div class="grid">
        {RUNNING_VERSION_LABELS.map(({ key, label }) => (
          <section>
            <h3>{label}: 確認 → 更新</h3>
            {summary.conversion[key].every((point) => point.checked === 0) ? (
              <p class="empty">期間内のデータなし</p>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>日付</th>
                    <th>確認</th>
                    <th>更新</th>
                    <th>転換率</th>
                    <th>確認の記録なし</th>
                  </tr>
                </thead>
                <tbody>
                  {summary.conversion[key]
                    .filter((point) => point.checked > 0 || point.downloadedWithoutCheck > 0)
                    .map((point) => (
                      <tr>
                        <td>{point.day.slice(5)}</td>
                        <td>{point.checked}</td>
                        <td>{point.converted}</td>
                        <td>{ratioLabel(point.converted, point.checked)}</td>
                        <td>{point.downloadedWithoutCheck}</td>
                      </tr>
                    ))}
                </tbody>
              </table>
            )}
          </section>
        ))}
      </div>
    </section>

    <section class="block">
      <h2>リリース後の取り込み（{windowLabel}）</h2>
      <p class="note">
        タグごとに、<strong>そのタグの更新を最初に観測した日を 0 日目として</strong>、
        経過日数ごとの累積アクセス元数を出す。 0 日目は<strong>リリースの公開日ではない</strong>。
        イベントにはリリースの公開時刻が無く、 R2 の latest.json も版とファイル名しか持たないため、
        観測の初出で代用している。 公開してから誰かが落とすまでに間があると、その分だけ曲線は
        速く見える。
      </p>
      <p class="note">
        数えるのは Worker 経由（enclosure が /dl/ を通る）の自動アップデートだけ。 配布 LP
        からのダウンロードは新規獲得なので含めない。 {windowLabel}
        の中で初めて観測したタグに限るため、それ以前に出たタグは出てこない。 現在の規模ではタグ 1
        つあたりのアクセス元が 1 桁になる。率ではなく実数で出しているのはそのため。
      </p>
      {summary.adoption.length === 0 ? (
        <p class="empty">期間内のデータなし</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th>タグ</th>
              <th>チャネル</th>
              <th>初回観測</th>
              <th>経過日数ごとの累積アクセス元</th>
            </tr>
          </thead>
          <tbody>
            {summary.adoption.map((entry) => (
              <tr>
                <td>{entry.version}</td>
                <td>{entry.channel}</td>
                <td>{entry.firstSeenDay.slice(5)}</td>
                <td>
                  {entry.cumulative
                    .map((point) => `${point.elapsedDays}日目: ${point.sources}`)
                    .join(' / ')}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  </>
)

export const UsersSections: FC<{ summary: UsersSummary }> = ({ summary }) => {
  const windowLabel = `直近 ${summary.windowDays} 日`

  return (
    <>
      <section class="block">
        <h2>日別のユニークアクセス元（{windowLabel}）</h2>
        <p class="note">
          利用者数そのものではなく近似。数えているのは「その日に記録されたアクセス元の
          異なり数」で、アクセス元は接続元 IP と User-Agent の組をその日のうちだけ
          同一視できるハッシュ（visitor_token）。同じ人でも回線が変われば別々に数えるため
          モバイル回線・VPN では過大に振れ、逆に同じ回線・同じ端末構成の複数台は 1 として数えるため
          NAT の内側では過小に振れる。ハッシュには日付が混ぜて
          あるので日をまたぐ同一人物は追えず、ここに出るのは常に「その日の」異なり数。
          通算のユニーク利用者数は出せない（出さない）。
        </p>
        <p class="note">
          サイト訪問（visit）とアプリ（アップデート確認）は母集団が違うので合算しない。
          アプリ側はアプリを起動して appcast を取りに来た端末で、stable と develop を
          分けている（develop には開発機が含まれるため、混ぜると利用者の規模を
          過大に見積もる）。ここの「サイト訪問」は概要面の「ページビュー」と同じ範囲
          （全ページ）だが、数えているのは延べ回数ではなくアクセス元の異なり数。
          ロボットの除外は他の集計と同じ条件だが、 curl
          のような自動アクセスはボット判定に当たらずここに残る。
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
          series={KIND_LABELS.map((entry) => ({
            label: entry.label,
            unit: '件',
            values: summary.hourly.map((point) => point.counts[entry.kind]),
          }))}
        />
      </section>

      <section class="block">
        <h2>稼働中のアプリバージョン（{windowLabel}）</h2>
        <p class="note">
          数えているのは<strong>アップデート確認を送ってきたアクセス元の異なり数</strong>で、
          確認の延べ回数ではない。アップデート確認はアプリが定期的に飛ばすため、回数で
          数えるとバージョンではなく起動回数を見ることになる。アクセス元は日別ユニークと 同じ
          visitor_token（接続元 IP と User-Agent の組をその日のうちだけ同一視する
          ハッシュ）なので、単位は「アクセス元×日」の異なり数であって通算の利用者数では
          ない。同じ端末でも、期間中の 5 日に確認を送れば 5 と数える。
        </p>
        <p class="note">
          全期間ではなく{windowLabel}に絞っている。見たいのは今も使われ続けている版で
          あって、過去に一度でも動いた版の履歴ではないため。develop は表に出していない。
          作者の開発機しか映らないうえ、単位が「アクセス元×日」なので同じ 1 台が回線や日を
          またぐたびに増え、利用者の分布としては読めないため（下の「確認 → 更新」には
          残してある）。上位 {TOP_N} 件まで。
        </p>
        <p class="note">
          流入面の「ダウンロード（LP）: バージョン別」とは別物。あちらは
          <strong>どのタグを取りに来たか</strong>（更新先）で、こちらは
          <strong>今どのバージョンが動いているか</strong>（更新元）。 稼働バージョンの記録は{' '}
          {APP_VERSION_COLUMN_START} に始めたもので、それより前の
          アップデート確認はどのバージョンから来たかを<strong>遡って分類できない</strong>。 Sparkle
          以外のクライアント（curl など）からの確認も、バージョンを名乗らないので ここには出ない。
        </p>
        <div class="grid">
          {RUNNING_VERSION_TABLE_LABELS.map(({ key, label }) => (
            <CountTable title={`${label}: 稼働バージョン別`} rows={summary.runningVersions[key]} />
          ))}
        </div>
      </section>
      <UpdateAdoption summary={summary} windowLabel={windowLabel} />
    </>
  )
}
