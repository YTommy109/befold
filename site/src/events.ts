import type { Context } from 'hono'
import type { AppEnv } from './index'
import { eventSchema, type EventKind } from './schema'
import { resolveReferrer } from './lib/referrer'
import { summarizeOS, summarizeUA, visitorDayHash } from './lib/visitor'

/** 呼び出し側が指定するイベント固有の属性。 */
export type EventAttributes = {
  kind: EventKind
  version?: string | null
  channel?: 'stable' | 'develop' | null
}

const INSERT_SQL =
  'INSERT INTO events' +
  ' (ts, kind, version, channel, country, os, ua_summary, visitor_day, referrer)' +
  ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'

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
      ts,
      kind: attributes.kind,
      version: attributes.version ?? null,
      channel: attributes.channel ?? null,
      country: c.req.header('CF-IPCountry') ?? null,
      os: summarizeOS(ua),
      uaSummary: summarizeUA(ua),
      visitorDay: await visitorDayHash(ip, ua, ts),
      referrer: resolveReferrer(
        c.req.query('ref') ?? null,
        c.req.header('Referer') ?? null,
        new URL(c.req.url).host,
      ),
    })

    await c.env.DB.prepare(INSERT_SQL)
      .bind(
        event.ts,
        event.kind,
        event.version,
        event.channel,
        event.country,
        event.os,
        event.uaSummary,
        event.visitorDay,
        event.referrer,
      )
      .run()
  } catch (error) {
    console.error('failed to record event', error)
  }
}
