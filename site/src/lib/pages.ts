/**
 * この Worker が配信する HTML ページの定義。**ページのパス列挙はここだけに置く。**
 *
 * LP と詳細ページを言語ごとの URL に分けた（TASK-496）ことで、同じ列挙を必要と
 * する場所が 5 つになった——ルート登録・`REDIRECTED_PATHS`・sitemap.xml・
 * hreflang・`og:locale`。ADR 0007 の決定 2 自身が「列挙は漏れる形で壊れる」と
 * 書いているとおり、5 箇所に書き写す形は必ずどこかが取り残される。ここを唯一の
 * 定義にして全部を導出する。
 *
 * **`/download`・`/dl/:tag/:file`・appcast をここに載せてはならない。** この表は
 * 「旧ホストから新ドメインへ 301 してよい HTML ページ」でもある（ADR 0007 の
 * 決定 2）。機械向けの経路を載せると、出荷済みアプリの更新経路が 301 を挟む形に
 * なって壊れる。`/download` も載せない——LP 由来のダウンロード計測（`source:'lp'`）
 * が 301 で別ホストの計測へ散るため（同決定 2）。
 */

import type { Page } from '../schema'

/** ページの表示言語。URL がこの状態の唯一の持ち主。 */
export type PageLang = 'ja' | 'en'

export type SitePage = {
  /** リクエストパス。 */
  path: string
  /** このパスで配信する言語。`<html lang>` / hreflang / og:locale / events.display_lang はすべてこの値から出る。 */
  lang: PageLang
  /** 計測上の論理ページ。言語が違っても同じ値になる（言語は display_lang が持つ）。 */
  page: Page
}

/**
 * 配信する 4 ページ。日本語を既定の URL に置き、英語を `/en` 配下に置く。
 *
 * 日本語側の URL を変えていないのは、既存の被リンク・sitemap・旧ホストからの
 * 301 をそのまま生かすため。
 */
export const SITE_PAGES: readonly SitePage[] = [
  { path: '/', lang: 'ja', page: '/' },
  { path: '/en', lang: 'en', page: '/' },
  { path: '/features', lang: 'ja', page: '/features' },
  { path: '/en/features', lang: 'en', page: '/features' },
]

/** `og:locale` に使うロケール。hreflang の言語コードとは書式が違う。 */
export const OG_LOCALE: Record<PageLang, string> = {
  ja: 'ja_JP',
  en: 'en_US',
}

/**
 * 指定のページを指定の言語で配信しているパス。ページ間リンクの宛先に使う。
 *
 * リンク先を `'/en/features'` のような文字列で書かない。`SITE_PAGES` を唯一の
 * 対応表にしておかないと、パスを変えたときにリンクだけが取り残される。
 */
export function pathFor(page: Page, lang: PageLang): string {
  const entry = SITE_PAGES.find((candidate) => candidate.page === page && candidate.lang === lang)
  if (entry === undefined) throw new Error(`no page ${page} in ${lang}`)
  return entry.path
}

/** 同じ論理ページの全バリアント（自分自身を含む）。hreflang と sitemap の両方が使う。 */
export function variantsOf(page: Page): readonly SitePage[] {
  return SITE_PAGES.filter((entry) => entry.page === page)
}

/**
 * 相手言語のページ。言語切替リンクの宛先。
 *
 * 2 言語しか無い前提を関数の中に閉じ込めてある。3 言語目を足すときはここが
 * コンパイルエラーにならないので、`variantsOf` を使う一覧表示へ作り替えること。
 */
export function alternateOf(entry: SitePage): SitePage {
  const other = variantsOf(entry.page).find((candidate) => candidate.lang !== entry.lang)
  if (other === undefined) throw new Error(`no alternate for ${entry.path}`)
  return other
}
