/**
 * 詳細ページの「対応ファイルタイプ」表と、その内容が実装とずれていないかを
 * 検証するためのパーサ。
 *
 * 拡張子の単一情報源は Swift 側の `FileType.typeByExtension`
 * （BefoldApp/BefoldKit/FileType.swift）であって、この表ではない。
 * ここに書いた一覧は表示用の並び・ラベルを与えるだけで、拡張子の集合が
 * Swift 側とずれたら test/file-types.test.ts が落ちる。
 */

/** 表示方法。`FileType.isRenderable` / `supportsSourceMode` に対応する。 */
export type RenderMode = 'both' | 'rendered-only' | 'source-only'

export type FileTypeGroup = {
  /** 種別名（言語非依存の表記なので日英で共通）。 */
  label: string
  /** この種別として判定される拡張子。ドットは含めない。 */
  extensions: string[]
  renderMode: RenderMode
  /** チャンク読み込みで段階的に開けるか（`FileType.isChunkable`）。 */
  chunkable: boolean
  /** 開けるファイルサイズの上限（MB）。`SIZE_LIMITS_MB` のいずれか。 */
  maxSizeMB: number
  note: { ja: string; en: string }
}

/**
 * 表示できるファイルサイズの上限（MB）。3 つの経路で上限が違う。
 *
 * - chunkable: 行/ブロック単位で分割読み込みできる形式（NormalizedTextCache.maxFileSizeBytes）
 * - nonChunkableText: 全量を一括で DOM 化する形式（ContentLoader.maxTextFileSizeBytes）
 * - binary: 画像・PDF（ContentLoader.maxFileSizeBytes）
 *
 * 値がずれたら test/file-types.test.ts が落ちる。
 */
export const SIZE_LIMITS_MB = {
  chunkable: 100,
  nonChunkableText: 10,
  binary: 50,
} as const

/**
 * highlight.js の言語名ごとにまとめず、拡張子だけを列挙する。
 * 言語名は viewer 側の内部表現であって、ページの読者に意味を持たないため。
 */
const CODE_EXTENSIONS = [
  'bash',
  'c',
  'cc',
  'cjs',
  'cpp',
  'cs',
  'css',
  'cxx',
  'diff',
  'go',
  'gql',
  'graphql',
  'h',
  'hpp',
  'ini',
  'java',
  'js',
  'json',
  'jsonc',
  'jsx',
  'kt',
  'kts',
  'less',
  'lua',
  'm',
  'mjs',
  'mk',
  'mm',
  'patch',
  'php',
  'pl',
  'plist',
  'pm',
  'py',
  'r',
  'rb',
  'rs',
  'scss',
  'sh',
  'sql',
  'swift',
  'toml',
  'ts',
  'tsx',
  'vb',
  'xml',
  'yaml',
  'yml',
  'zsh',
]

export const FILE_TYPE_GROUPS: FileTypeGroup[] = [
  {
    label: 'Mermaid',
    extensions: ['mmd', 'mermaid'],
    renderMode: 'both',
    chunkable: false,
    maxSizeMB: SIZE_LIMITS_MB.nonChunkableText,
    note: {
      ja: 'フローチャート・シーケンス図・ガント図などを図として描画します。',
      en: 'Renders flowcharts, sequence diagrams, Gantt charts and more as diagrams.',
    },
  },
  {
    label: 'Markdown',
    extensions: ['md', 'markdown'],
    renderMode: 'both',
    chunkable: true,
    maxSizeMB: SIZE_LIMITS_MB.chunkable,
    note: {
      ja: 'コードブロック内の Mermaid も図として描画します。GitHub と同じ見た目のスタイルです。',
      en: 'Mermaid inside code blocks is rendered as a diagram too, in GitHub-like styling.',
    },
  },
  {
    label: 'SVG',
    extensions: ['svg'],
    renderMode: 'both',
    chunkable: false,
    maxSizeMB: SIZE_LIMITS_MB.nonChunkableText,
    note: {
      ja: '画像として表示し、ソース表示に切り替えると XML を読めます。',
      en: 'Shown as an image; switch to source view to read the XML.',
    },
  },
  {
    label: 'HTML',
    extensions: ['html', 'htm'],
    renderMode: 'both',
    chunkable: false,
    maxSizeMB: SIZE_LIMITS_MB.nonChunkableText,
    note: {
      ja: 'レンダリング結果とソースを切り替えて確認できます。',
      en: 'Switch between the rendered result and the source.',
    },
  },
  {
    label: 'CSV / TSV',
    extensions: ['csv', 'tsv'],
    renderMode: 'both',
    chunkable: true,
    maxSizeMB: SIZE_LIMITS_MB.chunkable,
    note: {
      ja: '表として整形して表示します。大きなファイルは分割して読み込みます。',
      en: 'Formatted as a table. Large files load in chunks.',
    },
  },
  {
    label: 'Image',
    extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico'],
    renderMode: 'rendered-only',
    chunkable: false,
    maxSizeMB: SIZE_LIMITS_MB.binary,
    note: {
      ja: 'ズームに追従して表示します。テキストのソースを持たないためソース表示はありません。',
      en: 'Displayed with zoom support. There is no source view, since there is no text source.',
    },
  },
  {
    label: 'PDF',
    extensions: ['pdf'],
    renderMode: 'rendered-only',
    chunkable: false,
    maxSizeMB: SIZE_LIMITS_MB.binary,
    note: {
      ja: 'ページを連続してスクロール表示します。',
      en: 'Pages are shown in a continuous scroll.',
    },
  },
  {
    label: 'Source code',
    extensions: CODE_EXTENSIONS,
    renderMode: 'source-only',
    chunkable: true,
    maxSizeMB: SIZE_LIMITS_MB.chunkable,
    note: {
      ja: 'シンタックスハイライトと行番号（⌘L）付きで表示します。分割読み込みに対応します。',
      en: 'Shown with syntax highlighting and line numbers (⌘L). Loads in chunks.',
    },
  },
]

/** 表に載る全拡張子。 */
export function allTableExtensions(): Set<string> {
  return new Set(FILE_TYPE_GROUPS.flatMap((group) => group.extensions))
}

/**
 * FileType.swift の `public static let` 宣言のうち、拡張子リテラルを持つものを
 * 総当たりで拾う。
 *
 * 既知の定数名を決め打ちで読むと、Swift 側に新しい拡張子グループが増えたときに
 * **黙って取りこぼしたまま検証が通ってしまう**。そのため宣言名を列挙して返し、
 * 名前の集合そのものをテストで突き合わせられるようにする。
 */
export type ParsedFileTypeSource = {
  /** 拡張子リテラルを持つ宣言。値は拡張子（辞書なら key）の集合。 */
  literalGroups: Map<string, Set<string>>
  /** enum 内の `public static let` 宣言名（リテラル以外も含む全件）。 */
  declarationNames: string[]
}

export function parseSwiftFileTypes(source: string): ParsedFileTypeSource {
  const literalGroups = new Map<string, Set<string>>()
  const declarationNames: string[] = []

  const declaration = /public static let ([A-Za-z0-9_]+)\s*(?::[^=]+)?=\s*/gu
  for (const match of source.matchAll(declaration)) {
    const name = match[1]
    if (name === undefined) continue
    declarationNames.push(name)

    const extensions = readBracketLiteral(source, match.index + match[0].length)
    if (extensions !== null) literalGroups.set(name, extensions)
  }

  return { literalGroups, declarationNames }
}

/** `pattern` の 1 番目のキャプチャを順に集める。 */
export function captureAll(source: string, pattern: RegExp): string[] {
  const found: string[] = []
  for (const match of source.matchAll(pattern)) {
    if (match[1] !== undefined) found.push(match[1])
  }
  return found
}

/**
 * `start` の位置から始まる `[...]` リテラルを読み、拡張子の集合を返す。
 *
 * リテラルでない（`Set(...)` や `.code(...)`）、`[String](...)` のような型変換、
 * 文字列を 1 つも含まないものは null を返して「拡張子グループではない」と扱う。
 */
function readBracketLiteral(source: string, start: number): Set<string> | null {
  if (source[start] !== '[') return null

  let depth = 0
  let end = -1
  for (let i = start; i < source.length; i += 1) {
    if (source[i] === '[') depth += 1
    else if (source[i] === ']') {
      depth -= 1
      if (depth === 0) {
        end = i
        break
      }
    }
  }
  if (end === -1) return null

  // `[String](dictionary.keys)` のような型変換はリテラルではない。
  if (
    source
      .slice(end + 1)
      .trimStart()
      .startsWith('(')
  )
    return null

  const body = source.slice(start + 1, end)
  // 辞書リテラルなら key だけを採る。判定は本文に `"...":` が現れるかどうか。
  const isDictionary = /"[^"]*"\s*:/u.test(body)
  const pattern = isDictionary ? /"([^"]+)"\s*:/gu : /"([^"]+)"/gu
  const found = captureAll(body, pattern)

  return found.length === 0 ? null : new Set(found)
}

/**
 * `static let <name> = <n> * 1024 * 1024` 形式のサイズ上限を MB で拾う。
 *
 * 拡張子と同じく、上限も Swift 側が単一情報源。ページに書いた数値がずれたら
 * test/file-types.test.ts が落ちるようにするために使う。
 */
export function parseSwiftSizeLimitsMB(source: string): Map<string, number> {
  const limits = new Map<string, number>()
  const pattern = /static let ([A-Za-z0-9_]+)\s*=\s*(\d+)\s*\*\s*1024\s*\*\s*1024\b/gu

  for (const match of source.matchAll(pattern)) {
    const [, name, megabytes] = match
    if (name === undefined || megabytes === undefined) continue
    limits.set(name, Number(megabytes))
  }

  return limits
}
