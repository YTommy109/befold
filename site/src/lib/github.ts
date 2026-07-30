/** GitHub Releases 上の DMG / appcast の所在解決。 */

const REPO = 'YTommy109/befold'

export const RELEASES_LATEST_URL = `https://github.com/${REPO}/releases/latest`

const LATEST_RELEASE_API = `https://api.github.com/repos/${REPO}/releases/latest`

/** Sparkle が参照する appcast（GitHub 上の固定タグ）。Worker はこれをプロキシする。 */
export const APPCAST_UPSTREAM = {
  stable: `https://github.com/${REPO}/releases/download/appcast/appcast.xml`,
  develop: `https://github.com/${REPO}/releases/download/appcast/appcast-develop.xml`,
} as const

export type Channel = keyof typeof APPCAST_UPSTREAM

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
