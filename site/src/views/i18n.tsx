/** 言語ごとの URL で 1 言語だけを描くためのヘルパー（TASK-496）。 */

import type { FC } from 'hono/jsx'
import type { PageLang } from '../lib/pages'

/** 日英の対を持つ値。データ側の `{ ja, en }` はすべてこの形に揃えてある。 */
export type Localized = { ja: string; en: string }

/**
 * 言語に応じて片方の文字列を選ぶ。**属性値にはこちらを使う**。
 *
 * `alt` や `aria-label` はコンポーネントを差し込めないため、JSX の `<T>` では
 * 届かない。同じ対応表を関数からも引けるようにしておく。
 */
export function t(lang: PageLang, value: Localized): string {
  return value[lang]
}

/**
 * 言語に応じて片方の文面だけを描く。
 *
 * 以前は日英の両方を DOM に入れて `hidden` で隠していたが、その形だと
 * hreflang が出せず、実際に読まれた言語もサーバから観測できなかった。いまは
 * URL が言語を決めるので、出力するのは片方だけでよい。
 */
export const T: FC<{ lang: PageLang; ja: string; en: string }> = ({ lang, ja, en }) => (
  <>{lang === 'ja' ? ja : en}</>
)
