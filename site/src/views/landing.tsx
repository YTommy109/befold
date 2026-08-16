import type { FC } from 'hono/jsx'

import { pathFor, type SitePage } from '../lib/pages'
import { T, t, type Localized } from './i18n'
import { DOWNLOAD_PATH, FEATURES, MORE_FEATURES, REPO_URL, REQUIRED_OS } from './shared'
import { PageShell } from './shell'

/** kind: 'feature' はファイル形式ではなく機能の紹介なので、キャプションにラベルを添える。 */
const SCREENSHOTS: {
  src: string
  alt: Localized
  caption: string
  kind?: 'feature'
}[] = [
  {
    src: '/images/screenshot-1.png',
    alt: { ja: 'befold で表示した Mermaid のフローチャート', en: 'Mermaid flowchart in befold' },
    caption: 'Mermaid',
  },
  {
    src: '/images/screenshot-2.png',
    alt: { ja: 'befold で表示した SVG の図', en: 'SVG diagram rendering in befold' },
    caption: 'SVG',
  },
  {
    src: '/images/screenshot-3.png',
    alt: { ja: 'befold の Markdown プレビュー', en: 'Markdown preview in befold' },
    caption: 'Markdown',
  },
  {
    src: '/images/screenshot-4.png',
    alt: { ja: 'befold で表示した CSV の表', en: 'CSV table view in befold' },
    caption: 'CSV',
  },
  {
    src: '/images/screenshot-5.png',
    alt: { ja: 'befold のソースコード表示', en: 'Source code view in befold' },
    caption: 'Source Code',
  },
  {
    src: '/images/screenshot-6.png',
    alt: {
      ja: 'befold の Quick Open（あいまい検索）パネル',
      en: 'Quick Open fuzzy search panel in befold',
    },
    caption: 'Quick Open',
    kind: 'feature',
  },
  {
    src: '/images/screenshot-7.png',
    alt: {
      ja: 'befold のソース表示に並べた git の差分',
      en: 'Side-by-side git diff in the source view of befold',
    },
    caption: 'Git Diff',
    kind: 'feature',
  },
  {
    src: '/images/screenshot-8.png',
    alt: {
      ja: 'befold のサイドバーに出る変更ファイルの git ステータス',
      en: 'Sidebar showing git status badges for changed files in befold',
    },
    caption: 'Git Status',
    kind: 'feature',
  },
]

/** og:title / og:description を <title> / description と二重管理しないための定数。 */
const PAGE_TITLE: Localized = {
  ja: 'befold — macOS 向けファイルビューア',
  en: 'befold — File Viewer for macOS',
}

const PAGE_DESCRIPTION: Localized = {
  ja: 'befold は Markdown をあるがままの場所で読むための軽量な macOS ビューアです。Claude Code や Codex のようなコーディングエージェントが生成したドキュメントをレビューしたり、Finder でスペースキーを押すだけで GitHub と同じ見た目・Mermaid の作図・自動リロード付きで Markdown を読めます。',
  en: 'befold is a lightweight macOS viewer for reading Markdown where it already lives. Review the documents that coding agents like Claude Code and Codex generate, or just press Space in Finder to read a Markdown file with GitHub-style rendering, Mermaid diagrams and live reload.',
}

const OG_IMAGE_ALT: Localized = {
  ja: 'befold — Mermaid の図を含む Markdown ドキュメントを表示している macOS のファイルビューア',
  en: 'befold — a macOS file viewer showing a Markdown document with an embedded Mermaid diagram',
}

/**
 * 検索エンジン・AI 検索が読む構造化データ。
 * 対応 OS は本文の「動作要件」と同じ macOS 14 以降で揃える。
 *
 * `description` はページの言語に合わせる。構造化データの文面はページ上に見えて
 * いる内容と一致している必要があり、言語ごとに URL が分かれた以上、英語固定に
 * すると日本語ページで一致しなくなる。`operatingSystem` だけは技術的な値なので
 * 英語表記のまま揃える。
 */
function structuredData(origin: string, entry: SitePage): string {
  return JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: 'befold',
    description: t(entry.lang, PAGE_DESCRIPTION),
    url: `${origin}${entry.path}`,
    applicationCategory: 'DeveloperApplication',
    operatingSystem: REQUIRED_OS.en,
    downloadUrl: `${origin}${DOWNLOAD_PATH}`,
    softwareHelp: REPO_URL,
    image: `${origin}/images/ogp.png`,
    license: 'https://opensource.org/licenses/MIT',
    author: { '@type': 'Person', name: 'Tommy109', url: 'https://github.com/YTommy109' },
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
  })
}

/**
 * 配布 LP。ダウンロードは計測用の /download 経由にする。
 *
 * origin を受け取るのは、OGP のクローラが絶対 URL しか解決できない一方で、
 * ホスト名をハードコードすると staging が本番の URL を指してしまうため。
 * entry は配信中のバリアント（`SITE_PAGES` の 1 行）で、表示言語・canonical・
 * hreflang はすべてここから決まる。
 */
export const Landing: FC<{ origin: string; entry: SitePage }> = ({ origin, entry }) => {
  const lang = entry.lang

  return (
    <PageShell
      origin={origin}
      entry={entry}
      title={t(lang, PAGE_TITLE)}
      description={t(lang, PAGE_DESCRIPTION)}
      ogType="website"
      imageAlt={t(lang, OG_IMAGE_ALT)}
      jsonLd={structuredData(origin, entry)}
    >
      <main>
        <section class="hero">
          {lang === 'ja' ? (
            <>
              <h2>Markdown を行き来する。快適に。</h2>
              <p>
                Markdown や Mermaid そしてソースコードも軽快に読める
                <strong>Mac 専用</strong>の軽量ビューア。
              </p>
            </>
          ) : (
            <>
              <h2>Move through Markdown, comfortably.</h2>
              <p>
                A lightweight <strong>Mac-only</strong> viewer that reads Markdown, Mermaid and
                source code without slowing down.
              </p>
            </>
          )}
          <a href={DOWNLOAD_PATH} class="btn-primary">
            <T lang={lang} ja="Mac 版をダウンロード" en="Download for Mac" />
          </a>
          {/* ダウンロード前に対象 OS が伝わるよう、ボタン直下にも動作要件を置く。 */}
          <p class="hero-note">
            {lang === 'ja' ? (
              <>{REQUIRED_OS.ja}が必要です。Windows / Linux 版はありません。</>
            ) : (
              <>Requires {REQUIRED_OS.en}. There is no Windows or Linux version.</>
            )}
          </p>
        </section>

        {/* ふたつの読み手を同格に並べる。片方を従属させないため、
            両セクションは同じ .philosophy を使い、ラベルだけで宛先を分ける。 */}
        <section class="philosophy">
          {lang === 'ja' ? (
            <>
              <p class="philosophy-audience">コードを書く人へ</p>
              <p class="philosophy-lead">Claude が設計する。私は befold でレビューする。</p>
              <p class="philosophy-body">
                Claude Code や Codex が作る大量のドキュメントをスムーズにレビューするために befold
                を作りました。
                <br />
                編集機能は思い切って削り、読むことに特化したツールです。Quick Look
                にも対応してます。
              </p>
            </>
          ) : (
            <>
              <p class="philosophy-audience">For people who write code</p>
              <p class="philosophy-lead">Claude designs. I review in befold.</p>
              <p class="philosophy-body">
                I built befold to review the piles of documents that Claude Code and Codex generate.
                <br />
                Editing was deliberately left out — befold is a tool built purely for reading. It
                supports Quick Look, too.
              </p>
            </>
          )}
        </section>

        <section class="philosophy">
          {lang === 'ja' ? (
            <>
              <p class="philosophy-audience">Markdown を読む人へ</p>
              <p class="philosophy-lead">読むだけなら、詳しくなくていい。</p>
              <p class="philosophy-body">
                ファイルを開くだけ。覚えることも、決めておく設定もありません。
                <br />
                GitHub と同じ見た目で表示され、Mermaid のコードブロックは図として描かれます。
                <br />
                LLM がファイルを更新すると、0.2 秒で最新の内容に反映されます。
              </p>
            </>
          ) : (
            <>
              <p class="philosophy-audience">For people who read Markdown</p>
              <p class="philosophy-lead">You don&apos;t have to be technical to read it.</p>
              <p class="philosophy-body">
                Just open the file. Nothing to learn, nothing to configure beforehand.
                <br />
                It renders with the same look as GitHub, and Mermaid code blocks are drawn as
                diagrams.
                <br />
                When an LLM updates the file, the view catches up in 0.2 seconds.
              </p>
            </>
          )}
        </section>

        <section class="screenshot">
          <div class="carousel">
            <div class="carousel-track">
              {SCREENSHOTS.map((shot) => (
                <div class="carousel-slide">
                  {/* loading="lazy" は付けない。スライドは overflow:hidden の中を
                      transform で動かすため、Chrome がビューポート付近と判定せず
                      2 枚目以降が永久に読み込まれない。 */}
                  <img src={shot.src} alt={t(lang, shot.alt)} decoding="async" />
                  <p
                    class={
                      shot.kind === 'feature' ? 'carousel-caption feature' : 'carousel-caption'
                    }
                  >
                    {shot.caption}
                  </p>
                </div>
              ))}
            </div>
            <button
              class="carousel-prev"
              type="button"
              aria-label={t(lang, { ja: '前のスクリーンショット', en: 'Previous screenshot' })}
            >
              ‹
            </button>
            <button
              class="carousel-next"
              type="button"
              aria-label={t(lang, { ja: '次のスクリーンショット', en: 'Next screenshot' })}
            >
              ›
            </button>
            <div class="carousel-dots" />
          </div>
        </section>

        <section class="features">
          <h3>
            <T lang={lang} ja="機能" en="Features" />
          </h3>
          <div class="feature-grid">
            {FEATURES.map((feature) => (
              <div class="feature-card">
                <h4>
                  <T lang={lang} ja={feature.ja[0]} en={feature.en[0]} />
                </h4>
                <p>
                  <T lang={lang} ja={feature.ja[1]} en={feature.en[1]} />
                </p>
              </div>
            ))}
          </div>
          <ul class="feature-list">
            {MORE_FEATURES.map((feature) => (
              <li>
                <strong>
                  <T lang={lang} ja={feature.ja[0]} en={feature.en[0]} />
                </strong>{' '}
                — <T lang={lang} ja={feature.ja[1]} en={feature.en[1]} />
              </li>
            ))}
          </ul>
          <p class="section-more">
            <a href={pathFor('/features', lang)}>
              <T
                lang={lang}
                ja="全機能・対応ファイルタイプの一覧を見る →"
                en="See all features and supported file types →"
              />
            </a>
          </p>
        </section>

        <section class="requirements">
          <h3>
            <T lang={lang} ja="動作要件" en="Requirements" />
          </h3>
          <p>{t(lang, REQUIRED_OS)}</p>
        </section>

        <section class="install">
          <h3>
            <T lang={lang} ja="インストール" en="Installation" />
          </h3>
          {lang === 'ja' ? (
            <ol>
              <li>
                <a href={DOWNLOAD_PATH}>最新版をダウンロード</a>
              </li>
              <li>
                DMG を開き、<code>befold.app</code> を <code>/Applications</code> にコピーして起動
              </li>
            </ol>
          ) : (
            <ol>
              <li>
                <a href={DOWNLOAD_PATH}>Download the latest version</a>
              </li>
              <li>
                Open the DMG and copy <code>befold.app</code> to <code>/Applications</code> to
                launch
              </li>
            </ol>
          )}
        </section>
      </main>

      <script src="/carousel.js" />
    </PageShell>
  )
}
