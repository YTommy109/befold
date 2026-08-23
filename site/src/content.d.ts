/**
 * `site/content/*.md`（記事本文）を文字列として import するための宣言。
 *
 * 実体は `wrangler.toml` の `[[rules]] type = "Text"`。バンドラが中身を
 * 文字列リテラルとして埋め込むので、実行時のファイル読み込みは起きない。
 */
declare module '*.md' {
  const content: string
  export default content
}
