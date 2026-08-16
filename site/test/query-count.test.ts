import { env } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'
import { summarize } from '../src/analytics'

/**
 * ダッシュボード 1 回の表示で発行される D1 クエリ本数の上限。
 *
 * 内訳（計 13 本）: cumulativeTotals / todayTotals / dailySeries /
 * hourlyDistribution / breakdown 3 本（version・country・referrer）/
 * trafficSplit 2 本（総数・区分別内訳）/ recentEvents / 指標別内訳 2 本
 * （OS 別・接続元組織別で、指標の数に依らない）/ eventBreakdowns 1 本。
 *
 * 指標を 1 つ足すたびにクエリが増える形（KIND_LABELS ごとに発行する）へ戻ると
 * この上限を超えて落ちる（TASK-423 の前は 19 本だった）。
 *
 * TASK-488.2 で 13 → 14。ページ別・表示言語別・ブラウザ言語設定別の 3 つの内訳を
 * 追加したが、増やしたクエリは 1 本だけ。visit の行を 3 列の組で集約すると結果は
 * 高々数十行にしかならず、軸ごとの集計は TS 側で畳めるため（`eventBreakdowns`）。
 * 軸ごとに 1 本ずつ引く形へ戻すと 16 本になり、ここで落ちる。
 *
 * TASK-488.3 でホスト別・GitHub フォールバック経路別の 2 軸を足したが、本数は
 * 14 のまま。同じ 1 本の GROUP BY へ列を足し、kind の絞り込み（visit のみ）を
 * SQL から TS 側へ移して全 kind を 1 度に集約する形にしたため。
 *
 * TASK-490 で 14 → 13。データセンター区分を足して内訳が 3 区分になったが、区分を
 * 行に持たせて `ROW_NUMBER()` の窓で切る形にしたため、区分ごとに 1 本ずつ引いて
 * いた uaSplit の 3 本が trafficSplit の 2 本になった。区分ごとに引く形へ戻すと
 * 15 本になり、ここで落ちる。
 *
 * TASK-494 で母集団別の日次ユニーク数（サイト訪問 / チャネル別のアップデート確認）を
 * 足したが、本数は 13 のまま。母集団ごとに引かず、既存の日別推移クエリの SELECT 句へ
 * `COUNT(DISTINCT CASE WHEN ... END)` を並べる形にしたため。母集団ごとに 1 本ずつ
 * 引く形へ戻すと 17 本になり、ここで落ちる。
 */
const MAX_QUERIES = 13

/** prepare の呼び出し回数を数えるためだけの薄いラッパ。 */
function countingDb(db: D1Database): { db: D1Database; count: () => number } {
  let calls = 0
  const proxy = new Proxy(db, {
    get(target, property, receiver) {
      const value = Reflect.get(target, property, receiver)
      if (property !== 'prepare' || typeof value !== 'function') return value
      return (query: string) => {
        calls += 1
        return value.call(target, query)
      }
    },
  })

  return { db: proxy as D1Database, count: () => calls }
}

describe('ダッシュボードのクエリ本数', () => {
  it('指標の数に比例して増えない', async () => {
    const { db, count } = countingDb(env.DB)

    await summarize(db, Date.parse('2026-08-08T03:00:00Z'))

    expect(count()).toBeLessThanOrEqual(MAX_QUERIES)
  })
})
