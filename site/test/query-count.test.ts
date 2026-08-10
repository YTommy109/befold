import { env } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'
import { summarize } from '../src/analytics'

/**
 * ダッシュボード 1 回の表示で発行される D1 クエリ本数の上限。
 *
 * 内訳（TASK-423 時点、計 13 本）: cumulativeTotals / todayTotals / dailySeries /
 * hourlyDistribution / breakdown 3 本（version・country・referrer）/ uaSplit 3 本 /
 * recentEvents / 指標別内訳 2 本（OS 別・接続元組織別で、指標の数に依らない）。
 *
 * 指標を 1 つ足すたびにクエリが増える形（KIND_LABELS ごとに発行する）へ戻ると
 * この上限を超えて落ちる（TASK-423 の前は 19 本だった）。
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
