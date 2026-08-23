import type { FC } from 'hono/jsx'

import { navPagesFor, variantsOf, type FixedPage, type PageLang, type SitePage } from '../lib/pages'
import { t, type Localized } from './i18n'

/**
 * LP と詳細ページで共有する定数・断片。
 *
 * ここが唯一の定義箇所で、各ページ側に同じものを置き直さない。複製すると
 * 一方だけ直した状態がテストを通ってしまうため、構造として 1 箇所に寄せる。
 */

export const REPO_URL = 'https://github.com/YTommy109/befold'

/**
 * ダウンロード導線のパス。**絶対 URL にしない**（ADR 0007 の決定 6）。
 *
 * `<a href="/download">` はブラウザが表示中の文書のオリジンに対して解決するため、
 * 相対パスにするだけで「いま開いているホストの /download」になる。配布サイトは
 * 独自ドメインと workers.dev の両方で応答し、staging も別ホストなので、正規
 * オリジンを固定すると staging の LP のダウンロードボタンが本番を指し、staging で
 * download 経路と `source:'lp'` の計測を確かめられなくなる。
 *
 * 絶対 URL が要る箇所（JSON-LD の downloadUrl）は、canonical・og:url・sitemap と
 * 同じくリクエスト origin から組む。
 */
export const DOWNLOAD_PATH = '/download'

/** 動作要件。LP・詳細ページ・JSON-LD で同じ表記を使う。 */
export const REQUIRED_OS: Localized = {
  ja: 'macOS 14 (Sonoma) 以降',
  en: 'macOS 14 (Sonoma) or later',
}

/**
 * 言語切替に使っていた `localStorage` の掃除（TASK-496）。
 *
 * 言語は URL が持つようになったので `befold-lang` は読まなくなった。読み手を
 * 消すだけだと値はブラウザに残り続け、次に同名のキーを使ったときに誤って
 * 読まれる（`.claude/CLAUDE.md`「UserDefaults キーの廃止・改名」と同型の問題）。
 * 1 行だけ残して消す。
 */
export const CLEANUP_SCRIPT = `try { localStorage.removeItem('befold-lang'); } catch (e) {}`

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
      'Git 差分表示',
      'ブランチで加えた変更を、コミット済みの分までまとめてソースの差分で読める。レンダリング / ソース / 差分の切替は ⌘1 / ⌘2 / ⌘3、差分の上下・左右レイアウトは ⌘\\ で。表示モードはファイルごとに記憶される',
    ],
    en: [
      'Git Diff View',
      'Read what your branch changes — committed work included — as a source diff. Switch rendered / source / diff with ⌘1 / ⌘2 / ⌘3, flip the diff layout between stacked and side by side with ⌘\\. The view mode is remembered per file',
    ],
  },
  {
    ja: [
      '変更ファイルがわかるサイドバー',
      '変更のあったファイルに 1 文字と色のバッジが付き、フォルダーには配下の変更が集約される。ステージ済み・未ステージ・未追跡・ブランチでコミット済みを見分けられ、⌃⌘G で変更ファイルだけに絞り込める',
    ],
    en: [
      'A Sidebar That Knows Your Changes',
      'Changed files carry a one-letter colored badge, and folders roll up the changes beneath them. Staged, unstaged, untracked and committed-on-branch are told apart, and ⌃⌘G narrows the list to changed files only',
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
      '最近使ったリポジトリ',
      'ファイルメニューから最近開いたリポジトリを、当時のタブ構成ごと開き直せる。worktree は本体リポジトリの下にまとまって並ぶ',
    ],
    en: [
      'Recent Repositories',
      'Reopen a recently used repository from the File menu, tabs and all. Worktrees are grouped under their main repository',
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

/**
 * GitHub リボン + タイトル + ページナビ + 言語切替。全ページ共通。
 *
 * 言語切替は `<a>` で、宛先は同じ論理ページの各バリアント（`variantsOf`）。
 * 以前は `<button onclick>` で DOM の `hidden` を付け替えていたが、その形だと
 * 表示言語が URL に現れず、hreflang も出せなかった。現在地は `aria-current` で
 * 示す——テキスト内容の比較で active を決めていた旧実装（絵文字との一致を見て
 * いた）は、表記を変えると黙って壊れる形だった。
 */
export const SiteHeader: FC<{ title: string; entry: SitePage }> = ({ title, entry }) => (
  <>
    <a
      class="github-ribbon"
      href={REPO_URL}
      target="_blank"
      rel="noopener"
      aria-label={t(entry.lang, { ja: 'GitHub でソースを見る', en: 'View source on GitHub' })}
    >
      <span>GitHub</span>
    </a>

    <header>
      <h1>{title}</h1>
      <SiteNav entry={entry} />
      <nav class="lang-switcher" aria-label={t(entry.lang, { ja: '言語', en: 'Language' })}>
        {variantsOf(entry.page).map((variant) => (
          <a
            class="lang-btn"
            href={variant.path}
            hreflang={variant.lang}
            lang={variant.lang}
            {...(variant.lang === entry.lang ? { 'aria-current': 'page' } : {})}
          >
            {LANG_LABEL[variant.lang]}
          </a>
        ))}
      </nav>
    </header>
  </>
)

/**
 * ヘッダーのページナビ。項目は `navPagesFor` が返す固定ページで、パスは
 * `SITE_PAGES` から引く（`pathFor` と同じ表）。ここにパスを書き写さない。
 *
 * ラベルは `Record<FixedPage, Localized>` なので、固定ページを足したときに
 * ラベルの付け忘れが型で落ちる。
 *
 * 現在地は言語切替と同じく `aria-current="page"` で示す。記事ページはナビに
 * 項目を持たないため、どれも current にならない——記事から一覧へ戻る動線は
 * パンくず（`article.tsx`）が持っている。
 */
const SiteNav: FC<{ entry: SitePage }> = ({ entry }) => (
  <nav class="site-nav" aria-label={t(entry.lang, { ja: 'サイト内', en: 'Site' })}>
    {navPagesFor(entry.lang).map((item) => (
      <a
        class="site-nav-link"
        href={item.path}
        {...(item.page === entry.page ? { 'aria-current': 'page' } : {})}
      >
        {t(entry.lang, NAV_LABEL[item.page])}
      </a>
    ))}
  </nav>
)

/** ナビ項目の表記。固定ページを足したらここもコンパイルエラーになる。 */
const NAV_LABEL: Record<FixedPage, Localized> = {
  '/': { ja: 'ホーム', en: 'Home' },
  '/features': { ja: '機能', en: 'Features' },
  '/releases': { ja: 'リリース', en: 'Releases' },
  '/usecases': { ja: '事例', en: 'Use cases' },
}

/** 言語切替ボタンの表記。日本語は国旗、英語は EN。 */
const LANG_LABEL: Record<PageLang, string> = { ja: '\u{1F1EF}\u{1F1F5}', en: 'EN' }

export const SiteFooter: FC = () => (
  <footer>
    <p>
      <a href={REPO_URL}>GitHub</a> · MIT License · © 2026{' '}
      <a href="https://www.degino.com">Degino Inc.</a>
    </p>
  </footer>
)
