# Markdown を読む立場の人にとっての利点の棚卸し

<!-- derived-from ../../dev/native-app-design.md -->

> **これは 2026-08-16 時点の設計スナップショットです。**
> 現在の仕様は [`docs/dev/native-app-design.md`](../../dev/native-app-design.md)
> が単一の情報源。この文書は当時の意図と検討経緯を残すためのもので、
> 現在の実装と食い違っていることがある。着手前に必ずコードで裏を取ること。

## 目的と範囲（TASK-484.3）

befold はエンジニア向けに開発しているが、エンジニアでなくても Markdown を
読む立場の人（ライター・企画・レビュアーなど）に効く利点がある。この文書は
サイトのコピーを書き直す前の棚卸しで、成果物は**文章ではなく、訴求に使える
利点の優先順位付き一覧**。各項目に実装の裏付け（`file:line`）を添える。
消費先は TASK-484.4（LP の訴求セクション書き直し）。

優先順位の基準は次の 3 つ。

1. **学習ゼロで価値が伝わるか** — この層は「ビューアを導入する」動機が薄く、
   説明が要る機能は入口にならない
2. **この層の作業（読む・確認する・共有する）に直接効くか** — 開発ワークフロー
   前提の機能（git 差分など）はエンジニア側の訴求に譲る
3. **サイトに未掲載か** — 現在の `site/src/views/shared.tsx` の
   FEATURES / MORE_FEATURES に無い項目は、この層向けセクションの新規材料になる

## 優先度 A — 入口になる訴求（学習ゼロで価値が伝わる）

### A1. Finder で Space を押すだけでプレビュー（QuickLook）

アプリの使い方を覚える前に価値が体験できる、この層にとって最良の入口。

- 裏付け: `BefoldApp/BefoldQuickLook/Info.plist:24-27`
  （`com.apple.quicklook.preview` 拡張の宣言）、
  `BefoldApp/BefoldQuickLook/PreviewViewController.swift:17`
  （`preparePreviewOfFile(at:)` で描画）
- docs: `docs/dev/quicklook.md:5`、`docs/dev/native-app-design.md` の
  モジュール構成（appex）
- 注意: QuickLook は `RendererFeatures.quickLookRestricted`
  （`BefoldApp/BefoldQuickLook/PreviewViewController.swift:11`）で動作し、
  検索・パスリンク・画像埋め込み等の対話機能は無効。サイトでは
  「プレビューが見える」以上のことを QuickLook に紐付けて書かない

### A2. GitHub と同じ見た目で描画される

「レビュー対象と同じ見た目で読める」ことがこの層の安心材料。
サイト未掲載。

- 裏付け: `BefoldApp/BefoldKit/Resources/style.css:24-26`
  （github-markdown.css をライト/ダーク別に読み分け）、
  `BefoldApp/viewer-src/markdown.js:107-113`
  （markdown-it を `linkify: true` + highlight.js で構成）、
  `BefoldApp/package.json:38-42`
  （github-markdown-css 5.9.0 / highlight.js 11.11.1 / markdown-it 14.2.0）
- docs: `docs/dev/native-app-design.md:287-289`（技術スタック）
- 注意: URL 自動リンク化は scheme 付き URL のみ
  （`BefoldApp/viewer-src/markdown.js:125` で `fuzzyLink: false`）。
  「`example.com` のような素のドメインもリンクになる」とは書かない

### A3. 保存すると 0.2 秒で表示が更新される

どのエディタと組み合わせても成立する訴求。エディタの atomic save や
リネームにも追従して監視を張り直す。

- 裏付け: `BefoldApp/befold/FileWatching/FileWatcher.swift:15`
  （`defaultDebounceDelay = 0.2`）、同 `:133-177`
  （`resolveRename` が atomic save / rename を判別して監視を切替）、
  `BefoldApp/befold/Viewer/ViewerStore+FileWatching.swift:22`
  （onChange → 再読込、onRename → パス差し替え）
- docs: `docs/dev/native-app-design.md` の「ファイル監視」節（:187-195）

### A4. mermaid のコードブロックがそのまま図として描かれる

企画書・設計レビュー文書に含まれる図が、コードのまま見えるのではなく
図として読める。構文エラーは詳細付きで表示される。

- 裏付け: `BefoldApp/viewer-src/markdown.js:134`
  （```` ```mermaid ```` フェンスを `<pre class="mermaid">` へ）、
  `BefoldApp/viewer-src/mermaid.js:75`（`mermaid.run` で SVG 描画）、
  同 `:35-43`（`parseError` をエラーパネルに表示）
- docs: `docs/dev/native-app-design.md` の「表示仕様」節

## 優先度 B — 読み・レビューの作業を直接支える機能

### B1. 本文内検索（⌘F、大文字小文字・単語一致・正規表現）

長い文書を確認する作業の基本動作。サイト未掲載。

- 裏付け: `BefoldApp/befold/App/MainMenuBuilder.swift:136`（⌘F の割り当て）、
  `BefoldApp/viewer-src/find.js:10-12`（3 トグルから検索正規表現を構成）、
  `BefoldApp/BefoldKit/Resources/viewer.html:41`（検索バー UI の 3 ボタン）、
  `BefoldApp/BefoldKit/FindOptionsPreference.swift:12-21`（トグルの永続化）
- docs: `docs/dev/native-app-design.md:211`（表示仕様）

### B2. 見出しアンカーが GitHub 互換で動く

「この節を見て」の共有リンク・文書内の目次リンクがそのまま機能する。
サイト未掲載。

- 裏付け: `BefoldApp/viewer-src/markdown.js:49-90`
  （GitHub 互換 slug の生成と `heading_open` への ID 付与、重複は連番）、
  `BefoldApp/viewer-src/reference-clicks.js:46-51`
  （`#` リンクをスムーズスクロールで解決）、テスト
  `BefoldApp/BefoldKit/Resources/__tests__/viewer-markdown-heading-ids.test.js`

### B3. ローカル画像が表示される

スクリーンショットを貼った確認依頼・レビュー文書がそのまま読める。
サイト未掲載。

- 裏付け: `BefoldApp/BefoldKit/MarkdownImageEmbedder.swift:41-65`
  （相対パス画像を base64 data URI に埋め込む前処理。CSP 対応）、
  呼び出しは `BefoldApp/BefoldRenderKit/RenderableContent.swift:13-15`
- docs: `docs/dev/native-app-design.md:173`
- 注意: QuickLook では無効（`RendererFeatures.embedImages` が
  `quickLookRestricted` で false）。本体アプリでは条件なし

### B4. 印刷・PDF 書き出し（File > Print…）

紙・PDF で回覧する文化圏に効く。サイト未掲載。

- 裏付け: `BefoldApp/befold/App/MainMenuBuilder.swift:100-105`
  （File メニューの Print。キーは ⇧⌘P。⌘P は Quick Open）、
  `BefoldApp/befold/App/WebViewDocumentRenderer.swift:68-78`
  （`webView.printOperation` で標準印刷パネルを表示）
- 注意: PDF は macOS 標準の印刷パネルの「PDF として保存」経由。
  専用のエクスポート機能ではないので「PDF エクスポート」とは書かない

## 優先度 C — 「困らない」系（補助的な訴求）

### C1. スクロール位置・ズーム・タブ構成の復元

昨日読んでいた場所から続きが読める。サイト掲載済み
（「タブ & セッション復元」「ズーム & ダークモード」）。

- 裏付け: `BefoldApp/befold/App/ScrollPositionStore.swift:14-15`
  （表示モード別・ファイル単位のスクロール位置永続化）、
  `BefoldApp/befold/App/ZoomStore.swift:17`（ファイル単位のズーム倍率）、
  `BefoldApp/befold/App/SessionStore.swift:6-15` +
  `BefoldApp/befold/App/SessionRestorer.swift:161`（タブ構成の保存と復元）
- docs: `docs/dev/native-app-design.md:122-131` / `:209-210`

### C2. 100MB までの Markdown が段階描画で開ける

他ツールが固まるサイズでも開ける、という安心材料。サイト掲載済み
（「大きなファイルも開ける」）。

- 裏付け: `BefoldApp/BefoldKit/NormalizedTextCache.swift:15`
  （`maxFileSizeBytes = 100MB`）、
  `BefoldApp/BefoldKit/ViewerLoadPipeline.swift:69-99`
  （チャンク可能種別は先頭チャンクのみ読んで `.chunked`）、
  `BefoldApp/befold/Viewer/ViewerStore+Loading.swift:13-26`（逐次 append）
- docs: `docs/dev/text-loading-dataflow.md:124` / `:234`
- 注意: 100MB は Markdown 等チャンク可能な種別の上限。mmd / svg / html は
  50MB（`BefoldApp/BefoldKit/ContentLoader.swift:7`）。サイトで数字を出す
  なら「Markdown は 100MB まで」に限定する

### C3. Shift_JIS / EUC-JP の自動判別

社内に残る古い文書・他システムからの書き出しが文字化けせず開ける。
日本語圏のこの層に固有に効く。サイト未掲載。

- 裏付け: `BefoldApp/BefoldKit/TextEncoding.swift:95-109`
  （`detectLegacyEncoding`。lossy 変換になった場合は不採用）、
  同 `:128-137`（`detectAndDecodeText` の判定 → 再試行フロー）
- docs: `docs/dev/text-loading-dataflow.md:239-250`（エンコーディング対応）

### C4. 本文中のファイルパスが、実在するものだけリンクになる

仕様書が参照する別ファイルへワンクリックで移動できる。パス表記が
題材になる時点でややエンジニア寄りのため、この層向けとしては最後に置く。

- 裏付け: `BefoldApp/viewer-src/path-refs.js:182-231`
  （候補を Swift へ問い合わせ、解決できたものだけリンク化。
  解決不能は `befold-link-dead` として無効化）、
  `BefoldApp/BefoldKit/TrackedPathResolver.swift:95-116`
  （実在確認 → git 追跡ファイル索引へのフォールバック。
  フォールバック一致も再度実在確認）
- docs: `docs/dev/native-app-design.md:174`（`ReferenceResolver`）
- 注意: QuickLook では無効（`referenceActivation` ホスト機能が
  `quickLookRestricted` で無効）。本体アプリでは条件なし

## 書いてはいけないもの（未実装・スコープ外）

- **目次・アウトライン表示は存在しない。** 見出しアンカー（B2）はあるが、
  サイドバーやパネルに見出し一覧を出す機能は無い
- **編集機能は無い。** befold はビューアであり、エディタとしての訴求を
  一切しない
- **図のエクスポート（SVG / PNG）は無い。** PDF も専用機能ではなく
  印刷パネル経由（B4 の注意を参照）

## TASK-484.4 への申し送り

- サイト未掲載でこの層に効く新規材料は **A2（GitHub の見た目）・
  B1（本文内検索）・B2（アンカー）・B3（ローカル画像）・B4（印刷/PDF）・
  C3（文字コード自動判別）** の 6 つ。A1 / A3 / A4 / C1 / C2 は既存の
  FEATURES に対応項目があり、この層向けの言い換えで再利用できる
- 各項目の「注意」に挙げた言い過ぎ防止（fuzzyLink 無効・PDF は印刷パネル
  経由・100MB は Markdown のみ・QuickLook の機能制限）は、コピーの
  文言確定時にそのまま制約として扱うこと
