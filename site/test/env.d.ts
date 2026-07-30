import type { D1Migration } from '@cloudflare/vitest-pool-workers'

// テスト実行時のみ、マイグレーション内容を渡す追加バインディングが存在する。
declare global {
  namespace Cloudflare {
    interface Env {
      TEST_MIGRATIONS: D1Migration[]
    }
  }
}

export {}
