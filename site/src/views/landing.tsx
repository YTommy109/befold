import type { FC } from 'hono/jsx'
import { html, raw } from 'hono/html'

const REPO_URL = 'https://github.com/YTommy109/befold'

/** ダウンロード導線は配布サイトの絶対 URL に揃える。 */
const DOWNLOAD_URL = 'https://befold.tommy109.workers.dev/download'

const LANG_SCRIPT = `
function switchLang(lang) {
  document.querySelectorAll('[lang]').forEach(function(el) {
    if (el.tagName === 'HTML') return;
    el.hidden = el.getAttribute('lang') !== lang;
  });
  document.querySelectorAll('.lang-btn').forEach(function(btn) {
    btn.classList.toggle('active', btn.textContent.trim() === (lang === 'ja' ? '\u{1F1EF}\u{1F1F5}' : 'EN'));
  });
  document.documentElement.lang = lang;
  localStorage.setItem('befold-lang', lang);
}

(function() {
  var saved = localStorage.getItem('befold-lang');
  if (saved && saved !== 'ja') {
    switchLang(saved);
  }
})();
`

type Feature = { ja: [string, string]; en: [string, string] }

const FEATURES: Feature[] = [
  {
    ja: [
      'Quick Open (⌘P)',
      'ファイル名のあいまい検索で目的のファイルへ一息で。空欄なら最近開いたファイルとブックマークが並び、./ や ../ のパス入力にも対応',
    ],
    en: [
      'Quick Open (⌘P)',
      'Fuzzy-search filenames to jump straight to a file. An empty query lists recents and bookmarks, and ./ or ../ path input works too',
    ],
  },
  {
    ja: [
      'サイドバー & スワイプ',
      '⌘S でサイドバーを開き、フォルダを辿って名前で絞り込む。⌘[ / ⌘] とトラックパッドの2本指スワイプで読んだファイルを行き来できる',
    ],
    en: [
      'Sidebar & Swipe',
      'Open the sidebar with ⌘S to walk folders and filter by name. Move between files you have read with ⌘[ / ⌘] or a two-finger trackpad swipe',
    ],
  },
  {
    ja: [
      'CLI から開く',
      'befold path/... で複数ファイルをまとめて開く。--sidebar / --source / --line-numbers などの表示指定、表示可否だけを確かめる --check、--bookmark も使える',
    ],
    en: [
      'Open from the CLI',
      'befold path/... opens several files at once. Display flags like --sidebar, --source and --line-numbers, plus --check to verify a file opens and --bookmark',
    ],
  },
  {
    ja: [
      'ライブリロード',
      '外部のエディタや AI がファイルを書き換えると即座にプレビューへ反映。保存時に作り直されるファイルやリネーム・移動にも追従する',
    ],
    en: [
      'Live Reload',
      'Every change from an external editor or an AI lands in the preview instantly — including files recreated on save, renames and moves',
    ],
  },
  {
    ja: [
      '大きなファイルも開ける',
      'Markdown・CSV/TSV・ソースコードは分割して読み込むので、最大 100MB のファイルも待たされずに開ける。続きは「さらに読み込む」で',
    ],
    en: [
      'Large Files, Too',
      'Markdown, CSV/TSV and source code load in chunks, so files up to 100MB open without a wait. Pull in the rest with “Load More”',
    ],
  },
  {
    ja: [
      'QuickLook 対応',
      'QuickLook 拡張を同梱。Finder でファイルを選んでスペースキーを押すだけで、アプリを開かずに Mermaid や Markdown をレンダリング表示できる',
    ],
    en: [
      'QuickLook Support',
      'Ships a QuickLook extension. Select a file in Finder and hit space to see Mermaid or Markdown rendered — no need to open the app',
    ],
  },
]

/** Features グリッドの下に列挙する、際立たせるほどではない機能。 */
const MORE_FEATURES: Feature[] = [
  {
    ja: [
      'git を知っているリンク解決',
      'Markdown 内のパスは実在するものだけリンクになる。相対パスで見つからなければ git の追跡ファイルから探し当て、worktree やブランチを切り替えても追従する',
    ],
    en: [
      'Git-Aware Link Resolution',
      'Only paths that really exist become links. When a relative path misses, befold finds the file among git-tracked ones — and keeps up when you switch worktrees or branches',
    ],
  },
  {
    ja: [
      '多彩なフォーマット対応',
      '.mmd, .md, .svg, .html, .csv, .tsv のレンダリング表示に加え、.png, .jpg, .gif, .webp, .pdf, ソースコード（50以上の言語）にも対応。文字コードは UTF-8/16/32・Shift_JIS・EUC-JP を自動判別',
    ],
    en: [
      'Wide Format Support',
      'Renders .mmd, .md, .svg, .html, .csv, .tsv — plus displays .png, .jpg, .gif, .webp, .pdf, and source code in 50+ languages. Detects UTF-8/16/32, Shift_JIS and EUC-JP automatically',
    ],
  },
  {
    ja: [
      'レンダリング / ソース切替',
      '⌘U でレンダリング表示とソース表示をワンタッチ切替。ソースはシンタックスハイライトと ⌘L の行番号付き。⌘F の検索は正規表現・大文字小文字・単語単位に対応',
    ],
    en: [
      'Rendered / Source Toggle',
      'Switch between rendered and source view with ⌘U. Source view has syntax highlighting and line numbers via ⌘L. Find (⌘F) supports regex, case and whole-word matching',
    ],
  },
  {
    ja: [
      'タブ & セッション復元',
      'macOS ネイティブのタブ対応。前回のタブ構成は次回起動時に自動復元され、ズーム率・表示モード・スクロール位置はファイルごとに記憶する',
    ],
    en: [
      'Tabs & Session Restore',
      'Native macOS tabs. Your previous tab layout is restored on next launch, and zoom, view mode and scroll position are remembered per file',
    ],
  },
  {
    ja: [
      'ズーム & ダークモード',
      '⌘+/⌘-/⌘0 でズーム操作。macOS のダークモードに自動追従し、ソース表示のフォントは設定から変更できる',
    ],
    en: [
      'Zoom & Dark Mode',
      'Zoom with ⌘+/⌘-/⌘0. Follows macOS dark mode automatically, and the source-view font is configurable in Settings',
    ],
  },
  {
    ja: ['アプリ内アップデート', '新しいバージョンが利用可能になると通知。ワンクリックで更新'],
    en: ['In-App Updates', 'Notifies when a new version is available. One-click update'],
  },
]

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
]

/** og:title / og:description を <title> / description と二重管理しないための定数。 */
const PAGE_TITLE = 'befold — File Viewer for macOS'
const PAGE_DESCRIPTION =
  'befold is a lightweight macOS viewer for reviewing the Markdown that terminal coding agents like Claude Code and Codex generate. Open any file from the CLI or with ⌘P — including git worktrees — and read Mermaid, Markdown, SVG, HTML and CSV with live reload.'

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
    operatingSystem: 'macOS 14 (Sonoma) or later',
    downloadUrl: DOWNLOAD_URL,
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
      <a
        class="github-ribbon"
        href={REPO_URL}
        target="_blank"
        rel="noopener"
        aria-label="View source on GitHub"
      >
        <span>GitHub</span>
      </a>

      <header>
        <h1>befold</h1>
        <div class="lang-switcher">
          <button class="lang-btn active" onclick="switchLang('ja')" type="button">
            🇯🇵
          </button>
          <button class="lang-btn" onclick="switchLang('en')" type="button">
            EN
          </button>
        </div>
      </header>

      <main>
        <section class="hero">
          <div lang="ja">
            <h2>Markdown を行き来する。快適に。</h2>
            <p>
              数百のファイルを抱えたリポジトリのための、<strong>Mac 専用</strong>の軽量ビューア。
            </p>
          </div>
          <div lang="en" hidden>
            <h2>Move through Markdown, comfortably.</h2>
            <p>
              A lightweight <strong>Mac-only</strong> viewer for repositories that hold hundreds of
              files.
            </p>
          </div>
          <a href={DOWNLOAD_URL} class="btn-primary">
            <span lang="ja">Mac 版をダウンロード</span>
            <span lang="en" hidden>
              Download for Mac
            </span>
          </a>
          {/* ダウンロード前に対象 OS が伝わるよう、ボタン直下にも動作要件を置く。 */}
          <p class="hero-note" lang="ja">
            macOS 14 (Sonoma) 以降が必要です。Windows / Linux 版はありません。
          </p>
          <p class="hero-note" lang="en" hidden>
            Requires macOS 14 (Sonoma) or later. There is no Windows or Linux version.
          </p>
        </section>

        <section class="philosophy review">
          <div lang="ja">
            <p class="philosophy-lead">Claude が設計する。私は befold でレビューする。</p>
            <p class="philosophy-body">
              Claude Code や Codex に設計を任せると、Markdown のドキュメントがたくさん作られる。
              <br />
              ドキュメントを直せば、AI が作るコードは良くなる。
              <br />
              befold は「読む」を快適にする。
            </p>
          </div>
          <div lang="en" hidden>
            <p class="philosophy-lead">Claude designs. I review in befold.</p>
            <p class="philosophy-body">
              Hand the design to Claude Code or Codex, and a lot of Markdown documents get written.
              <br />
              Fix the documents, and the code the AI writes gets better.
              <br />
              befold makes reading them comfortable.
            </p>
          </div>
        </section>

        <section class="philosophy">
          <div lang="ja">
            <p class="philosophy-lead">vault に登録しなくていい。</p>
            <p class="philosophy-body">
              Obsidian は Markdown を快適に読ませてくれる。
              <br />
              けど worktree まで、vault へ登録してられない。
              <br />
              befold なら <code>befold .</code> と打つだけ。切ったばかりの worktree の
              Markdown も、その場で読める。
            </p>
          </div>
          <div lang="en" hidden>
            <p class="philosophy-lead">No vault to register.</p>
            <p class="philosophy-body">
              Obsidian reads Markdown beautifully.
              <br />
              But I'm not registering every worktree as a vault.
              <br />
              With befold, <code>befold .</code> is all it takes — the Markdown in a worktree you
              just created opens right there.
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
        </section>

        <section class="requirements">
          <div lang="ja">
            <h3>動作要件</h3>
            <p>macOS 14 (Sonoma) 以降</p>
          </div>
          <div lang="en" hidden>
            <h3>Requirements</h3>
            <p>macOS 14 (Sonoma) or later</p>
          </div>
        </section>

        <section class="install">
          <div lang="ja">
            <h3>インストール</h3>
            <ol>
              <li>
                <a href={DOWNLOAD_URL}>最新版をダウンロード</a>
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
                <a href={DOWNLOAD_URL}>Download the latest version</a>
              </li>
              <li>
                Open the DMG and copy <code>befold.app</code> to <code>/Applications</code> to
                launch
              </li>
            </ol>
          </div>
        </section>
      </main>

      <footer>
        <p>
          <a href={REPO_URL}>GitHub</a> · MIT License · © 2026{' '}
          <a href="https://github.com/YTommy109">Tommy109</a>
        </p>
      </footer>

      <script src="/carousel.js" />
      {html`<script>
        ${raw(LANG_SCRIPT)}
      </script>`}
    </body>
  </html>
)
