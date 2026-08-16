/**
 * R2 上のリリース成果物（DMG / appcast）の所在解決。
 *
 * リリースワークフローが署名・公証済みの成果物を R2 へ配置し、Worker が
 * そこから配信する。GitHub Releases にも同じものを置き続けるが、それは
 * 移行期の後方互換とロールバック用であって、正はあくまで R2 側。
 */

import { z } from 'zod'

/**
 * リリースタグの形。`v` + semver（+ dev プレリリース）だけを受け付ける。
 *
 * R2 のキーはこの検証を通った値からのみ組み立てる。リクエストのパスを
 * そのまま連結すると、バケット内の任意のオブジェクト（latest.json など
 * 配信対象でないもの）が読み出せてしまう。
 */
const tagSchema = z.string().regex(/^v\d+\.\d+\.\d+(-dev\.\d+)?$/u)

/** R2 のキー接頭辞。成果物以外を同じバケットへ置く場合の衝突も避ける。 */
const RELEASES_PREFIX = 'releases'

/** stable の最新バージョンを指すポインタ。prerelease では更新しない。 */
export const LATEST_KEY = `${RELEASES_PREFIX}/latest.json`

/** appcast の R2 キー。チャンネルごとに 1 つ。 */
export const APPCAST_KEY = {
  stable: 'appcast.xml',
  develop: 'appcast-develop.xml',
} as const

/** latest.json の中身。リリースワークフローが書き込む。 */
export const latestPointerSchema = z.object({
  version: tagSchema,
  file: z.string(),
})

export type LatestPointer = z.infer<typeof latestPointerSchema>

/**
 * `/dl/:tag/:file` のパスから R2 キーを解決する。
 *
 * タグの形と、ファイル名がそのタグの DMG であることの両方を検証する。
 * どちらかが合わなければ null を返し、呼び出し側は R2 を触らずに
 * GitHub Releases へフォールバックする。
 */
export function resolveDMGKey(tag: string, file: string): string | null {
  const parsedTag = tagSchema.safeParse(tag)
  if (!parsedTag.success) return null
  if (file !== dmgFileName(parsedTag.data)) return null

  return `${RELEASES_PREFIX}/${parsedTag.data}/${file}`
}

/** リリースタグに対応する DMG のファイル名。release.yml の DMG_NAME と対になる。 */
export function dmgFileName(tag: string): string {
  return `befold-${tag}.dmg`
}

/** 与えられたタグが prerelease（dev チャンネル）かどうか。 */
export function isPrerelease(tag: string): boolean {
  return tag.includes('-')
}
