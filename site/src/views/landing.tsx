import type { FC } from 'hono/jsx'
import { html, raw } from 'hono/html'

const REPO_URL = 'https://github.com/YTommy109/befold'

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
      '多彩なフォーマット対応',
      '.mmd, .md, .svg, .html, .csv, .tsv のレンダリング表示に加え、.png, .jpg, .gif, .webp, .pdf, ソースコード（50以上の言語）にも対応',
    ],
    en: [
      'Wide Format Support',
      'Renders .mmd, .md, .svg, .html, .csv, .tsv — plus displays .png, .jpg, .gif, .webp, .pdf, and source code in 50+ languages',
    ],
  },
  {
    ja: [
      'レンダリング / ソース切替',
      '⌘U でレンダリング表示とソース表示をワンタッチ切替。ソースはシンタックスハイライト付き',
    ],
    en: [
      'Rendered / Source Toggle',
      'Toggle between rendered and source view with ⌘U. Source view includes syntax highlighting',
    ],
  },
  {
    ja: ['ライブリロード', 'AI がファイルを書き換えると、その内容を即座にプレビューに反映'],
    en: ['Live Reload', 'Instantly reflects every change the AI makes to your files in the preview'],
  },
  {
    ja: [
      'タブ & セッション復元',
      'macOS ネイティブのタブ対応。前回のタブ構成は次回起動時に自動復元',
    ],
    en: [
      'Tabs & Session Restore',
      'Native macOS tab support. Previous tab layout is automatically restored on next launch',
    ],
  },
  {
    ja: ['ズーム & ダークモード', '⌘+/⌘-/⌘0 でズーム操作。macOS のダークモードに自動追従'],
    en: ['Zoom & Dark Mode', 'Zoom with ⌘+/⌘-/⌘0. Automatically follows macOS dark mode'],
  },
  {
    ja: ['アプリ内アップデート', '新しいバージョンが利用可能になると通知。ワンクリックで更新'],
    en: ['In-App Updates', 'Notifies when a new version is available. One-click update'],
  },
]

const SCREENSHOTS: { src: string; alt: string; caption: string; captionEn?: string }[] = [
  { src: '/images/screenshot-1.png', alt: 'Mermaid flowchart in befold', caption: 'Mermaid' },
  { src: '/images/screenshot-2.png', alt: 'SVG diagram rendering in befold', caption: 'SVG' },
  { src: '/images/screenshot-3.png', alt: 'Markdown preview in befold', caption: 'Markdown' },
  { src: '/images/screenshot-4.png', alt: 'CSV table view in befold', caption: 'CSV' },
  {
    src: '/images/screenshot-5.png',
    alt: 'Source code view in befold',
    caption: 'ソースコード',
    captionEn: 'Source Code',
  },
]

/** 配布 LP。ダウンロードは計測用の /download 経由にする。 */
export const Landing: FC = () => (
  <html lang="ja">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>befold — File Viewer for macOS</title>
      <meta
        name="description"
        content="befold is a lightweight file viewer for macOS that renders Mermaid diagrams, Markdown, SVG, HTML, CSV, and more with live reload."
      />
      <link rel="stylesheet" href="/style.css" />
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
            <h2>ファイルを開くだけ。即レンダリング。</h2>
            <p>Mermaid・Markdown・SVG・HTML・CSV など多彩なフォーマットをリアルタイムにプレビュー</p>
          </div>
          <div lang="en" hidden>
            <h2>Open a file. Instant rendering.</h2>
            <p>Live preview for Mermaid, Markdown, SVG, HTML, CSV, and many more formats</p>
          </div>
          <a href="/download" class="btn-primary">
            <span lang="ja">ダウンロード</span>
            <span lang="en" hidden>
              Download
            </span>
          </a>
        </section>

        <section class="philosophy">
          <div lang="ja">
            <p class="philosophy-lead">AI がコードを書く時代。</p>
            <p class="philosophy-body">
              開発者に必要なのは、もう一つのエディタではない。
              <br />
              読むことに集中できる、静かで快適なビューア。
              <br />
              befold はコードレビューを心地よくするために作られた。
            </p>
          </div>
          <div lang="en" hidden>
            <p class="philosophy-lead">In the age of AI-written code.</p>
            <p class="philosophy-body">
              What developers need isn't another editor.
              <br />
              It's a quiet, comfortable viewer for focused reading.
              <br />
              befold is built to make code review a pleasure.
            </p>
          </div>
        </section>

        <section class="screenshot">
          <div class="carousel">
            <div class="carousel-track">
              {SCREENSHOTS.map((shot, index) => (
                <div class="carousel-slide">
                  <img
                    src={shot.src}
                    alt={shot.alt}
                    {...(index === 0 ? {} : { loading: 'lazy' })}
                  />
                  <p class="carousel-caption">
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
                <a href="/download">ダウンロード</a>から <code>befold-vX.Y.Z.dmg</code> を取得
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
                <a href="/download">Download</a> <code>befold-vX.Y.Z.dmg</code>
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
