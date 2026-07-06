# cmd+click / shift+cmd+click によるファイル参照ジャンプ

## 概要

レンダリングされた Markdown 内のリンクと、コードブロック内に現れるファイルパス文字列に対して、cmd+click で参照先ファイルを現在のウィンドウで開き、shift+cmd+click で新しいウィンドウで開けるようにする。無修飾クリックは何も行わない（no-op）。

## 背景

- 現状 `ViewerWebView.swift` の `Coordinator` は `WKNavigationDelegate` の `didFinish` のみを実装しており、`decidePolicyFor` のハンドラが存在しない。そのため Markdown リンクをクリックすると WKWebView の既定のナビゲーション動作が発火し、レンダリング中のプレビューが壊れる（リンク先へ同一 WebView がナビゲートしようとする）潜在的な不具合がある。
- `viewer.html` の markdown-it 設定にはリンクのクリックハンドラや `link_open` レンダラールールの上書きは存在せず、`<a href>` はプレーンなまま出力される。
- コードブロック内のファイルパス文字列（例: `./foo.swift:42`）はハイライト済みのプレーンテキストであり、クリック検出の仕組みは存在しない。
- 相対パス解決・「参照先を開く」導線は存在しないが、既存の類似機能（`ViewerWindowController.switchFile(to:)` で現在ウィンドウのファイル切り替え、`ViewerWindowManager.openViewer(for:)` で新規ウィンドウを開く。いずれも同一ファイルの多重オープンを防ぐ重複排除ロジックを内包）を再利用できる。

## インタラクションモデル

WKWebView の既定ナビゲーションに依存する経路を残さないため、リンク／パスへのクリックは常に JS 側で横取りし `preventDefault()` する。その上で:

| 操作 | 対象が同一文書内アンカー(`#...`) | 対象がファイル参照・外部URL |
|---|---|---|
| 無修飾クリック | 既定動作（スクロール）をそのまま残す | 何もしない (no-op) |
| cmd+click | 対象外（アンカーは cmd の有無に関わらずスクロールのみ） | 参照先を現在のウィンドウで開く |
| shift+cmd+click | 対象外 | 参照先を新しいウィンドウで開く |

これは Xcode/VSCode の「cmd+click でジャンプ」に近い操作感で、befold がブラウザではなく「プレビュー」であることに合わせている。

## 設計

### JS 側: クリック検出とビジュアル演出（`Resources/viewer.html`）

**Markdown リンク (`<a>`)**

- レンダリング後のコンテナに `click` の委譲リスナーを1つ登録する。
- `href` が `#` で始まる場合は preventDefault せず既定動作に任せる。
- それ以外は常に `preventDefault()`。`e.metaKey` が false なら何もしない。true の場合、`isExternal = /^https?:\/\//.test(href)` を判定し、ブリッジへ post する。

**コードブロック内パスのヒューリスティック検出**

- `render()` 完了後、`<pre><code>` 配下のテキストノードを走査し、正規表現でパスらしきトークンを検出する。マッチ条件: `/` を含む（`./`・`../`・ディレクトリ区切り）、かつ既知の拡張子（swift, md, mmd, ts, tsx, js, jsx, py, rb, go, rs, java, kt, c, cpp, h, hpp, json, yaml, yml, toml, txt, html, css, sh 等）で終わる。末尾の `:数字`（行番号）は任意でマッチに含める。
- マッチ箇所を `<span class="befold-path-ref" data-path="...">` でラップする。
- **既知の制約**: シンタックスハイライトによってトークンが複数の `<span>` に分割されている場合、その境界をまたぐパスは検出されない（シンプルなヒューリスティックとして許容する）。
- `.befold-path-ref` へのクリックも同じ委譲リスナーで処理する（無修飾は no-op、cmd+click でのみ発火）。

**cmd 押下中の視覚フィードバック**

- `document` に `keydown`/`keyup` リスナーを追加し、`e.metaKey` に応じて `<body>` に `cmd-held` クラスを付け外しする。
- CSS: `.cmd-held a, .cmd-held .befold-path-ref { text-decoration: underline; cursor: pointer; }`

### ブリッジ契約（`ViewerBridge.swift`）

```swift
static let referenceActivatedMessageName = "referenceActivated"
// payload: { href: String, isExternal: Bool, newWindow: Bool }
```

`newWindow` は発火時の `e.shiftKey` をそのまま渡す。

### Swift 側: メッセージ登録とディスパッチ（`ViewerWebView.swift` 他）

- `makeNSView` で既存の `zoomChanged` ハンドラ登録と同じパターンで `referenceActivated` を `WeakScriptMessageHandler` 経由で登録する。
- `Coordinator.userContentController(_:didReceive:)` に新しい分岐を追加し、既存の `onSwitchFile` コールバックと同様の経路で新しいクロージャ（例: `onOpenReference: (_ href: String, _ isExternal: Bool, _ newWindow: Bool) -> Void`）を `ViewerWebView` → `ViewerContentView` → `ViewerWindowController` へ橋渡しする。
- ディスパッチ処理（`ViewerWindowController` または新設する小さな helper）:
  1. `isExternal` なら `NSWorkspace.shared.open(url)` して終了。
  2. ローカルパスなら、現在表示中ファイルの `deletingLastPathComponent()` を基準に `href` を絶対パスへ解決する。
  3. `FileManager.default.fileExists(atPath:)` で存在確認。存在しなければ `NSAlert` でエラーダイアログを表示して終了。
  4. 存在すれば `newWindow` で分岐:
     - `false` → 既存の `ViewerWindowController.switchFile(to:)`（現在ウィンドウ。「1ファイル1ウィンドウ」の重複排除ロジックはそのまま効く）
     - `true` → `AppDelegate.openViewer(for:)` 経由で `ViewerWindowManager.openViewer(for:)`（新規ウィンドウ。既存の重複排除ロジックがそのまま効く）

拡張子による分岐（befold 内表示 vs 外部エディタ起動）は行わない。ローカルファイルは種類を問わず既存のファイルオープン導線にそのまま委譲し、`FileType` がどう解釈するか（レンダリング表示 / コード表示）は既存ロジックに任せる。

### 対象外・no-op とする範囲

- 同一文書内アンカー（`#section`）: 既定のスクロール動作のみ。ブリッジへの通知は行わない。
- `mailto:` など、ファイル参照でも `http(s)://` でもないリンク: 何もしない。

### エラー時の動作

- ブリッジからの通知を受けて解決したパスがファイルシステム上に存在しない場合のみ `NSAlert` でエラーダイアログを表示する。それ以外（拡張子・ファイル種別起因のエラー）は既存のファイルオープン導線の挙動にそのまま従う（本機能独自のハンドリングは追加しない）。

## テスト方針

- **JS 側**（クリック検出・パス検出ヒューリスティック・cmd 演出）: 既存方針どおり WebView/GUI 層は自動テスト対象外。リリース前に手動チェック（`/webview-smoke`）でカバーする。
- **Swift 側の純粋ロジック**は `befoldTests/` に Swift Testing で単体テストを追加する:
  - 相対パス・絶対パスの解決結果
  - 存在しないパスでのエラー分岐
  - `isExternal` 判定（http/https vs ローカルパス）
  - `newWindow` フラグによる分岐先の呼び分け（`switchFile` と `openViewer` のどちらが呼ばれるかの検証）
