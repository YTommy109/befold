/**
 * 接続元組織（`events.as_org` = `request.cf.asOrganization`）による自動アクセスの判別。
 *
 * User-Agent によるボット判別（`lib/visitor.ts`、ADR 0004）とは**別の軸**で、
 * 「UA はふつうのブラウザだが、接続元がデータセンターである」アクセスを分ける。
 * 判定の理由と、この軸を足した経緯は ADR 0008。
 *
 * **判定は集計時に行う（記録時ではない）。** `as_org` は 2026-07-30 の列追加以降
 * すべての行に記録されているため、集計時に判定すれば**過去データにも遡って効く**。
 * UA 分類が遡れなかった（完全な UA を保存していない）のと非対称で、これが
 * この軸を選んだ決め手。
 */

/**
 * データセンター・ホスティング・スキャナの接続元組織名（部分一致、大小同一視）。
 *
 * SQLite の LIKE は ASCII について大小を区別しないため、パターンは見た目どおりに
 * 書いてよい。**ワイルドカード（`%` `_`）と引用符（`'`）を含めないこと**——
 * SQL へそのまま埋めるため、意図しない一致になる。`network.test.ts` が検査する。
 *
 * ここに**入れてはならない**もの:
 *
 * - **プライバシー中継の出口**（Cloudflare / Akamai / Fastly）。iCloud Private Relay
 *   と WARP はこれらの組織名で出るため、入れると人間の訪問を落とす（実測: 本番に
 *   `Cloudflare London, LLC` + Chrome + macOS + JP が 1 件）。
 * - **VPN・Tor の出口**（`TOR EXIT AND MORE`、`UAB code200` 等）。自動アクセスとは
 *   限らず、プライバシーを気にする人間の可能性がある。
 * - **消費者向け ISP**。日本の ARTERIA / KDDI / So-net / IIJ / BIGLOBE / NTT 系などは
 *   法人向けホスティングも兼ねるが、人間の訪問が主なので入れない。
 *
 * 誤って人間を落とす向きの間違いのほうが高くつく。この計測は「旧ホストと GitHub
 * 経路を止めてよいか」（ADR 0007）の判断材料に使うため、人間を少なく見積もると
 * まだ使われている経路を止めてしまう。迷ったら入れない。
 */
export const DATACENTER_ORG_PATTERNS: string[] = [
  // 大手クラウド。LP へのリンク展開・スキャン・自動巡回の主要な出どころ。
  'Amazon',
  'Google LLC',
  'Google Cloud',
  'Microsoft Corporation',
  'Oracle Corporation',
  'Alibaba',
  'Tencent',
  'Huawei Cloud',
  'DigitalOcean',
  'Linode',
  'Hetzner',
  'OVH',
  'Contabo',
  'Vultr',
  'The Constant Company',
  'Scaleway',
  'Leaseweb',
  'IONOS',
  'Choopa',
  'Hostwinds',
  'SAKURA Internet',
  // SNS のリンク展開。UA を名乗らないものが `other` として人間側に入っていた。
  'Meta Platforms',
  'Facebook',
  'Twitter',
  'X Corp',
  'ByteDance',
  // インターネット全域スキャン業者。
  'Driftnet',
  'Censys',
  'ONYPHE',
  'Shodan',
  'Internet Measurement',
  'Palo Alto Networks',
  'Recyber',
  'Stretchoid',
  // 個別のホスティング事業者（実データに現れたもの）。
  'HostRoyale',
  'EGIHosting',
  'MEVSPACE',
  'ReliableSite',
  'Web2Objects',
  'Virtualine',
  'Subnet Digital',
  'MOD Mission Critical',
  'DEDIK SERVICES',
  'BESTDC',
  // 事業者名を知らなくても拾える一般語。上の列挙が追いつかないぶんを受ける。
  'Hosting',
  'Datacenter',
  'Data Center',
  'Colocation',
]

/**
 * 接続元組織がデータセンターかを判定する SQL 断片を作る。
 *
 * **`COALESCE` を外さないこと。** `as_org` は NULL 許容で、`NULL LIKE ...` は
 * NULL を返す。素の LIKE を WHERE に置くと、`request.cf` が無い経路で記録された行
 * （ローカル・テストなど）が人間でもデータセンターでもなく黙って全集計から消える。
 * `BOT_MATCH`（`analytics.ts`）が同じ理由で COALESCE を持っている。
 *
 * 判定できない（as_org が NULL の）行は人間側に残す。NULL は「データセンターでは
 * ない」ではなく「不明」だが、不明を自動アクセスへ寄せると人間を落とす向きの
 * 間違いになるため。
 *
 * SQL 断片は必ずこの関数から作る。手書きの LIKE 列を置くと、パターンを足したときに
 * 片方だけ直る（`analytics.test.ts` の集約テストが検査する）。
 */
export function datacenterOrgMatch(column = 'as_org'): string {
  const terms = DATACENTER_ORG_PATTERNS.map(
    (pattern) => `COALESCE(${column}, '') LIKE '%${pattern}%'`,
  )
  return `(${terms.join(' OR ')})`
}

/**
 * 接続元組織名がデータセンターかを返す（TS 側の判定）。
 *
 * 集計は SQL 断片のほうを使う。こちらは同じ配列から導いた確認用で、パターンの
 * 追加漏れを検知するテストのためにある（判定の定義元は配列ひとつ）。
 */
export function isDatacenterOrg(asOrg: string | null): boolean {
  if (asOrg === null) return false
  const lower = asOrg.toLowerCase()
  return DATACENTER_ORG_PATTERNS.some((pattern) => lower.includes(pattern.toLowerCase()))
}
