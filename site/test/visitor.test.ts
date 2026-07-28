import { describe, expect, it } from 'vitest'
import { dayKey, summarizeOS, summarizeUA, visitorDayHash } from '../src/lib/visitor'

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 Safari/605.1.15'

describe('visitorDayHash', () => {
  it('同じ IP・UA・日付なら同じハッシュになる', async () => {
    const ts = Date.parse('2026-07-28T01:00:00Z')
    const a = await visitorDayHash('203.0.113.5', UA, ts)
    const b = await visitorDayHash('203.0.113.5', UA, Date.parse('2026-07-28T23:59:00Z'))

    expect(a).toBe(b)
    expect(a).toMatch(/^[0-9a-f]{64}$/)
  })

  it('日付が変われば別のハッシュになる', async () => {
    const a = await visitorDayHash('203.0.113.5', UA, Date.parse('2026-07-28T01:00:00Z'))
    const b = await visitorDayHash('203.0.113.5', UA, Date.parse('2026-07-29T01:00:00Z'))

    expect(a).not.toBe(b)
  })

  it('IP が変われば別のハッシュになり、元の IP は含まれない', async () => {
    const ts = Date.parse('2026-07-28T01:00:00Z')
    const a = await visitorDayHash('203.0.113.5', UA, ts)
    const b = await visitorDayHash('203.0.113.6', UA, ts)

    expect(a).not.toBe(b)
    expect(a).not.toContain('203.0.113.5')
  })
})

describe('dayKey', () => {
  it('UTC の YYYY-MM-DD を返す', () => {
    expect(dayKey(Date.parse('2026-07-28T23:30:00Z'))).toBe('2026-07-28')
  })
})

describe('UA 要約', () => {
  it('macOS のメジャーバージョンとブラウザ種別だけを残す', () => {
    expect(summarizeOS(UA)).toBe('macOS 14.5')
    expect(summarizeUA(UA)).toBe('Safari')
  })

  it('Sparkle のアップデートチェックを識別する', () => {
    expect(summarizeUA('befold/1.2.3 Sparkle/2.6.4')).toBe('Sparkle')
  })

  it('未知の UA では null / other を返す', () => {
    expect(summarizeOS('')).toBeNull()
    expect(summarizeUA('')).toBeNull()
    expect(summarizeUA('SomeBot/1.0')).toBe('other')
  })
})
