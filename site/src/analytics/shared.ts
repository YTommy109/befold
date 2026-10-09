/**
 * 面の一覧と、集計の窓幅・件数上限・共通ラベル。
 * SQL 断片や取得関数は置かない（それぞれ metrics.ts / access-class.ts と各クエリ側）。
 */

export type Count = { label: string; count: number }

/**
 * ダッシュボードの面の識別子。**これが唯一の定義元。**
 *
 * ルートの生成・面ごとの集計・ナビゲーション・クエリ本数の上限テストは
 * すべてここから導く。面を別々に書き写すと、レジストリに載っていない面が
 * 上限テストの列挙から漏れ、「面を増やせば上限を回避できる」形に戻る。
 * 実行時に配列が要るので型ではなく値で持つ（`Record<DashboardPageKey, ...>` の
 * 網羅は型で検査される）。
 */
export const DASHBOARD_PAGE_KEYS = ['overview', 'users', 'traffic', 'delivery', 'events'] as const

export type DashboardPageKey = (typeof DASHBOARD_PAGE_KEYS)[number]

/** 面の定義。path はダッシュボードのルート配下の相対パス。 */
export type DashboardPage = { key: DashboardPageKey; path: string; title: string }

/**
 * 面の一覧。ルート生成・ナビゲーション・テストの列挙がこの配列を共有する。
 *
 * 概要面だけが SSE でライブ更新される。他の面は分析用のスナップショットで、
 * 更新されているように読ませないため SSE の状態表示も出さない。
 */
export const DASHBOARD_PAGES: readonly DashboardPage[] = [
  { key: 'overview', path: '/', title: '概要' },
  { key: 'users', path: '/users', title: '利用者' },
  { key: 'traffic', path: '/traffic', title: '流入' },
  { key: 'delivery', path: '/delivery', title: '配信' },
  { key: 'events', path: '/events', title: 'イベント' },
]

/** 日別推移・時間帯分布が対象にする窓（当日を含む直近 N 日）。 */
export const DAILY_WINDOW_DAYS = 14

/**
 * 配信面の日次推移と「直近」列が対象にする窓（当日を含む直近 N 日）。
 *
 * **`DAILY_WINDOW_DAYS`（14 日）を流用しない。** 停止判断で読みたいのは
 * 「一過性のクローラのスパイクだったのか、今も続く流入なのか」で、これは
 * 発生から 2 週間では判別が付かない。実測（2026-09-04）では GitHub フォールバック
 * 266 件のうち 2026-08-19〜08-21 の 172 件がクローラの一斉巡回だったが、14 日窓では
 * その 3 日が窓の外へ落ち、肝心のスパイクが画面から消える。
 */
export const DELIVERY_WINDOW_DAYS = 30

/** 配信面の「直近」列のうち短いほうの窓（当日を含む直近 N 日）。 */
export const DELIVERY_RECENT_DAYS = 7
/**
 * 内訳を切り出す上位 N 件。ダッシュボードの注記もこの値を読む（画面の説明と
 * 実際の切り出し件数がずれないように、数字を書き写さない）。
 */
export const TOP_N = 10

/**
 * イベント面の 1 ページあたりの件数。
 *
 * 概要面の `RECENT_LIMIT`（20 件）とは別の定数にする。概要面は「いま何が
 * 起きているか」を一目で見るための短い一覧で、イベント面は過去へ遡るための
 * 一覧なので、片方を変えたときにもう片方まで動くと困る。
 */
export const EVENTS_PAGE_LIMIT = 100

/** SSE の 1 周期で流す新着イベントの上限。再開位置の判断に呼び出し側も使う。 */
export const STREAM_LIMIT = 100

/** 値が記録されていない行のラベル。列の導入前に記録された visit がここに入る。 */
export const UNRECORDED_LABEL = '未記録'
