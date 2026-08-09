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
    }
  }
}

export {}
