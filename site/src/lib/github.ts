/** GitHub Releases 上の DMG / appcast の所在解決。 */

const REPO = 'YTommy109/befold'

export const RELEASES_LATEST_URL = `https://github.com/${REPO}/releases/latest`

const LATEST_RELEASE_API = `https://api.github.com/repos/${REPO}/releases/latest`

/**
 * 配布チャネルの列挙。**これが唯一の定義元。**
 *
 * `schema.ts` の channel 列も、ダッシュボードのチャネル別系列も、ここから導く。
 * 別々に書き写すと、チャネルを増やしたときに記録側だけが増えて集計側の系列が
 * 増えず、新チャネルの数字が画面のどこにも出ないまま黙って落ちる。
 * 実行時に配列が要るので型ではなく値で持つ（`Record<Channel, ...>` の網羅は
 * 型で検査される）。
 */
export const CHANNELS = ['stable', 'develop'] as const

export type Channel = (typeof CHANNELS)[number]

/** Sparkle が参照する appcast（GitHub 上の固定タグ）。Worker はこれをプロキシする。 */
export const APPCAST_UPSTREAM: Record<Channel, string> = {
  stable: `https://github.com/${REPO}/releases/download/appcast/appcast.xml`,
  develop: `https://github.com/${REPO}/releases/download/appcast/appcast-develop.xml`,
}

/**
 * GitHub Releases 上の成果物 URL。R2 に目的のオブジェクトが無いときの
 * フォールバック先で、移行期の後方互換のために残している。
 *
 * ここで 404 を返さず GitHub へ送るのは Sparkle のため。Sparkle は
 * enclosure の 404 をアップデート失敗として扱うので、R2 への配置が
 * 間に合っていない過去バージョンでも更新経路を切らさないようにする。
 */
export function releaseAssetURL(tag: string, file: string): string {
  return `https://github.com/${REPO}/releases/download/${tag}/${file}`
}

/**
 * 一覧が 1 回の応答で覆えるリリース数。GitHub API の per_page 上限がそのまま
 * 天井になる。ページングはしない——実測で stable は 47 件（2026-08-16）であり、
 * 天井に当たるのは当分先。当たった場合に古い版が黙って消えないよう、ページ側は
 * 常に GitHub のリリース一覧への導線を出す。
 */
export const RELEASES_PAGE_LIMIT = 100

/** リリース一覧の取得元。stable も develop も 1 回の応答に混ざって返る。 */
const RELEASES_API = `https://api.github.com/repos/${REPO}/releases?per_page=${RELEASES_PAGE_LIMIT}`

/** 一覧に出す 1 つの stable リリース。 */
export type StableRelease = {
  /** `v1.13.2` の形。ダウンロード経路の R2 キーにもなる。 */
  tag: string
  /** 公開日時（ISO 8601）。表示は各言語で整形する。 */
  publishedAt: string
  /** リリースノート（GitHub のタグページ）。 */
  notesUrl: string
  /** DMG のファイル名。旧版は `mmdview-v1.3.3.dmg` のように現在の規約と違う。 */
  dmgFile: string
}

/**
 * stable リリースだけを新しい順に返す。
 *
 * 除外するのは 3 種類。(a) prerelease（develop チャンネル）、(b) `appcast` の
 * ような版を表さないタグ、(c) DMG が添付されていないリリース。(b) は実在する
 * ——appcast の配布用に prerelease=false の固定タグが 1 つある（実測）ので、
 * prerelease フラグだけでは弾けない。
 *
 * **取得に失敗したときは null を返す。** 空配列（＝ stable が 1 件も無い）と
 * 区別できないと、API 障害を「まだリリースがありません」と表示してしまう。
 */
export async function stableReleases(): Promise<StableRelease[] | null> {
  const response = await fetch(RELEASES_API, {
    headers: { 'User-Agent': 'befold-site', Accept: 'application/vnd.github+json' },
    // 人間が見るページからしか呼ばれないが、未認証の GitHub API は IP あたり
    // 60 req/h で、Worker の送信元は他所と共有される。エッジで畳んでおかないと
    // 一覧が縮退表示に落ちる。
    cf: { cacheTtl: 600, cacheEverything: true },
  }).catch(() => null)

  if (response === null || !response.ok) return null

  const releases = (await response.json().catch(() => null)) as unknown
  if (!Array.isArray(releases)) return null

  return releases.flatMap((release) => {
    const entry = toStableRelease(release)
    return entry === null ? [] : [entry]
  })
}

/** 版を表す stable タグの形。`appcast` のような版でないタグを弾く。 */
const STABLE_TAG_PATTERN = /^v\d+\.\d+\.\d+$/u

function toStableRelease(release: unknown): StableRelease | null {
  if (typeof release !== 'object' || release === null) return null

  const {
    tag_name: tag,
    published_at: publishedAt,
    prerelease,
    assets,
  } = release as Record<string, unknown>
  if (prerelease === true) return null
  if (typeof tag !== 'string' || !STABLE_TAG_PATTERN.test(tag)) return null
  if (typeof publishedAt !== 'string') return null
  if (!Array.isArray(assets)) return null

  const dmg = assets.find(
    (asset): asset is { name: string } =>
      typeof asset === 'object' &&
      asset !== null &&
      typeof (asset as { name?: unknown }).name === 'string' &&
      (asset as { name: string }).name.endsWith('.dmg'),
  )
  if (dmg === undefined) return null

  return {
    tag,
    publishedAt,
    notesUrl: `https://github.com/${REPO}/releases/tag/${tag}`,
    dmgFile: dmg.name,
  }
}

/** 過去のリリースをすべて並べた GitHub のページ。一覧の天井を逃がす先。 */
export const RELEASES_INDEX_URL = `https://github.com/${REPO}/releases`

export type DMGAsset = { version: string; url: string }

type LatestRelease = {
  tag_name?: unknown
  assets?: unknown
}

/**
 * 最新リリースの DMG アセットを解決する。
 * GitHub API 障害や DMG 未添付のときは null を返し、呼び出し側でフォールバックする。
 */
export async function latestDMG(): Promise<DMGAsset | null> {
  const response = await fetch(LATEST_RELEASE_API, {
    headers: { 'User-Agent': 'befold-site', Accept: 'application/vnd.github+json' },
    cf: { cacheTtl: 300, cacheEverything: true },
  }).catch(() => null)

  if (response === null || !response.ok) return null

  const release = (await response.json().catch(() => null)) as LatestRelease | null
  if (release === null || !Array.isArray(release.assets)) return null

  const dmg = release.assets.find(
    (asset): asset is { name: string; browser_download_url: string } =>
      typeof asset === 'object' &&
      asset !== null &&
      typeof (asset as { name?: unknown }).name === 'string' &&
      (asset as { name: string }).name.endsWith('.dmg') &&
      typeof (asset as { browser_download_url?: unknown }).browser_download_url === 'string',
  )
  if (dmg === undefined) return null

  const tag = typeof release.tag_name === 'string' ? release.tag_name : null
  return { version: tag ?? dmg.name, url: dmg.browser_download_url }
}
