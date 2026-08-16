import { env } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'

import { eventSchema } from '../src/schema'

describe('events テーブル', () => {
  it('マイグレーション適用後に INSERT / SELECT できる', async () => {
    const event = eventSchema.parse({
      timestamp: 1_700_000_000_000,
      kind: 'download',
      version: '1.2.3',
      channel: 'stable',
      country: 'JP',
    })

    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, version, channel, country, os, ua_summary, visitor_token)' +
        ' VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    )
      .bind(
        event.timestamp,
        event.kind,
        event.version,
        event.channel,
        event.country,
        event.os,
        event.uaSummary,
        event.visitorToken,
      )
      .run()

    const row = await env.DB.prepare(
      'SELECT kind, version, channel, country FROM events ORDER BY id DESC LIMIT 1',
    ).first()

    expect(row).toEqual({ kind: 'download', version: '1.2.3', channel: 'stable', country: 'JP' })
  })

  it('未知の kind を弾く', () => {
    // どう落ちたかまで固定する。型が合わない以外の理由（必須項目の欠落など）で
    // 落ちても通ってしまう空の toThrow() にしない。
    expect(() => eventSchema.parse({ timestamp: 0, kind: 'unknown' })).toThrow(
      /invalid_enum_value/u,
    )
  })

  it('列挙にないページを弾く', () => {
    // page は生パスではなく計上対象ページの列挙。増やすときはここを通す。
    expect(() => eventSchema.parse({ timestamp: 0, kind: 'visit', page: '/pricing' })).toThrow(
      /invalid_enum_value/u,
    )
    expect(eventSchema.parse({ timestamp: 0, kind: 'visit', page: '/features' }).page).toBe(
      '/features',
    )
  })
})
