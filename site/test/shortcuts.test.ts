import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'
import app from '../src/index'
import {
  formatShortcut,
  parseSwiftMenuShortcuts,
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
 * MainMenuBuilder.swift でキー等価を与えている項目の全件（ソース順）。
 *
 * サイトに載せている分だけを突き合わせると、実装側でキーが変わった項目が
 * 「サイトに書いていない」という理由で検証をすり抜ける。項目の一覧そのものを
 * 固定して、割り当ての増減・変更が必ずこのテストに現れるようにする。
 *
 * ここが落ちたら、増減した項目を stable ビルドで露出するかどうかで分類し、
 * この表・GATED_LOCALIZATION_KEYS・（露出するなら）features.tsx の SHORTCUTS を
 * 更新すること。`keyEquivalent` がリテラルでない項目（表示モードの ⌘1〜）は
 * 表記が実行時に決まるため、サイトには載せない。
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
    keyEquivalent: '"4"',
    modifiers: ['.command'],
  },
]

/**
 * フィーチャーゲートの内側にあり、stable ビルドでは項目自体が存在しないもの。
 * サイトは stable の利用者が見るため、ここに挙げた項目は載せてはならない。
 */
const GATED_LOCALIZATION_KEYS = new Set(['menu.view.showChangedFilesOnly', 'menu.view.diffSideBySide'])

/** `BookmarkShortcut.keyEquivalent` のような定数参照を、実際のキーへ解決する。 */
function resolveKeyEquivalent(expression: string): string | null {
  const literal = /^"(.*)"$/.exec(expression)?.[1]
  if (literal !== undefined) return literal

  const constant = /^BookmarkShortcut\.([A-Za-z0-9_]+)$/.exec(expression)?.[1]
  if (constant === undefined) return null

  return parseSwiftStringConstants(env.TEST_BOOKMARK_SHORTCUT_SWIFT).get(constant) ?? null
}

/**
 * stable ビルドに存在し、表記が静的に決まるショートカットの集合（例: `⌃⌘F`）。
 * 期待値の表ではなくパース結果から作る（実装を変えたときに、上の全件比較だけでなく
 * サイトとの突き合わせも落ちるようにするため）。
 */
function stableShortcuts(): Set<string> {
  const shortcuts = new Set<string>()
  for (const item of parsed) {
    if (GATED_LOCALIZATION_KEYS.has(item.localizationKey)) continue
    const key = resolveKeyEquivalent(item.keyEquivalent)
    if (key === null) continue
    shortcuts.add(formatShortcut(key, item.modifiers))
  }
  return shortcuts
}

/** フィーチャーゲートの内側にあり、stable ビルドでは存在しないショートカットの集合。 */
function gatedShortcuts(): Set<string> {
  const shortcuts = new Set<string>()
  for (const item of parsed) {
    if (!GATED_LOCALIZATION_KEYS.has(item.localizationKey)) continue
    const key = resolveKeyEquivalent(item.keyEquivalent)
    if (key !== null) shortcuts.add(formatShortcut(key, item.modifiers))
  }
  return shortcuts
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

describe('MainMenuBuilder.swift のパース', () => {
  it('キー等価を持つ項目を全件拾う（割り当てが変わったら落ちる）', () => {
    expect(parsed).toEqual(EXPECTED_MENU_ITEMS)
  })

  it('キー等価がリテラルまたは既知の定数参照として解決できる', () => {
    const unresolved = parsed
      .map((item) => item.keyEquivalent)
      .filter((expression) => resolveKeyEquivalent(expression) === null)

    // 実行時に決まる表示モードの項目だけが解決できない。ここが増えたら、
    // その項目をサイトに載せるかどうかを判断してから期待値を更新すること。
    expect(unresolved).toEqual(['String(mode.menuItemTag)'])
  })

  it('ブックマークのキー等価を BookmarkShortcut から解決する', () => {
    expect(resolveKeyEquivalent('BookmarkShortcut.keyEquivalent')).toBe('d')
  })
})

describe('ショートカット表', () => {
  it('表のショートカットが実装の割り当てに存在する', () => {
    const missing = tableShortcuts().filter((key) => !stableShortcuts().has(key))
    expect(missing).toEqual([])
  })

  it('同じショートカットを 2 行に載せない', () => {
    const listed = tableShortcuts()
    expect(listed.length).toBe(new Set(listed).size)
  })

  it('フィーチャーゲートの内側のショートカットは載せない', () => {
    const gated = gatedShortcuts()
    expect(gated.size).toBeGreaterThan(0)
    expect(tableShortcuts().filter((key) => gated.has(key))).toEqual([])
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
    expect(sorted(new Set(mentioned)).filter((key) => !stableShortcuts().has(key))).toEqual([])
  })

  it('詳細ページの記載はすべて表にも載っている', async () => {
    const mentioned = new Set(shortcutsInProse(await pageBody('/features')))
    const listed = new Set(tableShortcuts())

    expect(sorted(mentioned).filter((key) => !listed.has(key))).toEqual([])
  })
})
