import type { Localized } from './i18n'

/** kind: 'feature' はファイル形式ではなく機能の紹介なので、キャプションにラベルを添える。 */
export const SCREENSHOTS: {
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
  {
    src: '/images/screenshot-10.png',
    alt: {
      ja: 'befold のサイドバーで git の比較基準を切り替えるメニュー',
      en: 'Menu in the befold sidebar for switching the git comparison target',
    },
    caption: 'Comparison Target',
    kind: 'feature',
  },
  {
    src: '/images/screenshot-11.png',
    alt: {
      ja: 'befold で PDF の中を検索し、一致した語を強調している画面',
      en: 'Searching inside a PDF in befold with the matches highlighted',
    },
    caption: 'PDF Search',
    kind: 'feature',
  },
  {
    src: '/images/screenshot-9.png',
    alt: {
      ja: 'befold のスライドモードで全面表示した HTML スライド',
      en: 'An HTML slide shown full-window in befold slide mode',
    },
    caption: 'Slide Mode',
    kind: 'feature',
  },
]
