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
 * sha256(ip + ua + YYYY-MM-DD) を 16 進文字列で返す（events.visitor_token）。
 *
 * 同一日・同一訪問者なら決定的に同じ値になり、IP は復元できない。日付を材料に
 * 混ぜているため翌日には別の値になり、日をまたぐ同一人物の追跡はできない。
 * この性質が目的なので、ハッシュから日付だけを取り出す用途には使えない。
 */
export async function visitorTokenHash(ip: string, ua: string, ts: number): Promise<string> {
  const source = `${ip}\0${ua}\0${dayKey(ts)}`
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(source))
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

/** UA から OS 種別（と macOS のメジャーバージョン）だけを粗く抜き出す。 */
export function summarizeOS(ua: string): string | null {
  const mac = /Mac OS X (\d+)[._](\d+)/u.exec(ua)
  if (mac) return `macOS ${mac[1] ?? '0'}.${mac[2] ?? '0'}`
  if (ua.includes('Macintosh') || ua.includes('Darwin')) return 'macOS'
  if (ua.includes('Windows')) return 'Windows'
  if (ua.includes('Android')) return 'Android'
  if (/iPhone|iPad|iPod/u.test(ua)) return 'iOS'
  if (ua.includes('Linux')) return 'Linux'
  return null
}

/**
 * ボットとして分類した ua_summary に付ける接頭辞。
 *
 * 集計側（analytics.ts）は既知のボット名を列挙せず `LIKE 'bot:%'` だけで
 * 人間の訪問と分離する。トークンを増やしても集計側の同期漏れが起きない。
 */
export const BOT_PREFIX = 'bot:'

/** 既知トークンに当たらないボット様 UA の行き先。ここが増えるなら分類漏れ。 */
export const BOT_OTHER = `${BOT_PREFIX}other`

/**
 * 既知クローラの UA トークンと分類名（ADR 0004）。
 *
 * 上から順に部分一致で評価するため、長いトークンを先に置く
 * （`Applebot-Extended` は `Applebot` より前でなければ後者に吸われる）。
 * 比較は小文字化した UA に対して行うので、トークンも小文字で持つ。
 */
const BOT_TOKENS: { token: string; label: string }[] = [
  // AI クローラ（学習・検索・ユーザ起点の取得）。この計測の主目的。
  { token: 'applebot-extended', label: 'Applebot-Extended' },
  { token: 'google-extended', label: 'Google-Extended' },
  { token: 'oai-searchbot', label: 'OAI-SearchBot' },
  { token: 'chatgpt-user', label: 'ChatGPT-User' },
  { token: 'gptbot', label: 'GPTBot' },
  { token: 'claude-searchbot', label: 'Claude-SearchBot' },
  { token: 'claude-user', label: 'Claude-User' },
  { token: 'claudebot', label: 'ClaudeBot' },
  { token: 'anthropic-ai', label: 'anthropic-ai' },
  { token: 'perplexity-user', label: 'Perplexity-User' },
  { token: 'perplexitybot', label: 'PerplexityBot' },
  { token: 'meta-externalagent', label: 'Meta-ExternalAgent' },
  { token: 'bytespider', label: 'Bytespider' },
  { token: 'amazonbot', label: 'Amazonbot' },
  { token: 'ccbot', label: 'CCBot' },
  { token: 'cohere-ai', label: 'cohere-ai' },
  { token: 'youbot', label: 'YouBot' },
  { token: 'diffbot', label: 'Diffbot' },
  // 検索クローラ。AI クローラと分けて読めるよう種類別に残す。
  { token: 'googlebot', label: 'Googlebot' },
  { token: 'bingbot', label: 'bingbot' },
  { token: 'duckduckbot', label: 'DuckDuckBot' },
  { token: 'yandexbot', label: 'YandexBot' },
  { token: 'baiduspider', label: 'Baiduspider' },
  { token: 'applebot', label: 'Applebot' },
  // SNS のリンク展開。人間の閲覧ではないのでボット側に寄せる。
  { token: 'facebookexternalhit', label: 'facebookexternalhit' },
  { token: 'twitterbot', label: 'Twitterbot' },
  { token: 'slackbot', label: 'Slackbot' },
  { token: 'discordbot', label: 'Discordbot' },
]

/** 既知トークンに当たらなくてもボットと判断する一般的な語。 */
const GENERIC_BOT_PATTERN = /bot\b|bot\/|crawler|crawling|spider|scraper|slurp|feedfetcher/u

/**
 * UA がボットなら分類名を、そうでなければ null を返す。
 *
 * ブラウザ判定より先に評価する必要がある。現行の Googlebot / Applebot は
 * `Chrome/` や `Safari/` を UA に含むため、順序を逆にすると人間の訪問として
 * 計上され、到来量が測れなくなる。
 */
function summarizeBot(ua: string): string | null {
  const lower = ua.toLowerCase()
  const known = BOT_TOKENS.find((entry) => lower.includes(entry.token))
  if (known !== undefined) return `${BOT_PREFIX}${known.label}`
  return GENERIC_BOT_PATTERN.test(lower) ? BOT_OTHER : null
}

/** UA からクライアント種別だけを粗く抜き出す（バージョンや詳細は保持しない）。 */
export function summarizeUA(ua: string): string | null {
  if (ua.length === 0) return null
  const bot = summarizeBot(ua)
  if (bot !== null) return bot
  if (ua.includes('Sparkle')) return 'Sparkle'
  if (ua.includes('Edg/')) return 'Edge'
  if (ua.includes('Firefox/')) return 'Firefox'
  if (ua.includes('Chrome/')) return 'Chrome'
  if (ua.includes('Safari/')) return 'Safari'
  if (ua.includes('curl/')) return 'curl'
  return 'other'
}

/**
 * 稼働中の befold のバージョンとして受け付ける形（TASK-491.1）。
 *
 * UA はクライアントが自由に詐称できるヘッダなので、素通しにすると
 * `app_version` の内訳が任意文字列で発散する。アプリ名は `befold` に固定し、
 * 版もバージョン様の形に限る。プレリリース識別子は `-dev.4` 以外
 * （`-beta.1` など）も将来ありうるため形だけを縛り、値は列挙しない。
 */
const APP_VERSION_PATTERN =
  /^befold\/(\d{1,4}\.\d{1,4}\.\d{1,4}(?:-[0-9A-Za-z.]{1,20})?) Sparkle\//u

/**
 * Sparkle の UA から**そのリクエストを出したアプリの稼働バージョン**を取り出す。
 *
 * 実測した UA は `befold/1.13.2-dev.4 Sparkle/2.9.4`（Sparkle 2.9.4 の
 * `SPUUpdater.userAgentString` を befold の Info.plist を main bundle にして
 * 実行、2026-08-16）。Sparkle 側の書式は `%@%@/%@ Sparkle/%@`。
 *
 * ここで返すのは `events.app_version` に入る値で、`events.version` とは意味が違う。
 * 前者は「今どのバージョンが動いているか」（`v` 接頭辞なし）、後者は download の
 * 「どのタグを取りに来たか」（`v1.13.2-dev.4` のようにタグそのもの）。
 *
 * 生 UA は保存しない方針なので、抽出した版だけを返す。パースできない UA
 * （curl・ブラウザ・空文字・詐称）では null を返し、記録処理は止めない。
 */
export function summarizeAppVersion(ua: string): string | null {
  return APP_VERSION_PATTERN.exec(ua)?.[1] ?? null
}

/**
 * `ua_summary` の値がボットとして分類されたものかを返す。
 *
 * 分類の適用前に記録された行は種類が分からず `'other'` に丸まっている。
 * それらは false（人間側）になる——遡って分類し直す材料が無いため。
 */
export function isBotSummary(uaSummary: string): boolean {
  return uaSummary.startsWith(BOT_PREFIX)
}
