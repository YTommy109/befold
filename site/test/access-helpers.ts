import { vi } from 'vitest'

import { clearAccessKeyCache } from '../src/lib/access'

/** テストで使う Access の team domain と AUD（vitest.config.ts のバインディングと同じ値）。 */
export const TEST_TEAM_DOMAIN = 'test-team.cloudflareaccess.com'
export const TEST_AUD = 'test-aud'

const CERTS_URL = `https://${TEST_TEAM_DOMAIN}/cdn-cgi/access/certs`

function toBase64Url(bytes: Uint8Array): string {
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
}

function encodeSegment(value: unknown): string {
  return toBase64Url(new TextEncoder().encode(JSON.stringify(value)))
}

/**
 * Access の鍵配布（JWKS）を差し替え、その鍵で JWT を署名できるようにする。
 *
 * 実際の Access と同じく RS256 の鍵ペアを作り、`/cdn-cgi/access/certs` への
 * fetch だけを横取りする。署名検証を素通しにするのではなく本物の署名を通すため、
 * 「署名が違えば落ちる」ことまでテストで確かめられる。
 */
export async function installAccessKeys(kid = 'test-kid'): Promise<{
  sign: (claims: Record<string, unknown>) => Promise<string>
  headers: () => Promise<Record<string, string>>
}> {
  clearAccessKeyCache()

  const pair = (await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify'],
  )) as CryptoKeyPair
  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey)
  const jwks = JSON.stringify({ keys: [{ ...jwk, kid, alg: 'RS256', use: 'sig' }] })

  const realFetch = globalThis.fetch
  vi.stubGlobal('fetch', async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
    if (url === CERTS_URL) {
      return new Response(jwks, { headers: { 'Content-Type': 'application/json' } })
    }
    return await realFetch(input as RequestInfo, init)
  })

  async function sign(claims: Record<string, unknown>): Promise<string> {
    const nowSeconds = Math.floor(Date.now() / 1000)
    const payload = {
      iss: `https://${TEST_TEAM_DOMAIN}`,
      aud: [TEST_AUD],
      email: 'tokutomi@degino.com',
      exp: nowSeconds + 3600,
      iat: nowSeconds,
      ...claims,
    }
    const signingInput = `${encodeSegment({ alg: 'RS256', kid, typ: 'JWT' })}.${encodeSegment(payload)}`
    const signature = await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      pair.privateKey,
      new TextEncoder().encode(signingInput),
    )
    return `${signingInput}.${toBase64Url(new Uint8Array(signature))}`
  }

  return {
    sign,
    headers: async () => ({ 'Cf-Access-Jwt-Assertion': await sign({}) }),
  }
}

/** 鍵の差し替えとキャッシュを元に戻す。 */
export function removeAccessKeys(): void {
  vi.unstubAllGlobals()
  clearAccessKeyCache()
}
