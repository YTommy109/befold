import path from 'node:path'
import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-pool-workers'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  plugins: [
    cloudflareTest(async () => {
      // Atlas が生成したマイグレーションをテスト用 D1 に流し込むため、内容を読み込んで
      // バインディング経由でテスト側へ渡す（適用は test/setup.ts で行う）。
      const migrations = await readD1Migrations(path.join(import.meta.dirname, 'migrations'))

      return {
        singleWorker: true,
        wrangler: { configPath: './wrangler.toml' },
        miniflare: {
          // .dev.vars は gitignore 対象なので、テスト用の認証情報はここで固定する。
          bindings: {
            TEST_MIGRATIONS: migrations,
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
