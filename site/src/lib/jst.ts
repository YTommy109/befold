/**
 * 日付・時刻の基準タイムゾーン（JST = UTC+9）の唯一の定義元。
 *
 * 集計の日付バケット・時間帯バケット・visitor_token のハッシュ日付・
 * 画面表示の時刻をすべてこの基準にそろえる。SQL 側の補正を各クエリへ
 * 直書きすると、1 箇所書き忘れても SQL は valid のまま UTC の結果を
 * 静かに返すため、式ごと定数にして差し込む。
 */

export const JST_OFFSET_MS = 9 * 60 * 60 * 1000

/** 1 日のミリ秒。経過日数の計算にも使うので、ここを唯一の定義元にする。 */
export const DAY_MS = 24 * 60 * 60 * 1000

/** SQLite で timestamp (epoch ms) を JST の 'YYYY-MM-DD' にする式。 */
export const JST_DAY_EXPR = "date(timestamp / 1000, 'unixepoch', '+9 hours')"

/** SQLite で timestamp (epoch ms) を JST の時（'00'〜'23'）にする式。 */
export const JST_HOUR_EXPR = "strftime('%H', timestamp / 1000, 'unixepoch', '+9 hours')"

/** epoch ms を JST の 'YYYY-MM-DD' に変換する。 */
export function jstDayKey(ts: number): string {
  return new Date(ts + JST_OFFSET_MS).toISOString().slice(0, 10)
}

/** epoch ms を JST の 'YYYY-MM-DD HH:mm:ss' 表記に変換する。 */
export function formatJst(ts: number): string {
  return new Date(ts + JST_OFFSET_MS).toISOString().replace('T', ' ').slice(0, 19)
}

/** ts が属する JST の日の 0 時を epoch ms で返す。 */
export function jstDayStart(ts: number): number {
  return Date.parse(`${jstDayKey(ts)}T00:00:00Z`) - JST_OFFSET_MS
}

/**
 * 「当日を含む直近 days 日」の窓の開始を epoch ms で返す。
 *
 * now からの単純な差分（now - days * 24h）にすると端の 1 日が
 * 途中で切れるため、JST の日境界にそろえる。
 */
export function jstWindowStart(now: number, days: number): number {
  return jstDayStart(now) - (days - 1) * DAY_MS
}

/** 窓に含まれる JST 日付を古い順に列挙する（データが無い日のゼロ埋め用）。 */
export function jstDaysInWindow(now: number, days: number): string[] {
  const start = jstWindowStart(now, days)
  return Array.from({ length: days }, (_, index) => jstDayKey(start + index * DAY_MS))
}
