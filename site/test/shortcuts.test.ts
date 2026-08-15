import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'
import app from '../src/index'
import {
  formatShortcut,
  type MenuShortcutItem,
  parseSwiftMenuShortcuts,
  parseSwiftMenuItemTags,
  parseSwiftModeSegments,
  parseSwiftStringConstants,
  shortcutsInProse,
  splitShortcutKeys,
} from '../src/lib/shortcuts'
import { SHORTCUTS } from '../src/views/features'

/**
 * 紹介サイトに書いたキーボードショートカットが、実装（BefoldApp のメインメニュー定義）と
 * ずれたら落ちるようにする。Swift のソースは vitest.config.ts が読み込み、
 * TEST_MAIN_MENU_BUILDER_SWIFT / TEST_BOOKMARK_SHORTCUT_SWIFT で渡している。
 */

const parsed = parseSwiftMenuShortcuts(env.TEST_MAIN_MENU_BUILDER_SWIFT)

/**
 * 表示モードの ⌘1〜⌘3 のキー。メニュー定義には `String(mode.menuItemTag)` の
 * 計算値としてしか現れないため、参照先（ModeSegments.all の並びと
 * ViewerDisplayMode.menuItemTag の対応）をパースして静的に解決する。
 * タグが引けなければモード名がそのまま残り、下の期待値と一致せず落ちる。
 */
const displayModeKeys = (() => {
  const tags = parseSwiftMenuItemTags(env.TEST_VIEWER_DISPLAY_MODE_SWIFT)
  return parseSwiftModeSegments(env.TEST_MODE_SEGMENTS_SWIFT).map((name) =>
    String(tags.get(name) ?? name),
  )
})()

/**
 * MainMenuBuilder*.swift でキー等価を与えている項目の全件。
 *
 * 定義は extension（`MainMenuBuilder+ViewMenu.swift`）へ分割されるため、ソース順は
 * ファイル分割のたびに変わる。並びではなく集合を固定したいので、突き合わせる前に
 * 両辺をローカライズキーで整列する。
 *
 * サイトに載せている分だけを突き合わせると、実装側でキーが変わった項目が
 * 「サイトに書いていない」という理由で検証をすり抜ける。項目の一覧そのものを
 * 固定して、割り当ての増減・変更が必ずこのテストに現れるようにする。
 *
 * ここが落ちたら、この表と features.tsx の SHORTCUTS を更新すること。
 * `keyEquivalent` がリテラルでない項目（表示モードの ⌘1〜）は、参照先の
 * Swift ソースから displayModeKeys として解決する。
 */
const EXPECTED_MENU_ITEMS: {
  localizationKey: string
  keyEquivalent: string
  modifiers: string[] | null
}[] = [
  { localizationKey: 'menu.app.settings', keyEquivalent: '","', modifiers: ['.command'] },
  { localizationKey: 'menu.app.hide', keyEquivalent: '"h"', modifiers: null },
  { localizationKey: 'menu.app.hideOthers', keyEquivalent: '"h"', modifiers: ['.command', '.option'] },
  { localizationKey: 'menu.app.quit', keyEquivalent: '"q"', modifiers: null },
  { localizationKey: 'menu.file.open', keyEquivalent: '"o"', modifiers: null },
  { localizationKey: 'menu.file.quickOpen', keyEquivalent: '"p"', modifiers: null },
  { localizationKey: 'menu.file.close', keyEquivalent: '"w"', modifiers: null },
  { localizationKey: 'menu.file.print', keyEquivalent: '"p"', modifiers: ['.command', '.shift'] },
  { localizationKey: 'menu.edit.undo', keyEquivalent: '"z"', modifiers: null },
  { localizationKey: 'menu.edit.redo', keyEquivalent: '"z"', modifiers: ['.command', '.shift'] },
  { localizationKey: 'menu.edit.cut', keyEquivalent: '"x"', modifiers: null },
  { localizationKey: 'menu.edit.copy', keyEquivalent: '"c"', modifiers: null },
  { localizationKey: 'menu.edit.paste', keyEquivalent: '"v"', modifiers: null },
  { localizationKey: 'menu.edit.selectAll', keyEquivalent: '"a"', modifiers: null },
  { localizationKey: 'menu.edit.find', keyEquivalent: '"f"', modifiers: null },
  { localizationKey: 'menu.edit.findNext', keyEquivalent: '"g"', modifiers: null },
  { localizationKey: 'menu.edit.findPrevious', keyEquivalent: '"g"', modifiers: ['.command', '.shift'] },
  { localizationKey: 'menu.view.actualSize', keyEquivalent: '"0"', modifiers: null },
  { localizationKey: 'menu.view.zoomIn', keyEquivalent: '"+"', modifiers: null },
  { localizationKey: 'menu.view.zoomOut', keyEquivalent: '"-"', modifiers: null },
  { localizationKey: 'menu.view.toggleSource', keyEquivalent: '"u"', modifiers: null },
  { localizationKey: 'menu.view.showLineNumbers', keyEquivalent: '"l"', modifiers: null },
  {
    localizationKey: 'menu.view.addBookmark',
    keyEquivalent: 'BookmarkShortcut.keyEquivalent',
    modifiers: null,
  },
  { localizationKey: 'menu.view.toggleSidebar', keyEquivalent: '"s"', modifiers: ['.command'] },
  { localizationKey: 'menu.view.goBack', keyEquivalent: '"["', modifiers: null },
  { localizationKey: 'menu.view.goForward', keyEquivalent: '"]"', modifiers: null },
  {
    localizationKey: 'menu.view.showHiddenFiles',
    keyEquivalent: '"h"',
    modifiers: ['.command', '.control'],
  },
  {
    localizationKey: 'menu.view.showChangedFilesOnly',
    keyEquivalent: '"g"',
    modifiers: ['.command', '.control'],
  },
  {
    localizationKey: 'menu.view.sidebarTreeLayout',
    keyEquivalent: '"t"',
    modifiers: ['.command', '.control'],
  },
  {
    localizationKey: 'menu.view.enterFullScreen',
    keyEquivalent: '"f"',
    modifiers: ['.control', '.command'],
  },
  { localizationKey: 'menu.window.minimize', keyEquivalent: '"m"', modifiers: null },
  { localizationKey: 'menu.help.visitWebsite', keyEquivalent: '"?"', modifiers: null },
  {
    localizationKey: 'mode.menuLabelKey',
    keyEquivalent: 'String(mode.menuItemTag)',
    modifiers: ['.command'],
  },
  {
    localizationKey: 'menu.view.diffSideBySide',
    keyEquivalent: '"\\\\"',
    modifiers: ['.command'],
  },
]

/** `BookmarkShortcut.keyEquivalent` のような定数参照を、実際のキーへ解決する。 */
function resolveKeyEquivalent(expression: string): string | null {
  const literal = /^"(.*)"$/.exec(expression)?.[1]
  // Swift のエスケープを戻す（差分レイアウトの `"\\"` は 1 文字の `\`）。
  if (literal !== undefined) return literal.replace(/\\(.)/g, '$1')

  const constant = /^BookmarkShortcut\.([A-Za-z0-9_]+)$/.exec(expression)?.[1]
  if (constant === undefined) return null

  return parseSwiftStringConstants(env.TEST_BOOKMARK_SHORTCUT_SWIFT).get(constant) ?? null
}

/**
 * 実装のメニュー定義に存在するショートカットの集合（例: `⌃⌘F`）。
 * 期待値の表ではなくパース結果から作る（実装を変えたときに、上の全件比較だけでなく
 * サイトとの突き合わせも落ちるようにするため）。
 */
function implementedShortcuts(): Set<string> {
  const shortcuts = new Set<string>()
  for (const item of parsed) {
    for (const key of resolveKeys(item)) shortcuts.add(formatShortcut(key, item.modifiers))
  }
  return shortcuts
}

/** 1 項目が表すキーの列。表示モードの項目だけ複数キー（⌘1〜⌘3）へ展開する。 */
function resolveKeys(item: MenuShortcutItem): string[] {
  if (item.keyEquivalent === 'String(mode.menuItemTag)') return displayModeKeys
  const key = resolveKeyEquivalent(item.keyEquivalent)
  return key === null ? [] : [key]
}

/** 表に載せた全ショートカット（`⌘F / ⌘G` のような併記は分解する）。 */
function tableShortcuts(): string[] {
  return SHORTCUTS.flatMap((shortcut) => splitShortcutKeys(shortcut.keys))
}

async function pageBody(path: string): Promise<string> {
  const request = new Request(`https://befold.example${path}`)
  const ctx = createExecutionContext()
  const response = await app.fetch(request, env, ctx)
  await waitOnExecutionContext(ctx)
  return await response.text()
}

function sorted(values: Iterable<string>): string[] {
  return [...values].sort()
}

/** ファイル分割によるソース順の違いを無視するため、ローカライズキーで整列する。 */
function byLocalizationKey<T extends { localizationKey: string }>(items: readonly T[]): T[] {
  return [...items].sort((left, right) => left.localizationKey.localeCompare(right.localizationKey))
}

describe('MainMenuBuilder.swift のパース', () => {
  it('キー等価を持つ項目を全件拾う（割り当てが変わったら落ちる）', () => {
    expect(byLocalizationKey(parsed)).toEqual(byLocalizationKey(EXPECTED_MENU_ITEMS))
  })

  it('キー等価がリテラルまたは既知の定数参照として解決できる', () => {
    const unresolved = parsed
      .map((item) => item.keyEquivalent)
      .filter((expression) => resolveKeyEquivalent(expression) === null)

    // 表示モードの項目だけは単キーとして解決できず、displayModeKeys へ展開される。
    // ここが増えたら、解決の手段を用意してから期待値を更新すること。
    expect(unresolved).toEqual(['String(mode.menuItemTag)'])
  })

  it('ブックマークのキー等価を BookmarkShortcut から解決する', () => {
    expect(resolveKeyEquivalent('BookmarkShortcut.keyEquivalent')).toBe('d')
  })

  it('表示モードのキーを ModeSegments と ViewerDisplayMode から解決する', () => {
    expect(displayModeKeys).toEqual(['1', '2', '3'])
  })
})

describe('ショートカット表', () => {
  it('表のショートカットが実装の割り当てに存在する', () => {
    const missing = tableShortcuts().filter((key) => !implementedShortcuts().has(key))
    expect(missing).toEqual([])
  })

  it('同じショートカットを 2 行に載せない', () => {
    const listed = tableShortcuts()
    expect(listed.length).toBe(new Set(listed).size)
  })

})

describe('ページに書いたショートカット', () => {
  it.each([
    ['LP', '/'],
    ['詳細ページ', '/features'],
  ])('%s の記載が実装の割り当てに存在する', async (_label, path) => {
    // 表だけでなく訴求文にもベタ書きしているため、描画結果から拾って突き合わせる。
    const mentioned = shortcutsInProse(await pageBody(path))

    expect(mentioned.length).toBeGreaterThan(0)
    expect(sorted(new Set(mentioned)).filter((key) => !implementedShortcuts().has(key))).toEqual([])
  })

  it('詳細ページの記載はすべて表にも載っている', async () => {
    const mentioned = new Set(shortcutsInProse(await pageBody('/features')))
    const listed = new Set(tableShortcuts())

    expect(sorted(mentioned).filter((key) => !listed.has(key))).toEqual([])
  })
})
