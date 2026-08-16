/** Accept-Language の要約。ブラウザの言語設定であって、表示言語ではない。 */

import type { BrowserLang } from '../schema'

/**
 * 記録する言語区分。日英 2 言語の LP なので、それ以外は `other` に畳む。
 *
 * 生の言語タグ（`en-US` / `zh-Hans-TW` など）をそのまま入れない。内訳の
 * カーディナリティが際限なく増える一方、LP は日英しか出し分けないため、
 * `en-US` と `en-GB` の差は読み手に何も伝えない。
 */
export const LANG_JA = 'ja'
export const LANG_EN = 'en'
export const LANG_OTHER = 'other'

/**
 * Accept-Language から第一希望の言語だけを 'ja' / 'en' / 'other' に丸める。
 *
 * **これはブラウザの言語設定であって、実際に読まれた言語ではない。** LP は日英
 * 両方を同じ HTML に持ち、`localStorage` の `befold-lang` が未設定なら常に日本語を
 * 表示する（`src/views/shared.tsx` の LANG_SCRIPT）。したがって Accept-Language が
 * `en` の初回訪問者も、画面では日本語を読んでいる。この値が答えるのは
 * 「英語を求めて来た人がどれだけ居るか」であって「英語で読んだ人の数」ではない。
 *
 * q 値による並べ替えはしない。ブラウザは第一希望を先頭に置いて送るため、先頭の
 * タグを見れば足りる。ヘッダが無い・空・タグが取れない場合は null（Sparkle など
 * Accept-Language を送らないクライアントがこれに当たる）。
 */
export function summarizeLang(acceptLanguage: string | null): BrowserLang | null {
  if (acceptLanguage === null) return null

  const first = acceptLanguage.split(',')[0]?.split(';')[0]?.trim().toLowerCase() ?? ''
  // 言語タグの部分（`en-US` の `en`）だけを見る。地域差は畳む。
  const primary = first.split('-')[0] ?? ''

  if (primary.length === 0) return null
  // `*` はどの言語でもよいという意味で、希望が表明されていない。
  if (primary === '*') return null
  if (primary === LANG_JA) return LANG_JA
  if (primary === LANG_EN) return LANG_EN
  return LANG_OTHER
}
