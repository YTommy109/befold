#!/usr/bin/env node
/**
 * ローカル D1 にダッシュボード確認用のサンプルデータを流し込む。
 *
 * 空の DB ではグラフが「期間内のデータなし」にしかならず、レイアウトや
 * ラベルの見え方を確認できないため。worktree ごとにローカル D1
 * （site/.wrangler 配下）が別なので、各 worktree でこれを実行する。
 *
 * 生成は決定的（固定シードの xorshift）で、日付だけは実行時刻から
 * 逆算する。日別推移の窓が「当日を含む直近 14 日」なので、固定日付に
 * するとすぐ窓から外れて何も表示されなくなる。
 *
 * 対象は --local のみ。リモート D1 には触れない。
 */

import { execFileSync } from 'node:child_process'
import { createHash, randomUUID } from 'node:crypto'
import { writeFileSync, unlinkSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const WINDOW_DAYS = 14
const DAY_MS = 24 * 60 * 60 * 1000
const JST_OFFSET_MS = 9 * 60 * 60 * 1000

/** 固定シードの疑似乱数。実行のたびに同じ形の山ができるようにする。 */
function makeRandom(seed) {
  let state = seed
  return () => {
    state ^= state << 13
    state ^= state >>> 17
    state ^= state << 5
    state >>>= 0
    return state / 0x1_0000_0000
  }
}

const random = makeRandom(20260808)
const pick = (items) => items[Math.floor(random() * items.length)]
const between = (min, max) => min + Math.floor(random() * (max - min + 1))

/** 時間帯の重み（JST）。昼と夜に山、深夜は薄い。 */
const HOUR_WEIGHTS = [1, 1, 1, 1, 1, 1, 2, 4, 7, 9, 10, 9, 8, 9, 10, 11, 10, 9, 8, 9, 10, 8, 5, 3]

function pickHour() {
  const total = HOUR_WEIGHTS.reduce((sum, weight) => sum + weight, 0)
  let threshold = random() * total
  for (const [hour, weight] of HOUR_WEIGHTS.entries()) {
    threshold -= weight
    if (threshold <= 0) return hour
  }
  return 12
}

const COUNTRIES = ['JP', 'JP', 'JP', 'JP', 'JP', 'US', 'US', 'DE', 'GB', 'KR']
const OSES = ['macOS 15.0', 'macOS 15.0', 'macOS 14.5', 'macOS 14.5', 'Windows', 'Linux', 'iOS']
// AI クローラを混ぜるのは、クライアント種別の内訳が実運用でどう見えるかを確かめるため。
const UAS = ['Safari', 'Safari', 'Chrome', 'Chrome', 'Sparkle', 'ClaudeBot', 'GPTBot', 'curl']
const REFERRERS = [null, null, null, 'gh-pages', 'https://news.ycombinator.com', 'google']
const AS_ORGS = [null, null, 'NTT Communications', 'KDDI', 'SoftBank', 'Google LLC']
const VERSIONS = ['v1.10.0', 'v1.10.0', 'v1.10.0', 'v1.9.0', 'v1.8.1']

/** 実際の visitor_token と同じ 64 桁 16 進にする（形が違うと集計の見え方も変わる）。 */
const visitorToken = (label) => createHash('sha256').update(label).digest('hex')

/** JST の日付を保ったまま、指定の時分秒に置き換えた epoch ms を返す。 */
function jstTimeOnDay(dayOffset, hour, minute, second) {
  const base = new Date(Date.now() + JST_OFFSET_MS - dayOffset * DAY_MS)
  const day = base.toISOString().slice(0, 10)
  const clock = [hour, minute, second].map((n) => String(n).padStart(2, '0')).join(':')
  return Date.parse(`${day}T${clock}+09:00`)
}

const quote = (value) =>
  value === null ? 'NULL' : `'${String(value).replace(/'/g, "''")}'`

function buildRows() {
  const now = Date.now()
  const rows = []

  for (let dayOffset = WINDOW_DAYS - 1; dayOffset >= 0; dayOffset -= 1) {
    for (let visitor = 0; visitor < between(3, 14); visitor += 1) {
      const ts = jstTimeOnDay(dayOffset, pickHour(), between(0, 59), between(0, 59))
      if (ts > now) continue

      const token = visitorToken(`seed-${dayOffset}-${visitor}`)
      const shared = {
        country: pick(COUNTRIES),
        os: pick(OSES),
        ua: pick(UAS),
        referrer: pick(REFERRERS),
        asOrg: pick(AS_ORGS),
        token,
      }

      for (let repeat = 0; repeat < between(1, 3); repeat += 1) {
        rows.push({ ...shared, ts: ts + between(0, 600_000), kind: 'visit', version: null, channel: null })
      }
      if (random() < 0.35) {
        rows.push({
          ...shared,
          ts: ts + between(0, 900_000),
          kind: 'download',
          version: pick(VERSIONS),
          channel: 'stable',
        })
      }
      if (random() < 0.5) {
        rows.push({
          ...shared,
          ua: 'Sparkle',
          referrer: null,
          ts: ts + between(0, 900_000),
          kind: 'update_check',
          version: null,
          channel: 'stable',
        })
      }
    }
  }

  return rows.filter((row) => row.ts <= now)
}

function buildSql(rows) {
  const statements = rows.map(
    (row) =>
      'INSERT INTO events' +
      ' (timestamp, kind, version, channel, country, os, ua_summary, visitor_token, referrer, as_org)' +
      ` VALUES (${row.ts}, ${quote(row.kind)}, ${quote(row.version)}, ${quote(row.channel)},` +
      ` ${quote(row.country)}, ${quote(row.os)}, ${quote(row.ua)}, ${quote(row.token)},` +
      ` ${quote(row.referrer)}, ${quote(row.asOrg)});`,
  )

  // 何度実行しても同じ状態になるように、既存行を消してから入れ直す。
  return ['DELETE FROM events;', ...statements].join('\n')
}

const rows = buildRows()
const sqlPath = join(tmpdir(), `befold-seed-${randomUUID()}.sql`)
writeFileSync(sqlPath, buildSql(rows))

try {
  execFileSync(
    'npx',
    ['wrangler', 'd1', 'execute', 'befold-analytics', '--local', '--file', sqlPath],
    { stdio: ['ignore', 'ignore', 'inherit'] },
  )
  console.log(`ローカル D1 に ${rows.length} 行のサンプルデータを投入しました（直近 ${WINDOW_DAYS} 日）。`)
  console.log('既存の行は削除しています。npm run dev で /dashboard を確認してください。')
} finally {
  unlinkSync(sqlPath)
}
