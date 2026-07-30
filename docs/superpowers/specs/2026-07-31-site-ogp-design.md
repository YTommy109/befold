# 配布サイトの OGP 対応 設計

<!-- derived-from ../../../backlog/tasks/task-189 - 配布サイト（紹介ページ）を現状の機能・訴求ストーリーに合わせてリニューアルする.md -->

## 背景

配布サイト `https://befold.tommy109.workers.dev/` を SNS に投稿しても、意図した見た目のカードが表示されない。
`site/src/views/landing.tsx` の `<head>`（L177-186）には `charset` / `viewport` / `title` /
`description` / `stylesheet` しかなく、`og:*` も `twitter:*` も存在しない。
このため各 SNS はページ内から適当な画像を推測し、アスペクト比の合わない切り抜きになる。

`site/src/views/dashboard.tsx` も同様だが、こちらは Basic 認証で保護されており共有対象ではない。

## ゴール

配布サイトの URL を SNS に投稿したとき、1200×630 の専用画像を持つ大判カード
（`summary_large_image`）が意図どおりに表示される。

## 決定事項

| 論点 | 決定 |
| ---- | ---- |
| 画像の用意 | 専用の静的 PNG を 1 枚作り、リポジトリにコミットする |
| 絵柄 | 左にコピー、右にアプリ画面 |
| 素材 | Markdown に Mermaid を埋め込んだ画面を撮り下ろす（`site/tools/ogp-screenshot.png`） |
| 言語 | 英語（画像内コピー・`og:title`・`og:description` すべて） |
| 生成方法 | HTML テンプレート → ヘッドレス Chrome で撮影 → PNG をコミット |

Worker 実行時の画像生成は行わない。ページが実質トップ 1 枚である現状に対して
オーバーキルであり、Worker に画像生成依存を持ち込む価値がない。

## 成果物

### 1. `site/public/images/ogp.png`

1200×630 の PNG。`[assets]` バインディング経由で `/images/ogp.png` として配信される
（`site/wrangler.toml` の `directory = "public"`）。

レイアウト:

```
┌──────────────────────────────────────────┐
│  befold                    ╔════════════╗ │
│                            ║            ║ │
│  Read Markdown             ║  アプリ画面  ║ │
│  comfortably.              ║ (screenshot ║ │
│                            ║     -1)     ║ │
│  macOS 14+ · Free          ╚════════════╝ │
└──────────────────────────────────────────┘
```

配色・フォントは `site/public/style.css` の既存トーンに合わせる。
小さいカードでも読めるよう、見出しは十分な字面サイズを取る。

### 2. `site/tools/ogp-template.html`

上記 PNG を生成した元の HTML。1200×630 固定サイズ。
画像を作り直せるよう、生成手順を記した短い README コメントを含める。
Worker からは配信されない（`public/` の外に置く）。

### 3. `site/src/views/landing.tsx` のメタタグ

`<head>` に以下を追加する。

```
<link rel="canonical" href="{origin}/" />
<meta property="og:type" content="website" />
<meta property="og:site_name" content="befold" />
<meta property="og:title" content="befold — File Viewer for macOS" />
<meta property="og:description" content="{既存の description と同一}" />
<meta property="og:url" content="{origin}/" />
<meta property="og:image" content="{origin}/images/ogp.png" />
<meta property="og:image:width" content="1200" />
<meta property="og:image:height" content="630" />
<meta property="og:image:alt" content="befold — a macOS file viewer showing a rendered Mermaid diagram" />
<meta name="twitter:card" content="summary_large_image" />
```

`og:image` と `og:url` は絶対 URL でなければクローラが解決できない。
ホスト名をハードコードすると staging（`befold-staging.*.workers.dev`）で
本番 URL を指してしまうため、リクエストの origin から組み立てる。

`Landing` コンポーネントは現状 origin を受け取らないので、`site/src/routes/public.tsx` の
`publicRoutes.get('/')`（L10）で `new URL(c.req.url).origin` を求めて props で渡す。

`og:title` / `og:description` は既存の `<title>` / `<meta name="description">` と同じ文字列を使い、
定数として切り出して二重管理を避ける。

## テスト

`site/test/public.test.ts` に追加する（Vitest 4 + `@cloudflare/vitest-pool-workers`）。
HTML の meta を検証するテストは現状存在しないため、すべて新規。

1. `/` のレスポンス HTML に `og:image` が絶対 URL（`http://…/images/ogp.png`）として含まれる
2. `twitter:card` が `summary_large_image` である
3. `og:url` がリクエストの origin と一致する（ハードコードでないことの確認）
4. `/images/ogp.png` が 200 で返る

3 はホスト名を変えた 2 通のリクエストで検証し、それぞれの origin が反映されることを確かめる。

## スコープ外

- `/dashboard` の OGP — Basic 認証で保護されており共有されない
- Worker での動的 OGP 生成
- favicon / `theme-color` / JSON-LD — 今回の依頼と別件。必要なら別タスクとする
- 言語別 OGP の出し分け — ページが ja/en を 1 枚の HTML に同居させている構造上、カードは 1 種類しか出せない

## 確認方法

デプロイ後、staging と本番それぞれで以下を確認する。

- `curl -s <url> | grep 'og:'` で絶対 URL が正しいこと
- カードのプレビュー（各 SNS のデバッガ、または任意の OGP チェッカ）で
  画像が切れずに表示されること
