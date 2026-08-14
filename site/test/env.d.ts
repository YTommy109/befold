import type { D1Migration } from '@cloudflare/vitest-pool-workers'

// テスト実行時のみ、マイグレーション内容を渡す追加バインディングが存在する。
declare global {
  namespace Cloudflare {
    interface Env {
      TEST_MIGRATIONS: D1Migration[]
      /** 対応ファイルタイプ表のずれ検知に使う BefoldKit のソース。 */
      TEST_FILE_TYPE_SWIFT: string
      TEST_CONTENT_LOADER_SWIFT: string
      TEST_NORMALIZED_TEXT_CACHE_SWIFT: string
      /** ショートカット表のずれ検知に使う、メインメニュー定義とその参照先の定数。 */
      TEST_MAIN_MENU_BUILDER_SWIFT: string
      TEST_BOOKMARK_SHORTCUT_SWIFT: string
      /** ボット除外が 1 箇所に集約されているかの検査に使う集計クエリ本体。 */
      TEST_ANALYTICS_SOURCE: string
      /** 公開面（Custom Domain / workers.dev）の設定を検査する wrangler.toml 本文。 */
      TEST_WRANGLER_TOML: string
    }
  }
}

export {}
