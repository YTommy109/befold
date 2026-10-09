/**
 * 人間 / ロボット / データセンターの判定を SQL 式にしたもの。
 * ボット除外（HUMAN_ONLY）の定義元で、判定を他モジュールへ書き写さない。
 */

import { datacenterOrgMatch } from '../lib/network'
import { BOT_PREFIX } from '../lib/visitor'
import { UNRECORDED_LABEL } from './shared'

/**
 * ボット判定の SQL 側の表現。値の列挙は持たず接頭辞だけで分ける（lib/visitor.ts）。
 *
 * `COALESCE` を外さないこと。`ua_summary` は NULL 許容で、`NULL LIKE ...` は
 * NULL を返す。素の LIKE を WHERE に置くと、UA ヘッダの無いリクエストで
 * 記録された行が人間でもボットでもなく黙って全集計から消える。
 */
export const BOT_MATCH = `COALESCE(ua_summary, '') LIKE '${BOT_PREFIX}%'`

/**
 * 接続元組織による自動アクセスの判定（ADR 0008）。定義元は `lib/network.ts`。
 *
 * UA 判定（`BOT_MATCH`）とは別の軸で、「UA はふつうのブラウザだが接続元が
 * データセンター」のアクセスを捕まえる。`as_org` は記録済みなので**全期間に
 * 遡って効く**（UA 分類は適用日以降しか効かない）。
 */
const DATACENTER_MATCH = datacenterOrgMatch()

/**
 * 人間の訪問ではないもの。UA でボットと分かるものと、接続元がデータセンターの
 * ものを合わせた条件。
 *
 * 2 軸を OR で束ねる形をここ以外に書かない。片方だけを見る箇所ができると、
 * 「人間側から引かれたのに自動アクセス側にも出ない」という**総和の合わない
 * 表示**になる（trafficSplit / eventBreakdowns がまさにその位置にある）。
 */
export const NON_HUMAN_MATCH = `(${BOT_MATCH} OR ${DATACENTER_MATCH})`

/**
 * ロボットの巡回・自動アクセスを集計から外すための条件。集計クエリはこれを
 * WHERE へ足す。
 *
 * 除外の条件はこの 1 箇所だけに置く（集計ごとに書き写さない）。この規約は
 * `analytics.test.ts` の「FROM events を含むクエリは HUMAN_ONLY を含むか、
 * 意図的な除外リストに載っているか」を検査するテストが担保する。
 *
 * UA 分類（TASK-386）の適用前に記録された行は種類が分からず 'other' または NULL に
 * 丸まっており、UA の軸では人間側に残る。遡って分類し直す材料（完全な UA）を
 * 保存していないため。接続元組織の軸にはこの制約が無い。この非対称は
 * ダッシュボードの注記で示す。
 */
export const HUMAN_ONLY = `NOT ${NON_HUMAN_MATCH}`

/**
 * 1 行がどの区分かを返す SQL 式。内訳を区分ごとに 1 本のクエリで取るために使う。
 *
 * 判定の順序が意味を持つ。UA でボットと分かるものを先に見る——データセンターから
 * 来る Googlebot を「データセンター」に寄せると、ADR 0004 が測りたかった
 * 「AI クローラの到来量」がクローラ名の内訳から消えるため。
 */
export const TRAFFIC_CLASS_EXPR =
  `CASE WHEN ${BOT_MATCH} THEN '${'bot' satisfies TrafficClass}'` +
  ` WHEN ${DATACENTER_MATCH} THEN '${'datacenter' satisfies TrafficClass}'` +
  ` ELSE '${'human' satisfies TrafficClass}' END`

/**
 * 区分ごとの内訳ラベルを選ぶ SQL 式。
 *
 * データセンター区分だけ `as_org` を出す。UA を出しても `Chrome` や `other` が
 * 並ぶだけで、どこから来たのかが読めないため。値が無い行は「未記録」に寄せる
 * （区分から黙って落とさない）。
 */
export const TRAFFIC_LABEL_EXPR =
  `CASE WHEN ${DATACENTER_MATCH} AND NOT ${BOT_MATCH}` +
  ` THEN COALESCE(as_org, '${UNRECORDED_LABEL}')` +
  ` ELSE COALESCE(ua_summary, '${UNRECORDED_LABEL}') END`

/**
 * アクセスの区分。人間・UA で分かるロボット・接続元がデータセンターの 3 つ。
 *
 * `datacenter` を `bot` に混ぜない。判定の軸（UA / 接続元組織）も、遡って効くか
 * どうかも違うため、画面上で分けて読めないと「いつからの数字か」が分からなくなる。
 */
export type TrafficClass = 'human' | 'bot' | 'datacenter'

export const TRAFFIC_CLASSES: TrafficClass[] = ['human', 'bot', 'datacenter']
