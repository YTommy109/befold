# リンククリック挙動の整理（レンダリング系 click 化 / HTML直接プレビュー対応）

<!-- derived-from ./2026-07-06-cmd-click-open-reference-design.md -->
<!-- supersedes ./2026-07-06-cmd-click-open-reference-design.md#インタラクションモデル -->

## 概要

以下4点についてリンククリックの挙動を整理する。

1. レンダリング系（Markdown/Mermaid/SVG）の `<a>` リンク: 無修飾クリックで同一ウィンドウ内遷移できるようにする。cmd+click は新規ウィンドウで開く（意味を反転する）。
2. HTMLファイル直接プレビュー: クリック／cmd+click いずれでも無反応になっている現状を、1と同じ挙動に揃える。
3. ソースコードモードのファイルパス参照 (`.befold-path-ref`): 現状（cmd+click のみで同一ウィンドウ遷移）を変更しない。
4. ソースコードの import 文: 専用対応は行わない（現状の汎用パス検出のままとし、スコープ外とする）。

本設計は [[2026-07-06-cmd-click-open-reference-design.md]] のインタラクションモデル節
（「無修飾クリックは no-op。befold はブラウザではなくプレビューである」という根拠を含む）を、
レンダリング系リンクについて置き換えるものである。

## 背景

[[2026-07-06-cmd-click-open-reference-design.md]] で cmd+click / shift+cmd+click によるファイル参照ジャンプが実装された。今回はその修飾キー割り当てを見直す。

- `viewer.html` の `#diagram-wrap` click ハンドラは `<a>`（レンダリング結果のリンク）と `.befold-path-ref`（ソースコード内パス検出）の両方を同一ロジックで処理しており、`e.metaKey` が無いと常に no-op になっている。
- 同一文書内アンカー（`#...`）は、`decidePolicyFor` が `.other` 以外のナビゲーションを一律 `.cancel` するため、ネイティブ遷移ではなく **JS 側で `preventDefault()` + `scrollIntoView({behavior:'smooth'})` により明示的にスクロール**している（2026-07-06 設計書の「preventDefault せず既定動作に任せる」という記述は実装と異なっており、実態はこちら）。
- `.html`/`.htm` ファイルは `ViewerWebView.swift` の `isDirectHTMLMode` で `loadFileURL` により viewer.html の JS 層を経由せず直接ロードされる。このモードでは `allowsContentJavaScript = false` にしているためクリックハンドラの JS 注入はそもそも使えず、リンク遷移は `decidePolicyFor` で `navigationType != .other` として一律 `.cancel` され、常に無反応になっている。
- macOS の `WKNavigationAction` は `modifierFlags: NSEvent.ModifierFlags` を公開しているため、JS注入なしで Swift 側単独で cmd 判定が可能。
- ただし `decidePolicyFor` に届くのは元の href 文字列ではなく **WKWebView が解決済みの絶対 URL**（`file:///.../foo.md`、`https://...` 等）である。`ReferenceResolver.resolve` は `http`/`https` 以外のスキームを原則 `.unsupported` に落とすため、`file://` URL をそのまま渡すことはできない。この制約がセクション2の設計を規定する。
- `handleOpenReference(href:isExternal:newWindow:)` の `isExternal` 引数は現状すでに未使用で、外部/ローカル判定は `ReferenceResolver.resolve` の返り値に一本化済みである。

## 設計

### 1. レンダリング系リンク（`viewer.html`）

`#diagram-wrap` の click ハンドラ内で `anchor`（`<a>` 経由）と `pathRef`（`.befold-path-ref` 経由）の分岐を明確に分け、修飾キーの意味は `anchor` の場合のみ変更する。

| 対象 | 無修飾クリック | cmd+click |
|---|---|---|
| `<a>`（レンダリング系リンク） | 同一ウィンドウ内遷移（`referenceActivated`, `newWindow: false`） | 新規ウィンドウ（`referenceActivated`, `newWindow: true`） |
| `.befold-path-ref`（ソースパス参照） | no-op（変更なし） | 同一ウィンドウ内遷移（変更なし、`newWindow` の概念なし） |

- 同一文書内アンカー（`href` が `#` で始まる）は従来通り、JS 側で `preventDefault()` + `scrollIntoView` により明示的にスクロールする（背景の通り、ネイティブ遷移には任せられない）。この扱いは `anchor`/`pathRef` 双方で変更しない。
- `e.shiftKey` の参照は削除する（shift+cmd+click は廃止）。
- `referenceActivated` payload の `isExternal` フィールドは削除する。Swift 側の `handleOpenReference` は既にこれを使っておらず（判定は `ReferenceResolver.resolve` に一本化済み）、JS 側の `/^https?:\/\//` 判定・`onOpenReference` クロージャの引数・メッセージハンドラの取り出しをまとめて消す。payload は `{ href: String, newWindow: Bool }` になる。
- 無修飾クリックで `.unsupported`（`mailto:` 等）に解決される href は従来通り no-op（`handleOpenReference` の既存分岐のまま）。

### 2. HTMLファイル直接プレビュー（`ViewerWebView.swift`）

JS注入は行わず（`allowsContentJavaScript = false` のため不可能でもある）、Swift側の `decidePolicyFor navigationAction` のみで完結させる。

- **介入は `isDirectHTMLMode` の場合のみ**。viewer.html モードの `decidePolicyFor` は従来通り（`.other` のみ `.allow`、他は `.cancel`）とする。viewer.html モードでは JS がリンクを `preventDefault` するため通常 `.linkActivated` は届かないが、コンテキストメニューの「リンクを開く」等 JS を迂回する経路があり得るので、明示的にゲートする。
- direct HTML モードでの `.linkActivated` は、`navigationAction.request.url` を使って **`ReferenceResolver` を通さず URL で直接分岐**する（相対パス解決は WKWebView が済ませている）:
  1. **同一文書内フラグメント**: `request.url` と `webView.url` がフラグメントを除いて一致する場合は `.allow` し、ネイティブのフラグメントスクロールに任せる（direct HTML モードでは JS スクロールが使えないため、こちらはネイティブ任せでよい）。
  2. **ローカルファイル**（`url.isFileURL`）: `.cancel` し、フラグメントを除去した URL で存在確認（無ければ既存の `showFileNotFoundAlert` 相当）。cmd 無しは `switchFile(to:)`（同一ウィンドウ）、cmd あり（`navigationAction.modifierFlags.contains(.command)`）は `AppDelegate.shared?.openViewer`（新規ウィンドウ）。
  3. **外部URL**（`http`/`https`）: `.cancel` し、cmd の有無に関わらず `NSWorkspace.shared.open`（外部URLに「新規ウィンドウ」の概念は適用できない）。
  4. **その他**（`mailto:` 等）: `.cancel` して no-op。
- `.other`（初回ロード）は従来通り `.allow`。
- 共通化するのは「開く」処理（`handleOpenReference` の `.external`/`.localFile` 分岐以降: 存在確認・アラート・`switchFile`/`openViewer` の呼び分け）のみとし、`ReferenceResolver.resolve` のシグネチャは変更しない。
- テスト容易性のため、ポリシー判定は `WKNavigationAction` に依存しない純関数（例: `static func linkPolicy(url:currentURL:modifierFlags:isDirectHTMLMode:) -> 判定enum`）に抽出し、`decidePolicyFor` はその結果をディスパッチするだけにする（既存の `ViewerWebViewCoordinatorTests` が static ヘルパーをテストする方式と揃える）。

### 3. ソースコードモードのファイルパス参照

変更なし。セクション1で `pathRef` 分岐を独立させることで、既存の「cmd+click のみで同一ウィンドウ遷移」という挙動はそのまま維持される。

既知のトレードオフとして、変更後は同じ cmd+click が `<a>` では「新規ウィンドウ」、`.befold-path-ref` では「同一ウィンドウ」と対象種別で意味が異なり、また shift+cmd 廃止により pathRef を新規ウィンドウで開く手段は無くなる。今回は挙動変更のスコープをレンダリング系リンクに限定するためこれを許容し、pathRef 側の修飾キー体系を揃えるかは必要になった時点で別タスクとして検討する。

### 4. import文の特別対応

スコープ外とする。既存の `_PATH_RE`（スラッシュ入り相対/絶対パス + 既知拡張子）が `import Foo from './bar.ts'` のようなスラッシュ入りimportを副次的に拾うのは現状通り活用するが、`import Foundation` のようなベアなモジュール名はLSP相当の意味解析なしには解決できないため、今回の対応には含めない。

## テスト方針

- **JS側**（click ハンドラの分岐、修飾キー判定）: 既存方針通り自動テスト対象外。`/webview-smoke` で手動確認する。
- **Swift側**: `WKNavigationAction` はモック・生成が困難なため、セクション2で抽出する純関数を対象に `befoldTests/` へ追加する。
  - 同一文書内フラグメント（現在URLとフラグメント除去で一致）→ 介入しない（`.allow` 相当）
  - ローカル `file://` URL: cmd 無し→同一ウィンドウ、cmd あり→新規ウィンドウのディスパッチ分岐
  - `http`/`https` → cmd の有無に関わらず外部オープン
  - `mailto:` 等 → no-op
  - viewer.html モード（`isDirectHTMLMode == false`）では介入しないこと
- `ReferenceResolver` は変更しないため `ReferenceResolverTests` は変更なし。`isExternal` 削除に伴うメッセージハンドラの変更は既存テスト方式の範囲で扱う。
