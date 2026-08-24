/**
 * 記事本文の唯一の正である `site/content/*.md` を、HTML へ変換して配る。
 *
 * **本文の文章をこのモジュール（や他の TS/TSX）に書かない。** 本文が TSX に
 * 埋まっていると、校正するのにブラウザで開くしかなくなる（TASK-546 の動機）。
 * ここが持つのは変換の仕組みだけで、文章は `content/` 側にしか無い。
 *
 * ## 変換はモジュール読み込み時の 1 回だけ
 *
 * 下の `HTML` はモジュールトップレベルの `const` で、リクエスト経路に Markdown の
 * パースは乗らない。`articleHtml()` は出来上がった文字列を引くだけ。
 *
 * 実測（workerd 上、11 KB の記事）: 4 回の render で 5.0 ms、40 回で 12.0 ms。
 * Worker の起動 CPU 上限 400 ms に対して十分小さいので、記事が増えても
 * 遅延化（初回リクエストでのメモ化）へ切り替える必要はない。
 *
 * ## 生 HTML を通している
 *
 * `html: true` で `.md` 中の生 HTML をそのまま出す。**本文は自分たちが書くもので、
 * 外部入力ではない**ため、サニタイズは行わない。ユーザー投稿やフィードの取り込みを
 * 本文経路へ流す場合は、この前提が崩れるので先にここを直すこと。
 *
 * ## 記事を 1 本足すには
 *
 * 1. `site/content/<slug>.ja.md` と `<slug>.en.md` を書く。見出しは `###` から
 *    始める（`##` にあたる記事タイトルは枠側の `ArticlePage` が描くため）。
 *    画像とサイト内ファイルへのリンクは `../public/...` と書く（`toSitePaths()` を参照）
 * 2. この下の import と `SOURCES` に 1 エントリ足す（列挙は手書き。wrangler の
 *    text モジュールは `import.meta.glob` のような一括取り込みを持たない）
 * 3. `src/lib/articles.ts` の `ARTICLES` と `src/schema.ts` の `pageSchema`、
 *    `src/lib/pages.ts` の `SITE_PAGES` に足す（`articles.test.ts` が漏れを落とす）
 *
 * 公開する言語（`articleLangs()`）の本文が欠けていれば、このモジュールの読み込み
 * 時点で throw する。テストより手前で、Worker が起動しない形で気づける。
 */

import MarkdownIt from 'markdown-it'

import aiCodeReviewEn from '../../content/ai-code-review.en.md'
import aiCodeReviewJa from '../../content/ai-code-review.ja.md'
import medicalExpensesEn from '../../content/medical-expenses.en.md'
import medicalExpensesJa from '../../content/medical-expenses.ja.md'
import { ARTICLES, articleLangs, type Article, type ArticleLang } from '../lib/articles'
import { downloadHref, REQUIRED_OS } from './shared'

/** 言語ごとの本文ソース。片方だけの状態は `assertComplete()` が落とす。 */
type Sources = Partial<Record<ArticleLang, string>>

/**
 * 記事本文の生 Markdown。`Article['page']` ごとに 1 エントリ。
 *
 * ここに載っていない記事はルートが登録されない（`registerArticle` が返る）。
 * 「`ARTICLES` に足したが本文はまだ」という状態を許すための余地で、移行前の
 * `ARTICLE_BODIES` と同じ扱い。
 */
const SOURCES: Partial<Record<Article['page'], Sources>> = {
  '/usecases/medical-expenses': { ja: medicalExpensesJa, en: medicalExpensesEn },
  '/usecases/ai-code-review': { ja: aiCodeReviewJa, en: aiCodeReviewEn },
}

/**
 * 素の Markdown で書けない部品を `{{名前}}` で埋め込む。
 *
 * **トークンは増やさない方針**。生 HTML は `.md` に直接書けるので、ここに要るのは
 * 「TS 側の定数を参照しないと書けないもの」だけ——いまは `downloadHref()` と
 * `REQUIRED_OS` を読むダウンロード導線 1 つ。URL や対応 OS を本文へベタ書きすると、
 * 変わったときに記事だけ古いまま残る。
 *
 * 描画関数が `page` も受け取るのは、`?ref=` に「どの記事から押されたか」を
 * 載せるため（TASK-549）。記事ごとに違う値なので `lang` だけでは書けない。
 */
const TOKENS: Record<string, (lang: ArticleLang, page: Article['page']) => string> = {
  cta: (lang, page) => {
    const label = lang === 'ja' ? 'Mac 版をダウンロード' : 'Download for Mac'
    const note =
      lang === 'ja'
        ? `${REQUIRED_OS.ja}が必要です。無料で使えます。`
        : `Requires ${REQUIRED_OS.en}. Free to use.`
    return `<p><a href="${downloadHref(page)}" class="btn-primary">${label}</a></p>\n<p class="listing-note">${note}</p>`
  },
}

/**
 * `.md` 上のパスを、配信時のパスへ書き換える。
 *
 * `.md` には**リポジトリ上に実在する相対パス**（`../public/images/foo.png`）を書く。
 * 配信時の絶対パス（`/images/foo.png`）を直接書くと、`site/content/` の `.md` を
 * befold やエディタで開いたときに画像もリンクも解決できず、**原稿として読み返せない**
 * ——外部化した意味が半分無くなる（TASK-546 の動機そのもの）。
 *
 * 書き換えは接頭辞 `../public/` を `/` に畳むだけ。`site/public/` は Worker が
 * `[assets]` として配信するディレクトリなので、この 1 対 1 の対応が成り立つ。
 *
 * 書き換え後に `../` が残っていたら throw する。配信時に解決できないパスなので、
 * 「リンク切れの記事が公開される」形で通さない。
 */
function toSitePaths(source: string, where: string): string {
  const rewritten = source.replaceAll('../public/', '/')
  if (rewritten.includes('../')) {
    throw new Error(`${where}: 配信できない相対パス（../）が残っている`)
  }
  return rewritten
}

/**
 * トークンを展開する。**綴り違いを本文へそのまま出さない。**
 *
 * 未知の名前は throw し、正規表現に一致しない書き方（`{{ cta }}` のような空白入り、
 * 閉じ忘れ）は展開後に `{{` が残ることで捕まえる。置換漏れを「本文に `{{cta}}` と
 * 表示される」形で通すと、公開してから気づくことになる。
 */
function expandTokens(
  source: string,
  lang: ArticleLang,
  page: Article['page'],
  where: string,
): string {
  const expanded = source.replaceAll(/\{\{([a-z-]+)\}\}/gu, (whole, name: string) => {
    const render = TOKENS[name]
    if (render === undefined) throw new Error(`${where}: 未知のトークン ${whole}`)
    return render(lang, page)
  })
  if (expanded.includes('{{')) throw new Error(`${where}: 展開されなかった {{ が残っている`)
  return expanded
}

/**
 * befold 本体（`BefoldApp/BefoldKit/Resources/`）と同じ markdown-it を使う。
 * 同じものを通すことで、befold で読んだ原稿と公開される記事の見た目が揃う。
 */
const md = new MarkdownIt({ html: true })

/**
 * 公開する言語の本文が揃っていることを、モジュール読み込み時に確かめる。
 *
 * 移行前は `<T lang={lang} ja="…" en="…" />` が構造的に両言語を強制していた。
 * ファイルを分けるとその担保が消え、`en` を書き忘れると**英語ページだけ 404**
 * になる。`SITE_PAGES` には載ったままなので sitemap には 404 の URL が出る、
 * という静かな壊れ方をする。
 *
 * 検査する言語は `articleLangs()` が返すものだけ。`hasEnglish: false` の
 * ドラフト（日本語だけ先に置く）を壊さないため。
 */
function assertComplete(article: Article, sources: Sources): void {
  for (const lang of articleLangs(article)) {
    if (sources[lang] === undefined) {
      throw new Error(`記事 ${article.page} の ${lang} 本文が無い（content/ に .md を置く）`)
    }
  }
}

function renderAll(): Partial<Record<Article['page'], Sources>> {
  const html: Partial<Record<Article['page'], Sources>> = {}

  for (const article of ARTICLES) {
    const sources = SOURCES[article.page]
    if (sources === undefined) continue
    assertComplete(article, sources)

    const rendered: Sources = {}
    for (const lang of articleLangs(article)) {
      const source = sources[lang]
      if (source === undefined) continue
      const where = `${article.page} (${lang})`
      rendered[lang] = md.render(
        toSitePaths(expandTokens(source, lang, article.page, where), where),
      )
    }
    html[article.page] = rendered
  }

  return html
}

/** 変換済みの本文。**モジュール読み込み時に 1 回だけ**組み立てる。 */
const HTML = renderAll()

/**
 * その記事・その言語の本文 HTML。未登録なら null。
 *
 * `?? null` であって `|| null` ではない。空の `.md`（書きかけ）と未登録は別物で、
 * 空文字列を「無い」と畳むと書きかけが 404 になる。
 */
export function articleHtml(article: Article, lang: ArticleLang): string | null {
  return HTML[article.page]?.[lang] ?? null
}

/** その記事の本文が登録されているか。ルートを登録するかの判定に使う。 */
export function hasArticleBody(article: Article): boolean {
  return HTML[article.page] !== undefined
}
