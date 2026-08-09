import { describe, expect, it } from 'vitest'
import { dayKey, isBotSummary, summarizeOS, summarizeUA, visitorTokenHash } from '../src/lib/visitor'

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 Safari/605.1.15'

describe('visitorTokenHash', () => {
  it('同じ IP・UA・日付（JST）なら同じハッシュになる', async () => {
    // JST の同じ日に収まる 2 点（UTC では日をまたぐ）。
    const ts = Date.parse('2026-07-27T15:00:00Z')
    const a = await visitorTokenHash('203.0.113.5', UA, ts)
    const b = await visitorTokenHash('203.0.113.5', UA, Date.parse('2026-07-28T14:59:00Z'))

    expect(a).toBe(b)
    expect(a).toMatch(/^[0-9a-f]{64}$/)
  })

  it('日付（JST）が変われば別のハッシュになる', async () => {
    // JST の 0 時をまたぐ 1 分差。UTC 基準なら同じ日になってしまう組み合わせ。
    const a = await visitorTokenHash('203.0.113.5', UA, Date.parse('2026-07-28T14:59:00Z'))
    const b = await visitorTokenHash('203.0.113.5', UA, Date.parse('2026-07-28T15:00:00Z'))

    expect(a).not.toBe(b)
  })

  it('IP が変われば別のハッシュになり、元の IP は含まれない', async () => {
    const ts = Date.parse('2026-07-28T01:00:00Z')
    const a = await visitorTokenHash('203.0.113.5', UA, ts)
    const b = await visitorTokenHash('203.0.113.6', UA, ts)

    expect(a).not.toBe(b)
    expect(a).not.toContain('203.0.113.5')
  })
})

describe('dayKey', () => {
  it('JST の YYYY-MM-DD を返す（集計の日付バケットと同じ基準）', () => {
    expect(dayKey(Date.parse('2026-07-28T23:30:00Z'))).toBe('2026-07-29')
    expect(dayKey(Date.parse('2026-07-28T15:00:00Z'))).toBe('2026-07-29')
    expect(dayKey(Date.parse('2026-07-28T14:59:59Z'))).toBe('2026-07-28')
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
  })
})

describe('ボット判別', () => {
  // ADR 0004: 完全な UA は保存せず、UA トークン判定で種類だけを残す。
  it.each([
    ['Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)', 'bot:Googlebot'],
    ['Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)', 'bot:bingbot'],
    ['Mozilla/5.0 AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15 (Applebot/0.1; +http://www.apple.com/go/applebot)', 'bot:Applebot'],
    ['Mozilla/5.0 (compatible; GPTBot/1.2; +https://openai.com/gptbot)', 'bot:GPTBot'],
    ['Mozilla/5.0 (compatible; OAI-SearchBot/1.0; +https://openai.com/searchbot)', 'bot:OAI-SearchBot'],
    ['Mozilla/5.0 (compatible; ClaudeBot/1.0; +claudebot@anthropic.com)', 'bot:ClaudeBot'],
    ['Mozilla/5.0 (compatible; PerplexityBot/1.0; +https://perplexity.ai/perplexitybot)', 'bot:PerplexityBot'],
    ['Mozilla/5.0 (compatible; Bytespider; spider-feedback@bytedance.com)', 'bot:Bytespider'],
  ])('既知のクローラを種類別に分類する: %s', (ua, expected) => {
    expect(summarizeUA(ua)).toBe(expected)
  })

  it('Applebot-Extended を Applebot と混同しない（前者は AI 学習向けの別クローラ）', () => {
    expect(summarizeUA('Mozilla/5.0 (compatible; Applebot-Extended/0.1)')).toBe(
      'bot:Applebot-Extended',
    )
  })

  it('ブラウザ由来のトークンを含むクローラでもブラウザに分類しない', () => {
    // Googlebot の現行 UA は Chrome/ と Safari/ を含む。ブラウザ判定を先に
    // 走らせると Chrome として計上され、クローラ量が測れなくなる。
    const ua =
      'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Googlebot/2.1; +http://www.google.com/bot.html) Chrome/140.0.0.0 Safari/537.36'
    expect(summarizeUA(ua)).toBe('bot:Googlebot')
  })

  it('未知のボットは other ではなくボットと分かる値になる', () => {
    expect(summarizeUA('SomeBot/1.0')).toBe('bot:other')
    expect(summarizeUA('Mozilla/5.0 (compatible; ExampleCrawler/3.0)')).toBe('bot:other')
    expect(summarizeUA('some-random-spider/1')).toBe('bot:other')
  })

  it('通常のブラウザ・アプリはボットに分類しない', () => {
    expect(summarizeUA(UA)).toBe('Safari')
    expect(summarizeUA('befold/1.2.3 Sparkle/2.6.4')).toBe('Sparkle')
    expect(summarizeUA('curl/8.7.1')).toBe('curl')
    expect(
      summarizeUA(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
      ),
    ).toBe('Chrome')
  })

  it('isBotSummary が ua_summary の値からボットかどうかを判定する', () => {
    expect(isBotSummary('bot:GPTBot')).toBe(true)
    expect(isBotSummary('bot:other')).toBe(true)
    expect(isBotSummary('Safari')).toBe(false)
    // 分類の適用前に記録された行。ボットも人間もここに混ざっている。
    expect(isBotSummary('other')).toBe(false)
  })
})
