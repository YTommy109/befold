import { env } from 'cloudflare:test'
import { afterEach, describe, expect, it } from 'vitest'

import { kindBreakdowns } from '../src/analytics/breakdowns'
import { clearEvents } from './analytics-helpers'

afterEach(clearEvents)

// 記録済みの OS 列から macOS のバージョンを落とす移行（TASK-904）。ブラウザは UA の
// macOS バージョンを 10_15_7 に固定するため、残すと実態の無い「macOS 10.15」が
// OS 別内訳に並び続ける。テストの D1 には setup で全移行が適用済みなので、移行前の
// 値を入れてからこの移行の文だけをもう一度流す（UPDATE は何度流しても同じ結果になる）。
describe('OS バージョンを落とす移行', () => {
  it('バージョン付きの macOS を 1 行にまとめ、他の OS には触れない', async () => {
    for (const os of ['macOS 10.15', 'macOS 10.15', 'macOS 14.5', 'macOS', 'Windows']) {
      await env.DB.prepare(
        "INSERT INTO events (timestamp, kind, os, ua_summary) VALUES (0, 'visit', ?, 'Safari')",
      )
        .bind(os)
        .run()
    }
    const migration = env.TEST_MIGRATIONS.find(({ name }) => name.endsWith('_drop_os_version.sql'))
    expect(migration).toBeDefined()
    for (const query of migration?.queries ?? []) await env.DB.prepare(query).run()

    const visits = (await kindBreakdowns(env.DB)).find(({ kind }) => kind === 'visit')
    expect(visits?.byOS).toEqual([
      { label: 'macOS', count: 4 },
      { label: 'Windows', count: 1 },
    ])
  })
})
