// Atlas によるスキーマ管理。
// desired state を schema/schema.sql に置き、差分を migrations/ に生成する。
// 生成物は `wrangler d1 migrations apply` で D1 に適用する。
env "local" {
  src = "file://schema/schema.sql"
  dev = "sqlite://dev?mode=memory"

  // 既定の atlas フォーマット（1 マイグレーション = 1 ファイル）を使う。
  // wrangler d1 migrations は migrations/ 内の .sql をファイル名順に適用するため、
  // up/down 2 ファイルに分かれる形式は使えない。
  migration {
    dir = "file://migrations"
  }
}
