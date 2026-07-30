import { describe, expect, it } from 'vitest'
import { REFERRER_MAX_LENGTH, resolveReferrer } from '../src/lib/referrer'

const SELF = 'befold.tommy109.workers.dev'

describe('resolveReferrer', () => {
  it('?ref= があればそれを参照元として採用する', () => {
    expect(resolveReferrer('gh-pages', null, SELF)).toBe('gh-pages')
  })

  it('?ref= は Referer より優先される', () => {
    expect(resolveReferrer('gh-pages', 'https://news.ycombinator.com/item?id=1', SELF)).toBe(
      'gh-pages',
    )
  })

  it('?ref= の前後空白を落とし、空文字は参照元なしとして扱う', () => {
    expect(resolveReferrer('  gh-pages  ', null, SELF)).toBe('gh-pages')
    expect(resolveReferrer('   ', null, SELF)).toBeNull()
  })

  it('?ref= が長すぎる場合は上限で切り詰める', () => {
    const resolved = resolveReferrer('x'.repeat(REFERRER_MAX_LENGTH + 50), null, SELF)

    expect(resolved).toHaveLength(REFERRER_MAX_LENGTH)
  })

  it('?ref= が無ければ Referer のオリジンだけを採用しフルパスは捨てる', () => {
    const resolved = resolveReferrer(null, 'https://news.ycombinator.com/item?id=123', SELF)

    expect(resolved).toBe('https://news.ycombinator.com')
    expect(resolved).not.toContain('item')
    expect(resolved).not.toContain('123')
  })

  it('Referer のポートは保持する', () => {
    expect(resolveReferrer(null, 'http://localhost:3000/a/b', SELF)).toBe('http://localhost:3000')
  })

  it('自サイト内の遷移は参照元として記録しない', () => {
    expect(resolveReferrer(null, `https://${SELF}/`, SELF)).toBeNull()
  })

  it('URL として解釈できない Referer は参照元なしとして扱う', () => {
    expect(resolveReferrer(null, 'not a url', SELF)).toBeNull()
  })

  it('?ref= も Referer も無い直接アクセスは参照元なしになる', () => {
    expect(resolveReferrer(null, null, SELF)).toBeNull()
  })
})
