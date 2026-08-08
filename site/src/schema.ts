import { z } from 'zod'

/** 記録するイベント種別。 */
export const eventKindSchema = z.enum(['visit', 'download', 'update_check'])

export type EventKind = z.infer<typeof eventKindSchema>

/**
 * ダウンロードの発生経路。
 *
 * `lp` は配布 LP の /download 経由、`sparkle` は appcast の enclosure
 * （自動アップデート）経由。成果物を R2 へ移して enclosure を Worker 配下に
 * すると、両者が同じ kind='download' として記録されるようになる。
 * 新規獲得と既存ユーザの更新は性質が違うので、集計時に分離できるようにする。
 */
export const downloadSourceSchema = z.enum(['lp', 'sparkle'])

export type DownloadSource = z.infer<typeof downloadSourceSchema>

/** D1 の events テーブルに INSERT する 1 行分の形状。 */
export const eventSchema = z.object({
  timestamp: z.number().int().nonnegative(),
  kind: eventKindSchema,
  version: z.string().nullable().default(null),
  channel: z.enum(['stable', 'develop']).nullable().default(null),
  country: z.string().nullable().default(null),
  os: z.string().nullable().default(null),
  uaSummary: z.string().nullable().default(null),
  visitorToken: z.string().nullable().default(null),
  referrer: z.string().nullable().default(null),
  asOrg: z.string().nullable().default(null),
  source: downloadSourceSchema.nullable().default(null),
})

export type AnalyticsEvent = z.infer<typeof eventSchema>
