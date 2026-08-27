import type { FC } from 'hono/jsx'

import { FILE_TYPE_GROUPS, SIZE_LIMITS_MB, type RenderMode } from '../lib/file-types'
import { type PageLang, type SitePage } from '../lib/pages'
import { T, t, type Localized } from './i18n'
import { downloadHref, FEATURES, MORE_FEATURES, REQUIRED_OS } from './shared'
import { PageShell } from './shell'

const PAGE_TITLE: Localized = {
  ja: '機能と対応ファイルタイプ — befold',
  en: 'Features & Supported File Types — befold',
}

const PAGE_DESCRIPTION: Localized = {
  ja: 'Mermaid・Markdown・SVG・HTML・CSV/TSV・画像・PDF・ソースコードを読める macOS 向けビューア befold の全機能。対応する拡張子の一覧、キーボードショートカット、よくある質問への回答をまとめています。',
  en: 'Every feature of befold, the macOS viewer for Mermaid, Markdown, SVG, HTML, CSV/TSV, images, PDF and source code: the full table of supported file extensions, keyboard shortcuts and answers to common questions.',
}

const RENDER_MODE_LABEL: Record<RenderMode, Localized> = {
  both: { ja: 'レンダリング / ソース', en: 'Rendered / Source' },
  'rendered-only': { ja: 'レンダリングのみ', en: 'Rendered only' },
  'source-only': { ja: 'ソースのみ', en: 'Source only' },
}

/**
 * キーボードショートカット。macOS 標準の編集系（⌘C・⌘Q など）は載せず、
 * befold の操作に関わるものを載せる。
 *
 * 実装（MainMenuBuilder*.swift）とのずれは test/shortcuts.test.ts が検知する。
 */
export const SHORTCUTS: { keys: string; ja: string; en: string }[] = [
  { keys: '⌘O', ja: 'ファイル / フォルダを開く', en: 'Open a file or folder' },
  {
    keys: '⌘P',
    ja: 'Quick Open（ファイル名のあいまい検索）',
    en: 'Quick Open (fuzzy filename search)',
  },
  { keys: '⌘S', ja: 'サイドバーの表示 / 非表示', en: 'Show or hide the sidebar' },
  {
    keys: '⌘[ / ⌘]',
    ja: '前 / 次に読んだファイルへ',
    en: 'Go to the previously / next viewed file',
  },
  {
    keys: '⌘U',
    ja: 'レンダリング表示とソース表示の切替',
    en: 'Toggle between rendered and source view',
  },
  {
    keys: '⌘1 / ⌘2 / ⌘3',
    ja: '表示モードの切替（レンダリング / ソース / 差分）',
    en: 'Switch the display mode (rendered / source / diff)',
  },
  {
    keys: '⌘\\',
    ja: '差分レイアウトの上下・左右切替',
    en: 'Toggle the diff layout between stacked and side by side',
  },
  { keys: '⌘L', ja: 'ソース表示の行番号', en: 'Toggle line numbers in source view' },
  { keys: '⌘D', ja: 'ブックマークの追加 / 解除', en: 'Add or remove a bookmark' },
  { keys: '⌘F / ⌘G', ja: 'ページ内検索 / 次を検索', en: 'Find in page / find next' },
  { keys: '⌘0 / ⌘+ / ⌘-', ja: '実寸 / 拡大 / 縮小', en: 'Actual size / zoom in / zoom out' },
  { keys: '⌃⌘H', ja: '隠しファイルの表示', en: 'Show hidden files' },
  { keys: '⌃⌘G', ja: '変更されたファイルのみ表示', en: 'Show changed files only' },
  { keys: '⌃⌘T', ja: 'サイドバーのツリー表示切替', en: 'Toggle the sidebar tree view' },
  { keys: '⌃⌘F', ja: 'フルスクリーン', en: 'Enter full screen' },
  { keys: '⌘W', ja: 'ウィンドウを閉じる', en: 'Close the window' },
]

type FaqItem = {
  question: { ja: string; en: string }
  answer: { ja: string; en: string }
}

/**
 * FAQ。JSON-LD には英語の文面をそのまま載せる（構造化データの内容は
 * ページ上に見えている必要があるため、本文と同じ文字列を使う）。
 */
export const FAQ: FaqItem[] = [
  {
    question: {
      ja: 'Windows 版や Linux 版はありますか？',
      en: 'Is there a Windows or Linux version?',
    },
    answer: {
      ja: `ありません。befold は macOS 専用のアプリで、${REQUIRED_OS.ja} が必要です。`,
      en: `No. befold is a macOS-only app and requires ${REQUIRED_OS.en}.`,
    },
  },
  {
    question: { ja: '有料ですか？', en: 'Does befold cost anything?' },
    answer: {
      ja: '無料です。MIT ライセンスのオープンソースで、ソースコードは GitHub で公開しています。',
      en: 'No. befold is free and open source under the MIT license, and the source is published on GitHub.',
    },
  },
  {
    question: {
      ja: '開いたファイルの内容が外部へ送られることはありますか？',
      en: 'Does befold send the files I open anywhere?',
    },
    answer: {
      ja: 'ありません。描画はすべて手元で行い、文書の中身・ファイル名・パスを送信する経路はありません。アプリが出す通信はアップデート確認だけです。逆方向も塞いでいて、開いた文書に埋め込まれたリモート画像・トラッキング用の画像・外部スクリプトはネットワーク層で遮断されるため読み込まれません。開いた HTML 内のスクリプトも実行しません。',
      en: 'No. Everything is rendered locally, and there is no path that sends document contents, file names or paths anywhere; the only request befold makes is the update check. The reverse direction is blocked too: remote images, tracking pixels and external scripts embedded in a file are stopped at the network layer, and scripts inside an opened HTML file do not run.',
    },
  },
  {
    question: { ja: 'ファイルを編集できますか？', en: 'Can I edit files in befold?' },
    answer: {
      ja: 'いいえ。befold は閲覧専用のビューアです。編集は普段のエディタで行い、befold は変更を監視して即座に表示へ反映します。',
      en: 'No. befold is a read-only viewer. You edit in your usual editor, and befold watches the file and reflects each change immediately.',
    },
  },
  {
    question: {
      ja: 'どれくらい大きなファイルを開けますか？',
      en: 'How large a file can befold open?',
    },
    answer: {
      ja: `Markdown・CSV/TSV・ソースコードは分割して読み込むため最大 ${SIZE_LIMITS_MB.chunkable}MB まで開けます。全体を一度に組み立てる Mermaid・SVG・HTML は ${SIZE_LIMITS_MB.nonChunkableText}MB、画像と PDF は ${SIZE_LIMITS_MB.binary}MB が上限です。`,
      en: `Markdown, CSV/TSV and source code load in chunks, so they open up to ${SIZE_LIMITS_MB.chunkable}MB. Mermaid, SVG and HTML are built in one pass and are limited to ${SIZE_LIMITS_MB.nonChunkableText}MB; images and PDFs to ${SIZE_LIMITS_MB.binary}MB.`,
    },
  },
  {
    question: {
      ja: '表にない拡張子のファイルは開けますか？',
      en: 'What happens with an extension that is not in the table?',
    },
    answer: {
      ja: 'プレーンテキストとして開きます。表は「拡張子から種別を判定するもの」の一覧で、開けるファイルの全部ではありません。',
      en: 'It opens as plain text. The table lists the extensions befold recognises as a specific type — not the only files it can open.',
    },
  },
  {
    question: {
      ja: 'Finder から直接プレビューできますか？',
      en: 'Can I preview from Finder without opening the app?',
    },
    answer: {
      ja: 'できます。QuickLook 拡張を同梱しているので、Finder でファイルを選んでスペースキーを押すと Mermaid や Markdown がレンダリングされた状態で表示されます。',
      en: 'Yes. befold ships a QuickLook extension, so selecting a file in Finder and pressing space shows Mermaid or Markdown already rendered.',
    },
  },
  {
    question: { ja: 'ターミナルから開けますか？', en: 'Can I open files from the terminal?' },
    answer: {
      ja: 'できます。同梱の befold コマンドに複数のパスを渡すとまとめて開きます。--sidebar / --source / --line-numbers で開いた直後の表示も指定できます。',
      en: 'Yes. Pass one or more paths to the bundled befold command to open them all at once, and use --sidebar, --source or --line-numbers to choose how they open.',
    },
  },
]

/**
 * FAQPage の構造化データ。**本文に見えている文面と同じものを載せる。**
 *
 * 言語ごとに URL が分かれた（TASK-496）ので、ページの言語に合わせて選ぶ。
 * 以前は日英を同じ HTML に入れていたため英語固定でよかったが、いまは日本語ページに
 * 英語の本文が存在しないため、英語固定にすると構造化データが本文に存在しない
 * 文面を主張することになる。
 */
function faqStructuredData(lang: PageLang): string {
  return JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: FAQ.map((item) => ({
      '@type': 'Question',
      name: t(lang, item.question),
      acceptedAnswer: { '@type': 'Answer', text: t(lang, item.answer) },
    })),
  })
}

/**
 * 機能と対応ファイルタイプの詳細ページ。
 *
 * LP はダウンロードへの導線に絞り、網羅的な記述はこちらへ置く。
 * 対応ファイルタイプ表は FILE_TYPE_GROUPS だけを情報源にし、拡張子とサイズ上限が
 * BefoldKit の実装とずれたら test/file-types.test.ts が落ちる。
 */
export const Features: FC<{ origin: string; entry: SitePage }> = ({ origin, entry }) => {
  const lang = entry.lang

  return (
    <PageShell
      origin={origin}
      entry={entry}
      title={t(lang, PAGE_TITLE)}
      description={t(lang, PAGE_DESCRIPTION)}
      ogType="article"
      jsonLd={faqStructuredData(lang)}
    >
      <main>
        <section class="page-intro">
          {lang === 'ja' ? (
            <>
              <h2>機能と対応ファイルタイプ</h2>
              <p>
                befold は Mermaid・Markdown・SVG・HTML・CSV/TSV・画像・PDF・ソースコードを
                プレビューする macOS 専用のビューアです。このページでは全機能、対応する
                拡張子の一覧、キーボードショートカット、よくある質問をまとめています。
              </p>
            </>
          ) : (
            <>
              <h2>Features &amp; Supported File Types</h2>
              <p>
                befold is a macOS-only viewer for Mermaid, Markdown, SVG, HTML, CSV/TSV, images, PDF
                and source code. This page lists every feature, the full table of supported
                extensions, the keyboard shortcuts and answers to common questions.
              </p>
            </>
          )}
        </section>

        <section class="features">
          <h3>
            <T lang={lang} ja="機能" en="Features" />
          </h3>
          <dl class="feature-defs">
            {[...FEATURES, ...MORE_FEATURES].map((feature) => (
              <>
                <dt>
                  <T lang={lang} ja={feature.ja[0]} en={feature.en[0]} />
                </dt>
                <dd>
                  <T lang={lang} ja={feature.ja[1]} en={feature.en[1]} />
                </dd>
              </>
            ))}
          </dl>
        </section>

        <section class="file-types">
          <h3>
            <T lang={lang} ja="対応ファイルタイプ" en="Supported File Types" />
          </h3>
          <div class="table-scroll">
            <table class="file-type-table">
              <thead>
                <tr>
                  <th>
                    <T lang={lang} ja="種別" en="Type" />
                  </th>
                  <th>
                    <T lang={lang} ja="拡張子" en="Extensions" />
                  </th>
                  <th>
                    <T lang={lang} ja="表示" en="View" />
                  </th>
                  <th>
                    <T lang={lang} ja="上限" en="Max size" />
                  </th>
                </tr>
              </thead>
              <tbody>
                {FILE_TYPE_GROUPS.map((group) => (
                  <tr>
                    <th scope="row">{group.label}</th>
                    <td class="extensions">
                      {group.extensions.map((extension) => `.${extension}`).join(' ')}
                      <p>{t(lang, group.note)}</p>
                    </td>
                    <td>{t(lang, RENDER_MODE_LABEL[group.renderMode])}</td>
                    <td>{group.maxSizeMB}MB</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p>
            <T
              lang={lang}
              ja="この表にない拡張子のファイルは、プレーンテキストとして開きます。文字コードは UTF-8/16/32・Shift_JIS・EUC-JP を自動判別します。"
              en="Any other extension opens as plain text. Character encodings UTF-8/16/32, Shift_JIS and EUC-JP are detected automatically."
            />
          </p>
        </section>

        <section class="shortcuts">
          <h3>
            <T lang={lang} ja="キーボードショートカット" en="Keyboard Shortcuts" />
          </h3>
          <div class="table-scroll">
            <table class="shortcut-table">
              <tbody>
                {SHORTCUTS.map((shortcut) => (
                  <tr>
                    <th scope="row">
                      <kbd>{shortcut.keys}</kbd>
                    </th>
                    <td>
                      <T lang={lang} ja={shortcut.ja} en={shortcut.en} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <section class="faq">
          <h3>
            <T lang={lang} ja="よくある質問" en="Frequently Asked Questions" />
          </h3>
          {FAQ.map((item) => (
            <div class="faq-item">
              <h4>{t(lang, item.question)}</h4>
              <p>{t(lang, item.answer)}</p>
            </div>
          ))}
        </section>

        <section class="requirements">
          <h3>
            <T lang={lang} ja="動作要件" en="Requirements" />
          </h3>
          <p>{t(lang, REQUIRED_OS)}</p>
          <a href={downloadHref('/features')} class="btn-primary">
            <T lang={lang} ja="Mac 版をダウンロード" en="Download for Mac" />
          </a>
        </section>
      </main>
    </PageShell>
  )
}
