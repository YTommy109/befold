/** 日次ユニーク推定と UA 要約。生 IP・完全 UA は一切保持しない。 */

import { jstDayKey } from './jst'

/**
 * Unix epoch (ms) を JST の YYYY-MM-DD に変換する。
 *
 * 集計側の日付バケット（lib/jst.ts の JST_DAY_EXPR）と同じ基準にそろえる。
 * TASK-359.1 で UTC から JST へ変更した。この切り替えを境に同一訪問者の
 * visitor_day ハッシュが変わるため、切り替え日をまたぐ日次ユニークは
 * 過去データと連続しない（遡及再計算はしない）。
 */
export function dayKey(ts: number): string {
  return jstDayKey(ts)
}

/**
 * sha256(ip + ua + YYYY-MM-DD) を 16 進文字列で返す。
 * 同一日・同一訪問者なら決定的に同じ値になり、IP は復元できない。
 */
export async function visitorDayHash(ip: string, ua: string, ts: number): Promise<string> {
  const source = `${ip}\0${ua}\0${dayKey(ts)}`
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(source))
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

/** UA から OS 種別（と macOS のメジャーバージョン）だけを粗く抜き出す。 */
export function summarizeOS(ua: string): string | null {
  const mac = /Mac OS X (\d+)[._](\d+)/.exec(ua)
  if (mac) return `macOS ${mac[1] ?? '0'}.${mac[2] ?? '0'}`
  if (ua.includes('Macintosh') || ua.includes('Darwin')) return 'macOS'
  if (ua.includes('Windows')) return 'Windows'
  if (ua.includes('Android')) return 'Android'
  if (/iPhone|iPad|iPod/.test(ua)) return 'iOS'
  if (ua.includes('Linux')) return 'Linux'
  return null
}

/** UA からクライアント種別だけを粗く抜き出す（バージョンや詳細は保持しない）。 */
export function summarizeUA(ua: string): string | null {
  if (ua.length === 0) return null
  if (ua.includes('Sparkle')) return 'Sparkle'
  if (ua.includes('Edg/')) return 'Edge'
  if (ua.includes('Firefox/')) return 'Firefox'
  if (ua.includes('Chrome/')) return 'Chrome'
  if (ua.includes('Safari/')) return 'Safari'
  if (ua.includes('curl/')) return 'curl'
  return 'other'
}
