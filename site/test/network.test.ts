import { describe, expect, it } from 'vitest'

import { DATACENTER_ORG_PATTERNS, datacenterOrgMatch, isDatacenterOrg } from '../src/lib/network'

describe('接続元組織によるデータセンター判定', () => {
  it('クラウド・ホスティング・スキャン業者を自動アクセスとして分類する', () => {
    // いずれも本番で「人間の訪問」として計上されていた実在の組織名（TASK-490）。
    for (const org of [
      'Amazon Data Services Northern Virginia',
      'Amazon Technologies Inc.',
      'Amazon.com, Inc.',
      'Meta Platforms Ireland Limited',
      'Google LLC',
      'Twitter Inc.',
      'DigitalOcean, LLC',
      'Driftnet Ltd',
      'SAKURA Internet Inc.',
      'Hetzner Online GmbH',
      'OVH SAS',
      'Contabo GmbH',
      'Censys, Inc.',
      'FR ONYPHE',
      'HostRoyale Technologies Pvt Ltd',
    ]) {
      expect(isDatacenterOrg(org), org).toBe(true)
    }
  })

  it('消費者向け ISP を自動アクセスに含めない', () => {
    // 人間を落とす向きの間違いのほうが高くつく（ADR 0007 の停止判断に使うため）。
    for (const org of [
      'ARTERIA Networks Corp.',
      'KDDI CORPORATION',
      'So-net Service',
      'IIJ Internet',
      'BIGLOBE Inc.',
      'NTT DOCOMO,INC.',
      'SoftBank Corp.',
      'J:COM WEST Co., Ltd.',
      'Rakuten Mobile Network, Inc.',
      'OPTAGE Inc.',
    ]) {
      expect(isDatacenterOrg(org), org).toBe(false)
    }
  })

  it('プライバシー中継・VPN・Tor の出口を自動アクセスに含めない', () => {
    // iCloud Private Relay と WARP の出口はこれらの組織名で出る。人間の可能性が
    // あるので落とさない（実測: 本番に Cloudflare London, LLC + Chrome + JP が 1 件）。
    for (const org of [
      'Cloudflare London, LLC',
      'Akamai Technologies, Inc.',
      'Fastly, Inc.',
      'TOR EXIT AND MORE',
      'UAB code200',
    ]) {
      expect(isDatacenterOrg(org), org).toBe(false)
    }
  })

  it('接続元が分からない行は自動アクセスにしない', () => {
    // NULL は「データセンターでない」ではなく「不明」。不明を自動アクセスへ
    // 寄せると人間を落とす向きの間違いになる。
    expect(isDatacenterOrg(null)).toBe(false)
  })

  it('SQL 断片は NULL を人間側に落とす形で組み立てる', () => {
    // COALESCE を外すと NULL LIKE ... が NULL を返し、その行が人間でも
    // データセンターでもなく黙って全集計から消える（BOT_MATCH と同じ事故）。
    const sql = datacenterOrgMatch()
    expect(sql.match(/COALESCE\(as_org, ''\) LIKE '%/gu)).toHaveLength(
      DATACENTER_ORG_PATTERNS.length,
    )
    expect(datacenterOrgMatch('e.as_org')).toContain("COALESCE(e.as_org, '')")
  })
})
