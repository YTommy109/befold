import type { Context } from 'hono'
import type { AppEnv } from './index'
import { eventSchema, type DownloadSource, type EventKind } from './schema'
import { selfHostsFor } from './lib/hosts'
import { resolveReferrer } from './lib/referrer'
import { summarizeOS, summarizeUA, visitorTokenHash } from './lib/visitor'

/** 呼び出し側が指定するイベント固有の属性。 */
export type EventAttributes = {
  kind: EventKind
  version?: string | null
  channel?: 'stable' | 'develop' | null
  /** kind='download' のときのみ指定する発生経路。 */
  source?: DownloadSource | null
}

const INSERT_SQL =
  'INSERT INTO events' +
  ' (timestamp, kind, version, channel, country, os, ua_summary, visitor_token, referrer, as_org, source)' +
  ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'

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
        selfHostsFor(new URL(c.req.url).host),
      ),
      // request.cf は Cloudflare の実行環境でのみ付与される。ローカル/テストでは
      // undefined になり得るため、欠落時は記録処理自体を止めず null にする。
      asOrg: c.req.raw.cf?.asOrganization ?? null,
      source: attributes.source ?? null,
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
      )
      .run()
  } catch (error) {
    console.error('failed to record event', error)
  }
}
