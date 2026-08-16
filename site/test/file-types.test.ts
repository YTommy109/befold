import { env } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'

import {
  FILE_TYPE_GROUPS,
  SIZE_LIMITS_MB,
  allTableExtensions,
  captureAll,
  parseSwiftFileTypes,
  parseSwiftSizeLimitsMB,
} from '../src/lib/file-types'
import { FEATURES, MORE_FEATURES } from '../src/views/shared'

/**
 * 詳細ページの対応ファイルタイプ表が、実装（BefoldKit/FileType.swift）から
 * ずれたら落ちるようにする。Swift のソースは vitest.config.ts が読み込み、
 * TEST_FILE_TYPE_SWIFT バインディングで渡している。
 */

const parsed = parseSwiftFileTypes(env.TEST_FILE_TYPE_SWIFT)

/**
 * FileType.swift の `public static let` 宣言名（宣言順）。
 *
 * 拡張子を持つ定数だけでなく全件を突き合わせる。「新しい拡張子グループが
 * 増えたのにパーサがその形を知らず取りこぼす」と、拡張子の集合比較は通って
 * しまうため、宣言の増減そのものを検知する必要がある。
 * ここが落ちたら、増えた宣言が拡張子グループかどうかを見て
 * FILE_TYPE_GROUPS とこのリストの両方を更新すること。
 */
const EXPECTED_DECLARATIONS = [
  'mermaidExtensions',
  'markdownExtensions',
  'svgExtensions',
  'htmlExtensions',
  'csvExtensions',
  'tsvExtensions',
  'codeExtensionLanguages',
  'codeExtensions',
  'imageExtensionMimeTypes',
  'pdfExtensions',
  'plaintextFallback',
  'allExtensions',
  'quickLookSupportedExtensions',
]

/** 上のうち、拡張子リテラルを持つもの（= 拡張子の供給源）。 */
const EXPECTED_LITERAL_GROUPS = [
  'mermaidExtensions',
  'markdownExtensions',
  'svgExtensions',
  'htmlExtensions',
  'csvExtensions',
  'tsvExtensions',
  'codeExtensionLanguages',
  'imageExtensionMimeTypes',
  'pdfExtensions',
]

function sorted(values: Iterable<string>): string[] {
  return [...values].toSorted()
}

describe('FileType.swift のパース', () => {
  it('public static let 宣言を全件拾う（新しい宣言が増えたら落ちる）', () => {
    expect(parsed.declarationNames).toEqual(EXPECTED_DECLARATIONS)
  })

  it('拡張子リテラルを持つ宣言だけをグループとして扱う', () => {
    expect(sorted(parsed.literalGroups.keys())).toEqual(sorted(EXPECTED_LITERAL_GROUPS))
  })

  it('どのグループも 1 件以上の拡張子を持つ（パーサが壊れて空になったら落ちる）', () => {
    for (const [name, extensions] of parsed.literalGroups) {
      expect(extensions.size, `${name} の拡張子が空`).toBeGreaterThan(0)
    }
  })
})

describe('対応ファイルタイプ表', () => {
  it('表の拡張子が FileType.swift の全拡張子と一致する', () => {
    const fromSwift = new Set<string>()
    for (const extensions of parsed.literalGroups.values()) {
      for (const extension of extensions) fromSwift.add(extension)
    }

    expect(sorted(allTableExtensions())).toEqual(sorted(fromSwift))
  })

  it('同じ拡張子を 2 つの種別に載せない', () => {
    const listed = FILE_TYPE_GROUPS.flatMap((group) => group.extensions)
    expect(listed.length).toBe(new Set(listed).size)
  })

  it('表のサイズ上限が Swift 側の定数と一致する', () => {
    const contentLoader = parseSwiftSizeLimitsMB(env.TEST_CONTENT_LOADER_SWIFT)
    const normalizedTextCache = parseSwiftSizeLimitsMB(env.TEST_NORMALIZED_TEXT_CACHE_SWIFT)

    expect(normalizedTextCache.get('maxFileSizeBytes')).toBe(SIZE_LIMITS_MB.chunkable)
    expect(contentLoader.get('maxTextFileSizeBytes')).toBe(SIZE_LIMITS_MB.nonChunkableText)
    expect(contentLoader.get('maxFileSizeBytes')).toBe(SIZE_LIMITS_MB.binary)
  })

  it('チャンク対応の種別には分割読み込みの上限を割り当てる', () => {
    for (const group of FILE_TYPE_GROUPS) {
      if (!group.chunkable) continue
      expect(group.maxSizeMB, `${group.label} の上限`).toBe(SIZE_LIMITS_MB.chunkable)
    }
  })

  it('LP の機能説明に書いた拡張子も表に載っている', () => {
    // 訴求文なので生成はしないが、表と食い違ったまま片方だけ直る状態は作らない。
    const prose = [...FEATURES, ...MORE_FEATURES]
      .flatMap((feature) => feature.ja.concat(feature.en))
      .join(' ')
    const mentioned = captureAll(prose, /\.([a-z0-9]{1,8})\b/gu)

    expect(mentioned.length).toBeGreaterThan(0)
    expect(sorted(new Set(mentioned)).filter((ext) => !allTableExtensions().has(ext))).toEqual([])
  })
})
