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

/**
 * visit として計上するページ。
 *
 * 生のパスを入れない。`/dl/:tag/:file` のようにパスがパラメータを含む経路が
 * あるため、URL から導出するとカーディナリティが発散し、内訳が読めなくなる。
 * ここに列挙したページを、呼び出し側が明示して渡す。
 */
export const pageSchema = z.enum(['/', '/features'])

export type Page = z.infer<typeof pageSchema>

/**
 * ブラウザの言語設定（Accept-Language の第一タグ）。
 *
 * 実際に読まれた言語ではない。詳細は `lib/lang.ts` の `summarizeLang`。
 */
export const browserLangSchema = z.enum(['ja', 'en', 'other'])

export type BrowserLang = z.infer<typeof browserLangSchema>

/**
 * 実際に配信したページの言語（TASK-496）。
 *
 * `browserLang` と対にして読む。前者は「求めた言語」（Accept-Language）、こちらは
 * 「実際に出した言語」で、両方あって初めて「英語を求めて来た人が英語ページへ
 * 辿り着けたか」が測れる。値は配信したビューの言語そのもので、URL 文字列からは
 * 導出しない（`lib/pages.ts` の `SITE_PAGES` が唯一の対応表）。
 */
export const displayLangSchema = z.enum(['ja', 'en'])

export type DisplayLang = z.infer<typeof displayLangSchema>

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
  page: pageSchema.nullable().default(null),
  browserLang: browserLangSchema.nullable().default(null),
  displayLang: displayLangSchema.nullable().default(null),
})

export type AnalyticsEvent = z.infer<typeof eventSchema>
