/**
 * この Worker が応答するホスト名の定義。ホスト名リテラルはここだけに置く。
 *
 * 散らすと、次にホストが増えたときに片側だけ直る（ADR 0007 の決定 6）。
 * 配布サイトは独自ドメインへ移った後も workers.dev を恒久的に併存させるため
 * （同決定 1）、本番・staging とも新旧 2 ホストずつを持つ。
 */

import { SITE_PAGES } from './pages'

/** 本番の独自ドメイン。 */
export const CANONICAL_HOST = 'befold.degino.com'

/** 本番の workers.dev ホスト。出荷済みアプリの更新経路が依存するため停止しない。 */
export const LEGACY_HOST = 'befold.tommy109.workers.dev'

/** staging の独自ドメイン。 */
export const STAGING_HOST = 'staging.befold.degino.com'

/** staging の workers.dev ホスト。 */
export const LEGACY_STAGING_HOST = 'befold-staging.tommy109.workers.dev'

/**
 * 自己ホストの集合。ここに含まれるホストからの遷移は参照元として記録しない。
 *
 * 本番・staging の新旧 4 ホストを入れる。移行期は旧ホストの LP から新ドメインへ
 * 遷移するが、これは外部からの流入ではないので参照元の集計
 * （`src/analytics.ts` の `breakdown(db,'referrer')`）に混ぜてはならない。
 */
export const SELF_HOSTS: ReadonlySet<string> = new Set([
  CANONICAL_HOST,
  LEGACY_HOST,
  STAGING_HOST,
  LEGACY_STAGING_HOST,
])

/**
 * 旧ホストから 301 で送る先。旧ホストごとに対応する新ドメインを引く。
 *
 * staging の旧ホストを本番へ送らないよう、単一の宛先ではなく対応表にする。
 */
export const REDIRECT_TARGET_ORIGIN: ReadonlyMap<string, string> = new Map([
  [LEGACY_HOST, `https://${CANONICAL_HOST}`],
  [LEGACY_STAGING_HOST, `https://${STAGING_HOST}`],
])

/**
 * 旧ホストで 301 する対象パスの**肯定列挙**（ADR 0007 の決定 2）。
 *
 * 「appcast と /dl/ を除く」という否定列挙にはしない。否定列挙は新しい機械向け
 * パスを足したときに黙って壊れるが、肯定列挙なら列挙漏れは「リダイレクトされない」
 * = 安全側に倒れる。
 *
 * `/download` は入れない。LP 由来のダウンロード計測（`source:'lp'`）が 301 を挟んで
 * 別ホストの計測へ散るのを避けるため（同決定 2）。
 *
 * 列挙は `SITE_PAGES`（`lib/pages.ts`）から導出する。言語ごとの URL を足したとき
 * （TASK-496）に同じ列挙を必要とする場所が 5 つになり、書き写す形では必ずどこかが
 * 取り残されるため。`SITE_PAGES` に機械向けの経路を載せないことが、この導出が
 * 決定 2 を守り続ける条件になる（同ファイルの doc を参照）。
 */
export const REDIRECTED_PATHS: ReadonlySet<string> = new Set(
  SITE_PAGES.map((entry) => entry.path),
)

/**
 * このリクエストにとっての自己ホスト集合を作る。
 *
 * 既知の 4 ホストに、いま来ているホストを足す。リクエストホストを足すのは
 * `wrangler dev`（localhost:8787）や preview URL のように既知でないホストで
 * 配信されている場合に、自サイト内の遷移を参照元として記録しないため。
 * 逆にリクエストホストだけでは「いま来ているホスト以外の自ホスト」を除外できず、
 * 新旧ホスト間の遷移が外部参照元になる。両方が要る。
 */
export function selfHostsFor(requestHost: string): ReadonlySet<string> {
  return new Set([...SELF_HOSTS, requestHost])
}
