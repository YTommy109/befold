import type { Context } from 'hono'
import type { AppEnv } from './index'
import {
  eventSchema,
  type Channel,
  type DisplayLang,
  type DownloadSource,
  type EventKind,
  type FallbackRoute,
  type Page,
} from './schema'
import { summarizeLang } from './lib/lang'
import { classifyHost, selfHostsFor } from './lib/hosts'
import { resolveReferrer } from './lib/referrer'
import { summarizeOS, summarizeUA, visitorTokenHash } from './lib/visitor'

/** 呼び出し側が指定するイベント固有の属性。 */
export type EventAttributes = {
  kind: EventKind
  version?: string | null
  channel?: Channel | null
  /** kind='download' のときのみ指定する発生経路。 */
  source?: DownloadSource | null
  /**
   * kind='visit' のときのみ指定する訪問先ページ。
   *
   * リクエスト URL から導出しない。`/dl/:tag/:file` のようにパスがパラメータを
   * 含む経路があり、導出にするとページ内訳のカーディナリティが発散するため、
   * 計上したいページを呼び出し側が明示する（`source` と同じ持ち方）。
   */
  page?: Page | null
  /**
   * kind='visit' のときのみ指定する、実際に配信したページの言語。
   *
   * URL 文字列から導出しない。ルートが `SITE_PAGES`（`lib/pages.ts`）の該当
   * エントリの `lang` をそのまま渡す——「どのビューを配信したか」という事実で
   * あって、パスの形から推測するものではない（`page` と同じ持ち方）。
   * これにより `<html lang>` / hreflang / og:locale / display_lang の 4 者が
   * 必ず同じ値から出る。
   */
  displayLang?: DisplayLang | null
  /** kind='github_fallback' のときのみ指定する、GitHub へ落ちた経路。 */
  fallback?: FallbackRoute | null
}

/**
 * リクエスト先ホストはここに無い。**呼び出し側から渡せない形にしてある。**
 *
 * host は全 kind で値を持つ必要があり、経路ごとに渡す形にすると、次に記録箇所を
 * 足したときの付け忘れが「その経路だけホスト不明」という静かな欠測になる。
 * リクエストから一意に決まるものなので `insertEvent` が URL から導出する
 * （`country` / `browserLang` と同じ持ち方）。
 */

const INSERT_SQL =
  'INSERT INTO events' +
  ' (timestamp, kind, version, channel, country, os, ua_summary, visitor_token, referrer,' +
  ' as_org, source, page, browser_lang, display_lang, host, fallback)' +
  ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'

/**
 * リクエストから計測イベントを組み立てて D1 に記録する。
 *
 * 計測は best-effort。`ctx.waitUntil` でレスポンスと切り離し、
 * 検証エラーや D1 障害が起きても呼び出し側のレスポンスには影響させない。
 */
export function recordEvent(c: Context<AppEnv>, attributes: EventAttributes): void {
  c.executionCtx.waitUntil(insertEvent(c, attributes))
}

async function insertEvent(c: Context<AppEnv>, attributes: EventAttributes): Promise<void> {
  try {
    const ts = Date.now()
    const host = new URL(c.req.url).host
    const ua = c.req.header('User-Agent') ?? ''
    const ip = c.req.header('CF-Connecting-IP') ?? ''

    const event = eventSchema.parse({
      timestamp: ts,
      kind: attributes.kind,
      version: attributes.version ?? null,
      channel: attributes.channel ?? null,
      country: c.req.header('CF-IPCountry') ?? null,
      os: summarizeOS(ua),
      uaSummary: summarizeUA(ua),
      visitorToken: await visitorTokenHash(ip, ua, ts),
      referrer: resolveReferrer(
        c.req.query('ref') ?? null,
        c.req.header('Referer') ?? null,
        selfHostsFor(host),
      ),
      // request.cf は Cloudflare の実行環境でのみ付与される。ローカル/テストでは
      // undefined になり得るため、欠落時は記録処理自体を止めず null にする。
      asOrg: c.req.raw.cf?.asOrganization ?? null,
      source: attributes.source ?? null,
      page: attributes.page ?? null,
      // 言語は kind を問わずリクエストから導出する。Accept-Language を送らない
      // クライアント（Sparkle など）では null になる。
      browserLang: summarizeLang(c.req.header('Accept-Language') ?? null),
      displayLang: attributes.displayLang ?? null,
      host: classifyHost(host),
      fallback: attributes.fallback ?? null,
    })

    await c.env.DB.prepare(INSERT_SQL)
      .bind(
        event.timestamp,
        event.kind,
        event.version,
        event.channel,
        event.country,
        event.os,
        event.uaSummary,
        event.visitorToken,
        event.referrer,
        event.asOrg,
        event.source,
        event.page,
        event.browserLang,
        event.displayLang,
        event.host,
        event.fallback,
      )
      .run()
  } catch (error) {
    console.error('failed to record event', error)
  }
}
