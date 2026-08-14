/**
 * Cloudflare Access が発行する JWT（`Cf-Access-Jwt-Assertion`）の検証。
 *
 * Access アプリケーションを張っただけでは Worker 自身は無防備なままで、
 * Access を経由しない経路（同一 Worker の別ホスト、Cloudflare 内部からの
 * 到達など）で素通しになる。保護は「Access で止める」と「Worker が JWT を
 * 確かめる」の 2 段で成り立つ（ADR 0007 の決定 5）。
 */

/** JWKS の 1 鍵。Access は RS256 の公開鍵を JWK 形式で配る。 */
type AccessJwk = JsonWebKey & { kid?: string }

/** JWKS の取得結果と、その有効期限（ミリ秒エポック）。 */
type CachedKeys = { keys: Map<string, CryptoKey>; expiresAt: number }

/**
 * 鍵の再取得間隔。Access の鍵は 6 週間ごとに回るため 1 時間で十分に追随する。
 * 未知の kid が来た場合は期限前でも取り直す（下の `keyFor` を参照）。
 */
const KEYS_TTL_MS = 60 * 60 * 1000

/** team domain ごとの鍵キャッシュ。Worker の isolate 内で共有する。 */
const keyCache = new Map<string, CachedKeys>()

/** JWT のペイロードのうち、この検証で見るクレームだけ。 */
export type AccessClaims = {
  /** 認証された利用者のメールアドレス。 */
  email?: string
  /** アプリケーションの AUD タグ（複数入りうる）。 */
  aud: string[]
  /** 発行者。team domain の URL と一致していなければならない。 */
  iss: string
  /** 有効期限・有効開始（秒エポック）。 */
  exp: number
  nbf?: number
}

/** base64url をバイト列へ戻す。 */
function decodeBase64Url(value: string): Uint8Array {
  const base64 = value.replaceAll('-', '+').replaceAll('_', '/')
  const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), '=')
  const binary = atob(padded)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes
}

/** base64url の JSON セグメントを復元する。壊れていれば undefined。 */
function decodeJsonSegment(segment: string): unknown {
  try {
    return JSON.parse(new TextDecoder().decode(decodeBase64Url(segment)))
  } catch {
    return undefined
  }
}

/** JWKS を取得して kid → CryptoKey の対応表にする。 */
async function fetchKeys(teamDomain: string): Promise<Map<string, CryptoKey>> {
  const response = await fetch(`https://${teamDomain}/cdn-cgi/access/certs`)
  if (!response.ok) throw new Error(`failed to fetch Access certs: ${response.status}`)

  const body = (await response.json()) as { keys?: AccessJwk[] }
  const keys = new Map<string, CryptoKey>()
  for (const jwk of body.keys ?? []) {
    if (jwk.kid === undefined) continue
    const key = await crypto.subtle.importKey(
      'jwk',
      jwk,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    )
    keys.set(jwk.kid, key)
  }
  return keys
}

/**
 * kid に対応する公開鍵を返す。キャッシュに無い kid は鍵の回転とみなして
 * 1 度だけ取り直す（回転直後に全リクエストが落ちるのを避けるため）。
 */
async function keyFor(teamDomain: string, kid: string, now: number): Promise<CryptoKey | undefined> {
  const cached = keyCache.get(teamDomain)
  if (cached !== undefined && cached.expiresAt > now) {
    const key = cached.keys.get(kid)
    if (key !== undefined) return key
  }

  const keys = await fetchKeys(teamDomain)
  keyCache.set(teamDomain, { keys, expiresAt: now + KEYS_TTL_MS })
  return keys.get(kid)
}

/** テスト用に鍵キャッシュを空にする。 */
export function clearAccessKeyCache(): void {
  keyCache.clear()
}

/**
 * Access JWT を検証し、通ればクレームを返す。通らなければ undefined。
 *
 * 署名（RS256）・`aud`・`iss`・`exp` / `nbf` をすべて見る。1 つでも欠けると
 * 「別のアプリケーション向けに正しく署名された JWT」が通ってしまう。
 */
export async function verifyAccessJwt(
  token: string,
  options: { teamDomain: string; aud: string; now?: number },
): Promise<AccessClaims | undefined> {
  const nowSeconds = Math.floor((options.now ?? Date.now()) / 1000)
  const [headerSegment, payloadSegment, signatureSegment] = token.split('.')
  if (headerSegment === undefined || payloadSegment === undefined || signatureSegment === undefined) {
    return undefined
  }

  const header = decodeJsonSegment(headerSegment) as { alg?: string; kid?: string } | undefined
  if (header?.alg !== 'RS256' || header.kid === undefined) return undefined

  const key = await keyFor(options.teamDomain, header.kid, options.now ?? Date.now())
  if (key === undefined) return undefined

  const signed = new TextEncoder().encode(`${headerSegment}.${payloadSegment}`)
  const signature = decodeBase64Url(signatureSegment)
  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, signature, signed)
  if (!valid) return undefined

  const payload = decodeJsonSegment(payloadSegment) as Partial<AccessClaims> | undefined
  if (payload === undefined || typeof payload.exp !== 'number') return undefined

  const rawAudience: unknown = payload.aud
  const audience = (Array.isArray(rawAudience) ? rawAudience : [rawAudience]).filter(
    (value): value is string => typeof value === 'string',
  )
  if (!audience.includes(options.aud)) return undefined
  if (payload.iss !== `https://${options.teamDomain}`) return undefined
  if (payload.exp <= nowSeconds) return undefined
  if (typeof payload.nbf === 'number' && payload.nbf > nowSeconds) return undefined

  return { email: payload.email, aud: audience, iss: payload.iss, exp: payload.exp, nbf: payload.nbf }
}
