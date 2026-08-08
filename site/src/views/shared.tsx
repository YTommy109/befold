import type { FC } from 'hono/jsx'

/**
 * LP と詳細ページで共有する定数・断片。
 *
 * ここが唯一の定義箇所で、各ページ側に同じものを置き直さない。複製すると
 * 一方だけ直した状態がテストを通ってしまうため、構造として 1 箇所に寄せる。
 */

export const REPO_URL = 'https://github.com/YTommy109/befold'

/** ダウンロード導線は配布サイトの絶対 URL に揃える。 */
export const DOWNLOAD_URL = 'https://befold.tommy109.workers.dev/download'

/** 動作要件。LP・詳細ページ・JSON-LD で同じ表記を使う。 */
export const REQUIRED_OS = 'macOS 14 (Sonoma) or later'
export const REQUIRED_OS_JA = 'macOS 14 (Sonoma) 以降'

export const LANG_SCRIPT = `
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

export type Feature = { ja: [string, string]; en: [string, string] }

export const FEATURES: Feature[] = [
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
export const MORE_FEATURES: Feature[] = [
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

/** GitHub リボン + タイトル + 言語切替。全ページ共通。 */
export const SiteHeader: FC<{ title: string }> = ({ title }) => (
  <>
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
      <h1>{title}</h1>
      <div class="lang-switcher">
        <button class="lang-btn active" onclick="switchLang('ja')" type="button">
          🇯🇵
        </button>
        <button class="lang-btn" onclick="switchLang('en')" type="button">
          EN
        </button>
      </div>
    </header>
  </>
)

export const SiteFooter: FC = () => (
  <footer>
    <p>
      <a href={REPO_URL}>GitHub</a> · MIT License · © 2026{' '}
      <a href="https://github.com/YTommy109">Tommy109</a>
    </p>
  </footer>
)
