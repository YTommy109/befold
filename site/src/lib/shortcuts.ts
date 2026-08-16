/**
 * 紹介サイトに書いたキーボードショートカットを、実装（BefoldApp のメインメニュー定義）と
 * 突き合わせるためのパーサ群。
 *
 * 情報源は `BefoldApp/befold/App/MainMenuBuilder.swift` に一本化する。アプリ内ヘルプも
 * 同じメニュー定義から `MenuShortcutCatalog` が生成しており、表記の作り方（⌃⌥⇧⌘ の順に
 * 並べてキーを大文字化する）もそちらに合わせている。
 */

/** `addLocalizedItem` 呼び出し 1 件のうち、キー等価を持つもの。 */
export type MenuShortcutItem = {
  /**
   * 第 1 引数のローカライズキー（例: `menu.file.quickOpen`）。
   * リテラルでない場合（`mode.menuLabelKey`）は式をソースのまま持つ。
   */
  localizationKey: string
  /**
   * `keyEquivalent:` に渡された式をソースのまま持つ。
   * 文字列リテラルなら `"p"`、定数参照なら `BookmarkShortcut.keyEquivalent`、
   * 計算値なら `String(mode.menuItemTag)` のようになる。
   */
  keyEquivalent: string
  /**
   * `modifiers:` に渡された修飾キー。省略時は null（AppKit の既定である
   * `[.command]` と同じ扱いになるが、ソースに書いてあるかどうかは区別して持つ）。
   */
  modifiers: string[] | null
}

/**
 * MainMenuBuilder.swift から、キー等価を与えている `addLocalizedItem` 呼び出しを
 * ソース順に全件拾う。
 *
 * 既知の項目だけを決め打ちで読むと、実装側でキーが増減しても黙って検証が通る。
 * 呼び出しを総当たりで拾って一覧そのものをテストで突き合わせられるようにする
 * （`parseSwiftFileTypes` が宣言名を全件返すのと同じ考え方）。
 */
export function parseSwiftMenuShortcuts(source: string): MenuShortcutItem[] {
  const marker = 'addLocalizedItem('
  const starts = [...source.matchAll(/addLocalizedItem\(/gu)].map((match) => match.index)

  const items: MenuShortcutItem[] = []
  starts.forEach((start, index) => {
    // 次の呼び出しの直前までを 1 件分とする。呼び出しをまたいで読むと、キー等価を
    // 持たない項目が次の項目のキーを拾ってしまう。
    const rest = source.slice(start + marker.length, starts[index + 1] ?? source.length)
    // 呼び出しの閉じ括弧までで切る。後続のコードまで含めると、キー等価を持たない
    // 項目が近くの `keyEquivalent:`（別 API の引数など）を拾ってしまう。
    const item = parseCallChunk(rest.slice(0, callEnd(rest)))
    if (item !== null) items.push(item)
  })
  return items
}

/** `addLocalizedItem(` の直後から数えて、その呼び出しを閉じる `)` の位置を返す。 */
function callEnd(rest: string): number {
  let depth = 0
  for (let i = 0; i < rest.length; i += 1) {
    const character = rest[i] ?? ''
    if (character === '"') {
      i = skipStringLiteral(rest, i)
      continue
    }
    if ('([{'.includes(character)) depth += 1
    else if (')]}'.includes(character)) {
      if (depth === 0) return i
      depth -= 1
    }
  }
  return rest.length
}

function parseCallChunk(chunk: string): MenuShortcutItem | null {
  const first = readArgumentExpression(chunk, 0).expression
  // 表示モードの項目は第 1 引数も `mode.menuLabelKey` のような式で書かれている。
  // リテラルなら引用符を外し、式ならソースのまま残して一覧に現れるようにする。
  const localizationKey = /^"([^"]*)"$/u.exec(first)?.[1] ?? first

  const label = 'keyEquivalent:'
  const labelIndex = chunk.indexOf(label)
  if (labelIndex === -1) return null

  const { expression, end } = readArgumentExpression(chunk, labelIndex + label.length)
  const modifiers = /^\s*,\s*modifiers:\s*\[([^\]]*)\]/u.exec(chunk.slice(end))?.[1]

  return {
    localizationKey,
    keyEquivalent: expression,
    modifiers: modifiers === undefined ? null : splitModifiers(modifiers),
  }
}

/**
 * `start` から 1 引数分の式を読む。深さ 0 の `,` か `)` で終端する
 * （`String(mode.menuItemTag)` のように式の内側に括弧があっても途中で切らない）。
 */
function readArgumentExpression(chunk: string, start: number): { expression: string; end: number } {
  const open = '([{'
  const close = ')]}'
  let depth = 0

  for (let i = start; i < chunk.length; i += 1) {
    const character = chunk[i] ?? ''
    // 文字列リテラルは中身を見ない（`","` や `"["` の記号を区切りと誤認しないため）。
    if (character === '"') {
      i = skipStringLiteral(chunk, i)
      continue
    }
    if (open.includes(character)) depth += 1
    else if (close.includes(character)) {
      if (depth === 0) return { expression: chunk.slice(start, i).trim(), end: i }
      depth -= 1
    } else if (character === ',' && depth === 0) {
      return { expression: chunk.slice(start, i).trim(), end: i }
    }
  }
  return { expression: chunk.slice(start).trim(), end: chunk.length }
}

/** `open` 位置の `"` から始まる文字列リテラルの終端（閉じ引用符）の位置を返す。 */
function skipStringLiteral(chunk: string, open: number): number {
  for (let i = open + 1; i < chunk.length; i += 1) {
    if (chunk[i] === '\\') {
      i += 1
      continue
    }
    if (chunk[i] === '"') return i
  }
  return chunk.length
}

function splitModifiers(source: string): string[] {
  return source
    .split(',')
    .map((modifier) => modifier.trim())
    .filter((modifier) => modifier.length > 0)
}

/**
 * `static let <name> = "<value>"` 形式の文字列定数を拾う。
 *
 * `BookmarkShortcut.keyEquivalent` のように、メニュー定義がキー等価を定数参照で
 * 書いている箇所を解決するために使う。
 */
export function parseSwiftStringConstants(source: string): Map<string, string> {
  const constants = new Map<string, string>()
  const pattern = /static let ([A-Za-z0-9_]+)\s*(?::\s*String\s*)?=\s*"([^"]*)"/gu

  for (const match of source.matchAll(pattern)) {
    const [, name, value] = match
    if (name === undefined || value === undefined) continue
    constants.set(name, value)
  }

  return constants
}

/**
 * `ViewerDisplayMode.menuItemTag` の switch から、モード名 → タグ数値の対応を拾う。
 *
 * 表示モードのメニュー項目はキー等価を `String(mode.menuItemTag)` の計算値で
 * 与えており、メニュー定義側には数字が現れない。参照先の enum から解決する。
 * 数値を返す case はこのプロパティにしか無いため、ファイル全体を対象にする。
 */
export function parseSwiftMenuItemTags(source: string): Map<string, number> {
  const tags = new Map<string, number>()
  for (const match of source.matchAll(/case \.([A-Za-z0-9_]+):\s*(\d+)\b/gu)) {
    const [, name, tag] = match
    if (name === undefined || tag === undefined) continue
    tags.set(name, Number(tag))
  }
  return tags
}

/**
 * `ModeSegments.all` に並ぶモード名を宣言順に拾う。
 *
 * View メニューの表示モード項目は `ModeSegments.all` を回して作られるため、
 * メニューに現れる項目の並びと個数はこの配列が決める。
 */
export function parseSwiftModeSegments(source: string): string[] {
  const list = /static let all[^=]*=\s*\[([^\]]*)\]/u.exec(source)?.[1] ?? ''
  return [...list.matchAll(/\.([A-Za-z0-9_]+)/gu)].flatMap((match) => match[1] ?? [])
}

/**
 * キー等価と修飾キーを `MenuShortcutCatalog.keyDisplay` と同じ表記へ変換する。
 *
 * 修飾キーの指定が無い場合、AppKit はキー等価を与えた項目に `[.command]` を既定で
 * 割り当てるため、同じ扱いにする。
 */
export function formatShortcut(key: string, modifiers: string[] | null): string {
  const flags = modifiers ?? ['.command']
  let symbols = ''
  if (flags.includes('.control')) symbols += '⌃'
  if (flags.includes('.option')) symbols += '⌥'
  if (flags.includes('.shift')) symbols += '⇧'
  if (flags.includes('.command')) symbols += '⌘'
  return symbols + key.toUpperCase()
}

/** ショートカット表記に使う修飾キー記号。 */
const MODIFIER_SYMBOLS = '⌃⌥⇧⌘'

/**
 * `⌘F / ⌘G` のように 1 行へまとめた表記を、個々のショートカットへ分解する。
 * 表の見た目のためにスラッシュで併記している行があるため、突き合わせる前に割る。
 */
export function splitShortcutKeys(keys: string): string[] {
  return keys
    .split('/')
    .map((key) => key.trim())
    .filter((key) => key.length > 0)
}

/**
 * 散文に現れるショートカット表記（`⌘S`、`⌃⌘F` など）を拾う。
 *
 * LP の訴求文や詳細ページの補足文はショートカットを地の文にベタ書きしているため、
 * 表と食い違ったまま片方だけ直る状態を作らないために使う。
 */
export function shortcutsInProse(prose: string): string[] {
  // 修飾キー記号に続く 1 文字がキー。区切り文字・句読点・HTML タグの開始で終端する。
  const pattern = new RegExp(`[${MODIFIER_SYMBOLS}]+[^\\s、。,.（）()/<>&]`, 'gu')
  return [...prose.matchAll(pattern)].map((match) => match[0])
}
