/** 参照元の解決。Referer はオリジンのみを保持し、フルパスは保存しない。 */

/** 参照元として保存する文字列の最大長。集計軸が異常値で膨らむのを防ぐ。 */
export const REFERRER_MAX_LENGTH = 64

/**
 * リクエストから参照元を決める。
 *
 * `?ref=` を最優先で採用する。GitHub Pages は静的ホスティングのため
 * サーバーサイドリダイレクトができず meta refresh / JS になり、ブラウザ既定の
 * Referrer-Policy と実装差で Referer は取りこぼしが出る。明示パラメータなら
 * その影響を受けずに数えられる。
 *
 * `?ref=` が無い場合は Referer のオリジンだけを採用する。フルパスは
 * 参照元ページの内容が漏れうるため保存しない（IP をハッシュ化し UA を
 * 要約のみ保存する既存方針に合わせる）。自サイト内の遷移は参照元ではない
 * ので null にする。
 *
 * `selfHosts` は単一のホスト名ではなく**集合**を受け取る。配布サイトは独自
 * ドメインと workers.dev の両方で応答するため（ADR 0007 の決定 1）、単一ホスト
 * 前提のままだと新旧ホスト間の遷移が外部参照元として記録される。集合を要求する
 * ことで、リクエストホスト 1 つを渡す旧実装は型エラーになり戻せない
 * （`string` は `ReadonlySet<string>` に代入できない）。集合の作り方は
 * `src/lib/hosts.ts` の `selfHostsFor` が唯一の入口。
 */
export function resolveReferrer(
  refParam: string | null,
  refererHeader: string | null,
  selfHosts: ReadonlySet<string>,
): string | null {
  const explicit = refParam?.trim()
  if (explicit !== undefined && explicit.length > 0) {
    return explicit.slice(0, REFERRER_MAX_LENGTH)
  }

  if (refererHeader === null) return null

  let origin: string
  let host: string
  try {
    const url = new URL(refererHeader)
    origin = url.origin
    host = url.host
  } catch {
    return null
  }

  if (selfHosts.has(host)) return null

  return origin.slice(0, REFERRER_MAX_LENGTH)
}
