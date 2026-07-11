# リンククリック挙動の整理（レンダリング系 click 化 / HTML直接プレビュー対応）

<!-- derived-from ./2026-07-06-cmd-click-open-reference-design.md -->

## 概要

以下4点についてリンククリックの挙動を整理する。

1. レンダリング系（Markdown/Mermaid/SVG）の `<a>` リンク: 無修飾クリックで同一ウィンドウ内遷移できるようにする。cmd+click は新規ウィンドウで開く（意味を反転する）。
2. HTMLファイル直接プレビュー: クリック／cmd+click いずれでも無反応になっている現状を、1と同じ挙動に揃える。
3. ソースコードモードのファイルパス参照 (`.befold-path-ref`): 現状（cmd+click のみで同一ウィンドウ遷移）を変更しない。
4. ソースコードの import 文: 専用対応は行わない（現状の汎用パス検出のままとし、スコープ外とする）。

## 背景

[[2026-07-06-cmd-click-open-reference-design.md]] で cmd+click / shift+cmd+click によるファイル参照ジャンプが実装された。今回はその修飾キー割り当てを見直す。

- `viewer.html` の `#diagram-wrap` click ハンドラは `<a>`（レンダリング結果のリンク）と `.befold-path-ref`（ソースコード内パス検出）の両方を同一ロジックで処理しており、`e.metaKey` が無いと常に no-op になっている。
- `.html`/`.htm` ファイルは `ViewerWebView.swift` の `isDirectHTMLMode` で `loadFileURL` により viewer.html の JS 層を経由せず直接ロードされる。そのためクリックハンドラ自体が存在せず、リンク遷移は `decidePolicyFor` で `navigationType != .other` として一律 `.cancel` され、常に無反応になっている。
- macOS の `WKNavigationAction` は `modifierFlags: NSEvent.ModifierFlags` を公開しているため、JS注入なしで Swift 側単独で cmd 判定が可能。

## 設計

### 1. レンダリング系リンク（`viewer.html`）

`#diagram-wrap` の click ハンドラ内で `anchor`（`<a>` 経由）と `pathRef`（`.befold-path-ref` 経由）の分岐を明確に分け、修飾キーの意味は `anchor` の場合のみ変更する。

| 対象 | 無修飾クリック | cmd+click |
|---|---|---|
| `<a>`（レンダリング系リンク） | 同一ウィンドウ内遷移（`referenceActivated`, `newWindow: false`） | 新規ウィンドウ（`referenceActivated`, `newWindow: true`） |
| `.befold-path-ref`（ソースパス参照） | no-op（変更なし） | 同一ウィンドウ内遷移（変更なし、`newWindow` の概念なし） |

- 同一文書内アンカー（`href` が `#` で始まる）は従来通り preventDefault せずネイティブのスクロールに任せる。この扱いは `anchor`/`pathRef` 双方で変更しない。
- `e.shiftKey` の参照は削除する（shift+cmd+click は廃止）。

### 2. HTMLファイル直接プレビュー（`ViewerWebView.swift`）

JS注入は行わず、Swift側の `decidePolicyFor navigationAction` のみで完結させる。

- `navigationAction.navigationType == .linkActivated` かつ href が `#` で始まらない場合にのみ介入する。
  - `#` で始まるフラグメントリンクは `.allow` してネイティブスクロールに任せる（decidePolicyFor で分岐しない）。
- 対象リンクは常に `.cancel` し、`navigationAction.modifierFlags.contains(.command)` の有無に応じて [[2026-07-06-cmd-click-open-reference-design.md]] の `handleOpenReference` 相当のロジック（`ReferenceResolver.resolve` → 外部URL/ローカルファイル/未対応の3分岐）をそのまま呼び出す。
  - cmd無し: 同一ウィンドウ内遷移（ローカルファイルは `switchFile(to:)`、外部URLは `NSWorkspace.shared.open`）
  - cmdあり: 新規ウィンドウ（`AppDelegate.shared?.openViewer` 経由）
- `.other`（初回ロード）は従来通り `.allow`。

`handleOpenReference` は現状 JSブリッジのpayload形状(`href: String, isExternal: Bool, newWindow: Bool`)に依存した引数を取っているため、`decidePolicyFor` からも共通利用できるよう、`isExternal` を `ReferenceResolver.resolve` の結果から導出する形に整理する（呼び出し側での判定の重複をなくす）。実装時に既存シグネチャをどこまで変えるかは差分を見て判断する。

### 3. ソースコードモードのファイルパス参照

変更なし。セクション1で `pathRef` 分岐を独立させることで、既存の「cmd+click のみで同一ウィンドウ遷移」という挙動はそのまま維持される。

### 4. import文の特別対応

スコープ外とする。既存の `_PATH_RE`（スラッシュ入り相対/絶対パス + 既知拡張子）が `import Foo from './bar.ts'` のようなスラッシュ入りimportを副次的に拾うのは現状通り活用するが、`import Foundation` のようなベアなモジュール名はLSP相当の意味解析なしには解決できないため、今回の対応には含めない。

## テスト方針

- **JS側**（click ハンドラの分岐、修飾キー判定）: 既存方針通り自動テスト対象外。`/webview-smoke` で手動確認する。
- **Swift側**: `befoldTests/` に以下を追加・更新する。
  - `decidePolicyFor` の `modifierFlags` 判定によるディスパッチ分岐（cmd無し→同一ウィンドウ、cmdあり→新規ウィンドウ）
  - `#` フラグメントの場合に介入しないこと
  - 既存の `ReferenceResolverTests` は変更なしのはずだが、`isExternal` 導出ロジックを整理した場合はその単体テストを追加する
