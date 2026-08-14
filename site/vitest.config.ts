import { readdir, readFile } from 'node:fs/promises'
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

/**
 * 集計クエリ本体。ボット除外の条件が 1 箇所に集約されているかを、実行結果では
 * なくソースの形で検査するために渡す（新しい集計を足したときに検知する）。
 */
const ANALYTICS_TS = path.join(import.meta.dirname, 'src', 'analytics.ts')

/**
 * Worker の公開面（Custom Domain と workers.dev）の設定そのもの。routes を
 * 書くと workers_dev は次回デプロイで false と推論される仕様があるため、
 * 設定ファイルの記述をテストで固定する（ADR 0007 の決定 1 の担保）。
 */
const WRANGLER_TOML = path.join(import.meta.dirname, 'wrangler.toml')

/** キーボードショートカット表が参照する、メインメニュー定義とその参照先の定数。 */
const APP = path.join(import.meta.dirname, '..', 'BefoldApp', 'befold', 'App')
const BOOKMARK_SHORTCUT_SWIFT = path.join(APP, 'BookmarkShortcut.swift')

/**
 * メニュー定義は `MainMenuBuilder+ViewMenu.swift` のように extension へ分割される
 * （SwiftLint の file_length 対策）。1 ファイルだけを読むと、分割で移動した項目が
 * 「実装に存在しない」と見なされて検証が壊れるため、`MainMenuBuilder*.swift` を
 * すべて読んで連結する。1 件も見つからなければ throw して黙って無効化させない。
 */
async function readMainMenuBuilderSwift(): Promise<string> {
  const names = (await readdir(APP))
    .filter((name) => name.startsWith('MainMenuBuilder') && name.endsWith('.swift'))
    .sort()
  if (names.length === 0) throw new Error(`MainMenuBuilder*.swift が見つからない: ${APP}`)

  const sources = await Promise.all(names.map((name) => readFile(path.join(APP, name), 'utf8')))
  return sources.join('\n')
}

export default defineConfig({
  plugins: [
    cloudflareTest(async () => {
      // Atlas が生成したマイグレーションをテスト用 D1 に流し込むため、内容を読み込んで
      // バインディング経由でテスト側へ渡す（適用は test/setup.ts で行う）。
      const migrations = await readD1Migrations(path.join(import.meta.dirname, 'migrations'))
      const fileTypeSwift = await readFile(FILE_TYPE_SWIFT, 'utf8')
      const contentLoaderSwift = await readFile(CONTENT_LOADER_SWIFT, 'utf8')
      const normalizedTextCacheSwift = await readFile(NORMALIZED_TEXT_CACHE_SWIFT, 'utf8')
      const mainMenuBuilderSwift = await readMainMenuBuilderSwift()
      const bookmarkShortcutSwift = await readFile(BOOKMARK_SHORTCUT_SWIFT, 'utf8')
      const analyticsSource = await readFile(ANALYTICS_TS, 'utf8')
      const wranglerToml = await readFile(WRANGLER_TOML, 'utf8')

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
            TEST_ANALYTICS_SOURCE: analyticsSource,
            TEST_WRANGLER_TOML: wranglerToml,
            ACCESS_TEAM_DOMAIN: 'test-team.cloudflareaccess.com',
            ACCESS_AUD: 'test-aud',
          },
        },
      }
    }),
  ],
  test: {
    setupFiles: ['./test/setup.ts'],
  },
})
