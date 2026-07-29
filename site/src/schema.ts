import { z } from 'zod'

/** 記録するイベント種別。 */
export const eventKindSchema = z.enum(['visit', 'download', 'update_check'])

export type EventKind = z.infer<typeof eventKindSchema>

/** D1 の events テーブルに INSERT する 1 行分の形状。 */
export const eventSchema = z.object({
  ts: z.number().int().nonnegative(),
  kind: eventKindSchema,
  version: z.string().nullable().default(null),
  channel: z.enum(['stable', 'develop']).nullable().default(null),
  country: z.string().nullable().default(null),
  os: z.string().nullable().default(null),
  uaSummary: z.string().nullable().default(null),
  visitorDay: z.string().nullable().default(null),
  referrer: z.string().nullable().default(null),
})

export type AnalyticsEvent = z.infer<typeof eventSchema>
