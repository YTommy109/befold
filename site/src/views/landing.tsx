import type { FC } from 'hono/jsx'
import { html, raw } from 'hono/html'
import {
  DOWNLOAD_PATH,
  FEATURES,
  LANG_SCRIPT,
  MORE_FEATURES,
  REPO_URL,
  REQUIRED_OS,
  REQUIRED_OS_JA,
  SiteFooter,
  SiteHeader,
} from './shared'

/** kind: 'feature' はファイル形式ではなく機能の紹介なので、キャプションにラベルを添える。 */
const SCREENSHOTS: {
  src: string
  alt: string
  caption: string
  captionEn?: string
  kind?: 'feature'
}[] = [
  { src: '/images/screenshot-1.png', alt: 'Mermaid flowchart in befold', caption: 'Mermaid' },
  { src: '/images/screenshot-2.png', alt: 'SVG diagram rendering in befold', caption: 'SVG' },
  { src: '/images/screenshot-3.png', alt: 'Markdown preview in befold', caption: 'Markdown' },
  { src: '/images/screenshot-4.png', alt: 'CSV table view in befold', caption: 'CSV' },
  { src: '/images/screenshot-5.png', alt: 'Source code view in befold', caption: 'Source Code' },
  {
    src: '/images/screenshot-6.png',
    alt: 'Quick Open fuzzy search panel in befold',
    caption: 'Quick Open',
    kind: 'feature',
  },
  {
    src: '/images/screenshot-7.png',
    alt: 'Side-by-side git diff in the source view of befold',
    caption: 'Git Diff',
    kind: 'feature',
  },
  {
    src: '/images/screenshot-8.png',
    alt: 'Sidebar showing git status badges for changed files in befold',
    caption: 'Git Status',
    kind: 'feature',
  },
]

/** og:title / og:description を <title> / description と二重管理しないための定数。 */
const PAGE_TITLE = 'befold — File Viewer for macOS'
const PAGE_DESCRIPTION =
  'befold is a lightweight macOS viewer for reading Markdown where it already lives. Review the documents that coding agents like Claude Code and Codex generate, or just press Space in Finder to read a Markdown file with GitHub-style rendering, Mermaid diagrams and live reload.'

/**
 * 検索エンジン・AI 検索が読む構造化データ。
 * 対応 OS は本文の「動作要件」と同じ macOS 14 以降で揃える。
 */
function structuredData(origin: string): string {
  return JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: 'befold',
    description: PAGE_DESCRIPTION,
    url: `${origin}/`,
    applicationCategory: 'DeveloperApplication',
    operatingSystem: REQUIRED_OS,
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
 */
export const Landing: FC<{ origin: string }> = ({ origin }) => (
  <html lang="ja">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>{PAGE_TITLE}</title>
      <meta name="description" content={PAGE_DESCRIPTION} />
      <link rel="canonical" href={`${origin}/`} />
      <meta property="og:type" content="website" />
      <meta property="og:site_name" content="befold" />
      <meta property="og:title" content={PAGE_TITLE} />
      <meta property="og:description" content={PAGE_DESCRIPTION} />
      <meta property="og:url" content={`${origin}/`} />
      <meta property="og:image" content={`${origin}/images/ogp.png`} />
      <meta property="og:image:width" content="1200" />
      <meta property="og:image:height" content="630" />
      <meta
        property="og:image:alt"
        content="befold — a macOS file viewer showing a Markdown document with an embedded Mermaid diagram"
      />
      <meta name="twitter:card" content="summary_large_image" />
      <link rel="stylesheet" href="/style.css" />
      {html`<script type="application/ld+json">
        ${raw(structuredData(origin))}
      </script>`}
    </head>
    <body>
      <SiteHeader title="befold" />

      <main>
        <section class="hero">
          <div lang="ja">
            <h2>Markdown を行き来する。快適に。</h2>
            <p>
              Markdown や Mermaid そしてソースコードも軽快に読める
              <strong>Mac 専用</strong>の軽量ビューア。
            </p>
          </div>
          <div lang="en" hidden>
            <h2>Move through Markdown, comfortably.</h2>
            <p>
              A lightweight <strong>Mac-only</strong> viewer that reads Markdown, Mermaid and
              source code without slowing down.
            </p>
          </div>
          <a href={DOWNLOAD_PATH} class="btn-primary">
            <span lang="ja">Mac 版をダウンロード</span>
            <span lang="en" hidden>
              Download for Mac
            </span>
          </a>
          {/* ダウンロード前に対象 OS が伝わるよう、ボタン直下にも動作要件を置く。 */}
          <p class="hero-note" lang="ja">
            {REQUIRED_OS_JA}が必要です。Windows / Linux 版はありません。
          </p>
          <p class="hero-note" lang="en" hidden>
            Requires {REQUIRED_OS}. There is no Windows or Linux version.
          </p>
        </section>

        {/* ふたつの読み手を同格に並べる。片方を従属させないため、
            両セクションは同じ .philosophy を使い、ラベルだけで宛先を分ける。 */}
        <section class="philosophy">
          <div lang="ja">
            <p class="philosophy-audience">コードを書く人へ</p>
            <p class="philosophy-lead">Claude が設計する。私は befold でレビューする。</p>
            <p class="philosophy-body">
              Claude Code や Codex が作る大量のドキュメントをスムーズにレビューするために
              befold を作りました。
              <br />
              編集機能は思い切って削り、読むことに特化したツールです。Quick Look にも対応してます。
            </p>
          </div>
          <div lang="en" hidden>
            <p class="philosophy-audience">For people who write code</p>
            <p class="philosophy-lead">Claude designs. I review in befold.</p>
            <p class="philosophy-body">
              I built befold to review the piles of documents that Claude Code and Codex generate.
              <br />
              Editing was deliberately left out — befold is a tool built purely for reading. It
              supports Quick Look, too.
            </p>
          </div>
        </section>

        <section class="philosophy">
          <div lang="ja">
            <p class="philosophy-audience">Markdown を読む人へ</p>
            <p class="philosophy-lead">読むだけなら、詳しくなくていい。</p>
            <p class="philosophy-body">
              ファイルを開くだけ。覚えることも、決めておく設定もありません。
              <br />
              GitHub と同じ見た目で表示され、Mermaid のコードブロックは図として描かれます。
              <br />
              LLM がファイルを更新すると、0.2 秒で最新の内容に反映されます。
            </p>
          </div>
          <div lang="en" hidden>
            <p class="philosophy-audience">For people who read Markdown</p>
            <p class="philosophy-lead">You don't have to be technical to read it.</p>
            <p class="philosophy-body">
              Just open the file. Nothing to learn, nothing to configure beforehand.
              <br />
              It renders with the same look as GitHub, and Mermaid code blocks are drawn as
              diagrams.
              <br />
              When an LLM updates the file, the view catches up in 0.2 seconds.
            </p>
          </div>
        </section>

        <section class="screenshot">
          <div class="carousel">
            <div class="carousel-track">
              {SCREENSHOTS.map((shot) => (
                <div class="carousel-slide">
                  {/* loading="lazy" は付けない。スライドは overflow:hidden の中を
                      transform で動かすため、Chrome がビューポート付近と判定せず
                      2 枚目以降が永久に読み込まれない。 */}
                  <img src={shot.src} alt={shot.alt} decoding="async" />
                  <p
                    class={
                      shot.kind === 'feature' ? 'carousel-caption feature' : 'carousel-caption'
                    }
                  >
                    {shot.captionEn === undefined ? (
                      shot.caption
                    ) : (
                      <>
                        <span lang="ja">{shot.caption}</span>
                        <span lang="en" hidden>
                          {shot.captionEn}
                        </span>
                      </>
                    )}
                  </p>
                </div>
              ))}
            </div>
            <button class="carousel-prev" type="button" aria-label="Previous screenshot">
              ‹
            </button>
            <button class="carousel-next" type="button" aria-label="Next screenshot">
              ›
            </button>
            <div class="carousel-dots" />
          </div>
        </section>

        <section class="features">
          <div lang="ja">
            <h3>機能</h3>
          </div>
          <div lang="en" hidden>
            <h3>Features</h3>
          </div>
          <div class="feature-grid">
            {FEATURES.map((feature) => (
              <div class="feature-card">
                <h4 lang="ja">{feature.ja[0]}</h4>
                <h4 lang="en" hidden>
                  {feature.en[0]}
                </h4>
                <p lang="ja">{feature.ja[1]}</p>
                <p lang="en" hidden>
                  {feature.en[1]}
                </p>
              </div>
            ))}
          </div>
          <ul class="feature-list">
            {MORE_FEATURES.map((feature) => (
              <li>
                <span lang="ja">
                  <strong>{feature.ja[0]}</strong> — {feature.ja[1]}
                </span>
                <span lang="en" hidden>
                  <strong>{feature.en[0]}</strong> — {feature.en[1]}
                </span>
              </li>
            ))}
          </ul>
          <p class="section-more">
            <a href="/features">
              <span lang="ja">全機能・対応ファイルタイプの一覧を見る →</span>
              <span lang="en" hidden>
                See all features and supported file types →
              </span>
            </a>
          </p>
        </section>

        <section class="requirements">
          <div lang="ja">
            <h3>動作要件</h3>
            <p>{REQUIRED_OS_JA}</p>
          </div>
          <div lang="en" hidden>
            <h3>Requirements</h3>
            <p>{REQUIRED_OS}</p>
          </div>
        </section>

        <section class="install">
          <div lang="ja">
            <h3>インストール</h3>
            <ol>
              <li>
                <a href={DOWNLOAD_PATH}>最新版をダウンロード</a>
              </li>
              <li>
                DMG を開き、<code>befold.app</code> を <code>/Applications</code>{' '}
                にコピーして起動
              </li>
            </ol>
          </div>
          <div lang="en" hidden>
            <h3>Installation</h3>
            <ol>
              <li>
                <a href={DOWNLOAD_PATH}>Download the latest version</a>
              </li>
              <li>
                Open the DMG and copy <code>befold.app</code> to <code>/Applications</code> to
                launch
              </li>
            </ol>
          </div>
        </section>
      </main>

      <SiteFooter />

      <script src="/carousel.js" />
      {html`<script>
        ${raw(LANG_SCRIPT)}
      </script>`}
    </body>
  </html>
)
