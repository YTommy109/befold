import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-pool-workers'
import { defineConfig } from 'vitest/config'

/**
 * 詳細ページの対応ファイルタイプ表が参照する Swift 側の単一情報源。
 * テストは workers ランタイムで走り node:fs を持たないため、マイグレーションと
 * 同じくここで読んでバインディングとして渡す。
 *
 * 読めなければ readFile が throw して設定ごと失敗する。空文字で代替すると
 * 「Swift 側に拡張子が 1 つも無い」と解釈されかねず、パスを動かしたときに
 * ずれ検知が黙って無効になるため、フォールバックは置かない。
 */
const KIT = path.join(import.meta.dirname, '..', 'BefoldApp', 'BefoldKit')
const FILE_TYPE_SWIFT = path.join(KIT, 'FileType.swift')
const CONTENT_LOADER_SWIFT = path.join(KIT, 'ContentLoader.swift')
const NORMALIZED_TEXT_CACHE_SWIFT = path.join(KIT, 'NormalizedTextCache.swift')

/** キーボードショートカット表が参照する、メインメニュー定義とその参照先の定数。 */
const APP = path.join(import.meta.dirname, '..', 'BefoldApp', 'befold', 'App')
const MAIN_MENU_BUILDER_SWIFT = path.join(APP, 'MainMenuBuilder.swift')
const BOOKMARK_SHORTCUT_SWIFT = path.join(APP, 'BookmarkShortcut.swift')

export default defineConfig({
  plugins: [
    cloudflareTest(async () => {
      // Atlas が生成したマイグレーションをテスト用 D1 に流し込むため、内容を読み込んで
      // バインディング経由でテスト側へ渡す（適用は test/setup.ts で行う）。
      const migrations = await readD1Migrations(path.join(import.meta.dirname, 'migrations'))
      const fileTypeSwift = await readFile(FILE_TYPE_SWIFT, 'utf8')
      const contentLoaderSwift = await readFile(CONTENT_LOADER_SWIFT, 'utf8')
      const normalizedTextCacheSwift = await readFile(NORMALIZED_TEXT_CACHE_SWIFT, 'utf8')
      const mainMenuBuilderSwift = await readFile(MAIN_MENU_BUILDER_SWIFT, 'utf8')
      const bookmarkShortcutSwift = await readFile(BOOKMARK_SHORTCUT_SWIFT, 'utf8')

      return {
        singleWorker: true,
        wrangler: { configPath: './wrangler.toml' },
        miniflare: {
          // .dev.vars は gitignore 対象なので、テスト用の認証情報はここで固定する。
          bindings: {
            TEST_MIGRATIONS: migrations,
            TEST_FILE_TYPE_SWIFT: fileTypeSwift,
            TEST_CONTENT_LOADER_SWIFT: contentLoaderSwift,
            TEST_NORMALIZED_TEXT_CACHE_SWIFT: normalizedTextCacheSwift,
            TEST_MAIN_MENU_BUILDER_SWIFT: mainMenuBuilderSwift,
            TEST_BOOKMARK_SHORTCUT_SWIFT: bookmarkShortcutSwift,
            DASHBOARD_USER: 'owner',
            DASHBOARD_PASSWORD: 'test-password',
          },
        },
      }
    }),
  ],
  test: {
    setupFiles: ['./test/setup.ts'],
  },
})
