import type { FC } from 'hono/jsx'
import { html, raw } from 'hono/html'
import { FILE_TYPE_GROUPS, SIZE_LIMITS_MB, type RenderMode } from '../lib/file-types'
import {
  DOWNLOAD_URL,
  FEATURES,
  MORE_FEATURES,
  LANG_SCRIPT,
  REPO_URL,
  REQUIRED_OS,
  REQUIRED_OS_JA,
  SiteFooter,
  SiteHeader,
} from './shared'

const PAGE_TITLE = 'Features & Supported File Types — befold'
const PAGE_DESCRIPTION =
  'Every feature of befold, the macOS viewer for Mermaid, Markdown, SVG, HTML, CSV/TSV, images, PDF and source code: the full table of supported file extensions, keyboard shortcuts and answers to common questions.'

const RENDER_MODE_LABEL: Record<RenderMode, { ja: string; en: string }> = {
  both: { ja: 'レンダリング / ソース', en: 'Rendered / Source' },
  'rendered-only': { ja: 'レンダリングのみ', en: 'Rendered only' },
  'source-only': { ja: 'ソースのみ', en: 'Source only' },
}

/**
 * キーボードショートカット。stable ビルドで必ず存在するものだけを載せる。
 *
 * 表示モードの ⌘1〜⌘4 はフィーチャーゲートで項目数が変わる（MainMenuBuilder の
 * `addDisplayModeItems`）ため、確定するまでここには書かない。
 * 実装とのずれ検知は TASK-384 で入れる。
 */
export const SHORTCUTS: { keys: string; ja: string; en: string }[] = [
  { keys: '⌘O', ja: 'ファイル / フォルダを開く', en: 'Open a file or folder' },
  { keys: '⌘P', ja: 'Quick Open（ファイル名のあいまい検索）', en: 'Quick Open (fuzzy filename search)' },
  { keys: '⌘S', ja: 'サイドバーの表示 / 非表示', en: 'Show or hide the sidebar' },
  { keys: '⌘[ / ⌘]', ja: '前 / 次に読んだファイルへ', en: 'Go to the previously / next viewed file' },
  { keys: '⌘U', ja: 'レンダリング表示とソース表示の切替', en: 'Toggle between rendered and source view' },
  { keys: '⌘L', ja: 'ソース表示の行番号', en: 'Toggle line numbers in source view' },
  { keys: '⌘D', ja: 'ブックマークの追加 / 解除', en: 'Add or remove a bookmark' },
  { keys: '⌘F / ⌘G', ja: 'ページ内検索 / 次を検索', en: 'Find in page / find next' },
  { keys: '⌘0 / ⌘+ / ⌘-', ja: '実寸 / 拡大 / 縮小', en: 'Actual size / zoom in / zoom out' },
  { keys: '⌃⌘H', ja: '隠しファイルの表示', en: 'Show hidden files' },
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
      ja: `ありません。befold は macOS 専用のアプリで、${REQUIRED_OS_JA} が必要です。`,
      en: `No. befold is a macOS-only app and requires ${REQUIRED_OS}.`,
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

/** FAQPage の構造化データ。本文に見えている英語の文面と同じものを載せる。 */
function faqStructuredData(): string {
  return JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: FAQ.map((item) => ({
      '@type': 'Question',
      name: item.question.en,
      acceptedAnswer: { '@type': 'Answer', text: item.answer.en },
    })),
  })
}

const Bilingual: FC<{ ja: string; en: string; tag?: 'p' | 'span' }> = ({ ja, en, tag }) => {
  const Tag = tag ?? 'p'
  return (
    <>
      <Tag lang="ja">{ja}</Tag>
      <Tag lang="en" hidden>
        {en}
      </Tag>
    </>
  )
}

/**
 * 機能と対応ファイルタイプの詳細ページ。
 *
 * LP はダウンロードへの導線に絞り、網羅的な記述はこちらへ置く。
 * 対応ファイルタイプ表は FILE_TYPE_GROUPS だけを情報源にし、拡張子とサイズ上限が
 * BefoldKit の実装とずれたら test/file-types.test.ts が落ちる。
 */
export const Features: FC<{ origin: string }> = ({ origin }) => (
  <html lang="ja">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>{PAGE_TITLE}</title>
      <meta name="description" content={PAGE_DESCRIPTION} />
      <link rel="canonical" href={`${origin}/features`} />
      <meta property="og:type" content="article" />
      <meta property="og:site_name" content="befold" />
      <meta property="og:title" content={PAGE_TITLE} />
      <meta property="og:description" content={PAGE_DESCRIPTION} />
      <meta property="og:url" content={`${origin}/features`} />
      <meta property="og:image" content={`${origin}/images/ogp.png`} />
      <meta property="og:image:width" content="1200" />
      <meta property="og:image:height" content="630" />
      <meta name="twitter:card" content="summary_large_image" />
      <link rel="stylesheet" href="/style.css" />
      {html`<script type="application/ld+json">
        ${raw(faqStructuredData())}
      </script>`}
    </head>
    <body>
      <SiteHeader title="befold" />

      <main>
        <nav class="breadcrumb">
          <a href="/">
            <span lang="ja">← トップページへ戻る</span>
            <span lang="en" hidden>
              ← Back to the home page
            </span>
          </a>
        </nav>

        <section class="page-intro">
          <div lang="ja">
            <h2>機能と対応ファイルタイプ</h2>
            <p>
              befold は Mermaid・Markdown・SVG・HTML・CSV/TSV・画像・PDF・ソースコードを
              プレビューする macOS 専用のビューアです。このページでは全機能、対応する
              拡張子の一覧、キーボードショートカット、よくある質問をまとめています。
            </p>
          </div>
          <div lang="en" hidden>
            <h2>Features & Supported File Types</h2>
            <p>
              befold is a macOS-only viewer for Mermaid, Markdown, SVG, HTML, CSV/TSV, images,
              PDF and source code. This page lists every feature, the full table of supported
              extensions, the keyboard shortcuts and answers to common questions.
            </p>
          </div>
        </section>

        <section class="features">
          <div lang="ja">
            <h3>機能</h3>
          </div>
          <div lang="en" hidden>
            <h3>Features</h3>
          </div>
          <dl class="feature-defs">
            {[...FEATURES, ...MORE_FEATURES].map((feature) => (
              <>
                <dt lang="ja">{feature.ja[0]}</dt>
                <dd lang="ja">{feature.ja[1]}</dd>
                <dt lang="en" hidden>
                  {feature.en[0]}
                </dt>
                <dd lang="en" hidden>
                  {feature.en[1]}
                </dd>
              </>
            ))}
          </dl>
        </section>

        <section class="file-types">
          <div lang="ja">
            <h3>対応ファイルタイプ</h3>
          </div>
          <div lang="en" hidden>
            <h3>Supported File Types</h3>
          </div>
          <div class="table-scroll">
            <table class="file-type-table">
              <thead>
                <tr>
                  <th>
                    <span lang="ja">種別</span>
                    <span lang="en" hidden>
                      Type
                    </span>
                  </th>
                  <th>
                    <span lang="ja">拡張子</span>
                    <span lang="en" hidden>
                      Extensions
                    </span>
                  </th>
                  <th>
                    <span lang="ja">表示</span>
                    <span lang="en" hidden>
                      View
                    </span>
                  </th>
                  <th>
                    <span lang="ja">上限</span>
                    <span lang="en" hidden>
                      Max size
                    </span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {FILE_TYPE_GROUPS.map((group) => (
                  <tr>
                    <th scope="row">{group.label}</th>
                    <td class="extensions">
                      {group.extensions.map((extension) => `.${extension}`).join(' ')}
                      <Bilingual ja={group.note.ja} en={group.note.en} />
                    </td>
                    <td>
                      <span lang="ja">{RENDER_MODE_LABEL[group.renderMode].ja}</span>
                      <span lang="en" hidden>
                        {RENDER_MODE_LABEL[group.renderMode].en}
                      </span>
                    </td>
                    <td>{group.maxSizeMB}MB</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Bilingual
            ja="この表にない拡張子のファイルは、プレーンテキストとして開きます。文字コードは UTF-8/16/32・Shift_JIS・EUC-JP を自動判別します。"
            en="Any other extension opens as plain text. Character encodings UTF-8/16/32, Shift_JIS and EUC-JP are detected automatically."
          />
        </section>

        <section class="shortcuts">
          <div lang="ja">
            <h3>キーボードショートカット</h3>
          </div>
          <div lang="en" hidden>
            <h3>Keyboard Shortcuts</h3>
          </div>
          <div class="table-scroll">
            <table class="shortcut-table">
              <tbody>
                {SHORTCUTS.map((shortcut) => (
                  <tr>
                    <th scope="row">
                      <kbd>{shortcut.keys}</kbd>
                    </th>
                    <td>
                      <span lang="ja">{shortcut.ja}</span>
                      <span lang="en" hidden>
                        {shortcut.en}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <section class="faq">
          <div lang="ja">
            <h3>よくある質問</h3>
          </div>
          <div lang="en" hidden>
            <h3>Frequently Asked Questions</h3>
          </div>
          {FAQ.map((item) => (
            <div class="faq-item">
              <h4 lang="ja">{item.question.ja}</h4>
              <p lang="ja">{item.answer.ja}</p>
              <h4 lang="en" hidden>
                {item.question.en}
              </h4>
              <p lang="en" hidden>
                {item.answer.en}
              </p>
            </div>
          ))}
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
          <a href={DOWNLOAD_URL} class="btn-primary">
            <span lang="ja">Mac 版をダウンロード</span>
            <span lang="en" hidden>
              Download for Mac
            </span>
          </a>
          <p class="hero-note">
            <a href={REPO_URL}>GitHub</a>
          </p>
        </section>
      </main>

      <SiteFooter />

      {html`<script>
        ${raw(LANG_SCRIPT)}
      </script>`}
    </body>
  </html>
)
