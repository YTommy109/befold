import { describe, expect, it } from 'vitest'

import {
  CANONICAL_HOST,
  LEGACY_HOST,
  LEGACY_STAGING_HOST,
  SELF_HOSTS,
  STAGING_HOST,
  selfHostsFor,
} from '../src/lib/hosts'
import { REFERRER_MAX_LENGTH, resolveReferrer } from '../src/lib/referrer'

const SELF = selfHostsFor(CANONICAL_HOST)

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
    expect(resolveReferrer(null, `https://${CANONICAL_HOST}/`, SELF)).toBeNull()
  })

  it('URL として解釈できない Referer は参照元なしとして扱う', () => {
    expect(resolveReferrer(null, 'not a url', SELF)).toBeNull()
  })

  it('?ref= も Referer も無い直接アクセスは参照元なしになる', () => {
    expect(resolveReferrer(null, null, SELF)).toBeNull()
  })
})

/**
 * 独自ドメイン移行で自己ホストが 1 つから 4 つに増えた（ADR 0007 の決定 1・4・6）。
 * 単一ホスト前提のままだと、旧ホスト → 新ドメインの遷移が外部参照元として D1 に
 * 記録され、参照元の集計に移行期の断層が残る。
 */
describe('自己ホスト集合', () => {
  const HOSTS = [CANONICAL_HOST, LEGACY_HOST, STAGING_HOST, LEGACY_STAGING_HOST]

  it('本番・staging の新旧 4 ホストを含む', () => {
    expect([...SELF_HOSTS].sort()).toEqual([...HOSTS].sort())
  })

  it.each(
    HOSTS.flatMap((from) => HOSTS.filter((to) => to !== from).map((to) => [from, to] as const)),
  )('%s から %s への遷移は参照元として記録しない', (from, to) => {
    expect(resolveReferrer(null, `https://${from}/`, selfHostsFor(to))).toBeNull()
  })

  it('既知でないホストで配信されていても、そのホスト内の遷移は参照元にしない', () => {
    // wrangler dev / preview URL のように SELF_HOSTS に無いホストで配信される場合。
    expect(
      resolveReferrer(null, 'http://localhost:8787/features', selfHostsFor('localhost:8787')),
    ).toBeNull()
  })

  it('自己ホスト以外からの流入は従来どおり参照元として記録する', () => {
    expect(
      resolveReferrer(null, 'https://news.ycombinator.com/', selfHostsFor(CANONICAL_HOST)),
    ).toBe('https://news.ycombinator.com')
  })
})
