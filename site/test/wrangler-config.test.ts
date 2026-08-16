import { env } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'

/**
 * 公開面の設定を、デプロイ結果ではなく設定ファイルの形で固定する。
 *
 * routes（Custom Domain）を書くと `workers_dev` は次回デプロイで false と
 * 推論される仕様がある（Cloudflare「workers.dev」）。旧ホストが落ちると、
 * 出荷済みアプリに焼き込まれた Sparkle フィード URL と配信済み appcast の
 * enclosure が 404 になり、更新経路が止まる（ADR 0007 の決定 1）。
 * 「明示的に書き続ける」は文章だけでは守られないため、消したら落ちるものを
 * 置く。
 */
describe('wrangler.toml の公開面', () => {
  const toml = env.TEST_WRANGLER_TOML

  /** `[env.staging]` 以降を staging 側、それより前を本番側として切り出す。 */
  const stagingIndex = toml.indexOf('[env.staging]')
  const production = toml.slice(0, stagingIndex)
  const staging = toml.slice(stagingIndex)

  it('staging セクションが存在する', () => {
    expect(stagingIndex).toBeGreaterThan(0)
  })

  it('本番・staging とも workers_dev = true を明示している', () => {
    expect(production).toMatch(/^workers_dev = true$/mu)
    expect(staging).toMatch(/^workers_dev = true$/mu)
  })

  it('本番の Custom Domain が befold.degino.com である', () => {
    expect(production).toContain('pattern = "befold.degino.com"')
    expect(production).toContain('custom_domain = true')
  })

  it('staging の Custom Domain が staging.befold.degino.com である', () => {
    expect(staging).toContain('pattern = "staging.befold.degino.com"')
    expect(staging).toContain('custom_domain = true')
  })

  /**
   * ダッシュボードの保護は Access の設定と Worker 側の JWT 検証の 2 段で成り立つ
   * （ADR 0007 の決定 5）。検証に要る値が設定ファイルから消えると、Worker は 503 で
   * 閉じる——つまり気づけはするが、気づくのがデプロイ後になる。宣言そのものを固定する。
   */
  it('本番・staging とも Access の検証に使う変数を宣言している', () => {
    for (const section of [production, staging]) {
      expect(section).toMatch(/^ACCESS_TEAM_DOMAIN = /mu)
      expect(section).toMatch(/^ACCESS_AUD = /mu)
    }
  })
})
