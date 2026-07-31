# befold

macOS 向けのドキュメント・ダイアグラムビューアアプリ。
`.mmd` / `.md` を中心に SVG / HTML / CSV・TSV / 画像 / PDF / ソースコードを
プレビューし、ファイル変更を監視してプロセス内でリアルタイム更新する。

## アーキテクチャ

**詳細な構成図・モジュールツリー・コンポーネント一覧は
[`docs/dev/native-app-design.md`](../docs/dev/native-app-design.md) が単一の情報源。
ここには最低限の見取り図だけを置く（同じ内容を二重管理しない）。**

ソースはすべて `BefoldApp/` 配下にあり、主要ターゲットは次のとおり。

| ターゲット | 責務 |
|---|---|
| `befold/` | 本体アプリ（AppKit + SwiftUI）。`App/`（ライフサイクル・ウィンドウ管理・各種永続化ストア）、`Viewer/`（`ViewerStore` / `ViewerWebView` / サイドバー・検索）、`FileWatching/`（`FileWatcher` / `Debouncer`）、`Updates/`（`UpdateChannel`） |
| `BefoldKit/` | コアロジック＋レンダリングアセット（`ContentLoader` / `FileType` / `ViewerBridge` / `RendererFeatures` ほか、`Resources/` に viewer.html・mermaid・markdown-it 等を同梱） |
| `BefoldRenderKit/` | 描画エンジン `ViewerRenderer`（WKWebView ドライバ）。本体アプリと QuickLook 拡張で共有 |
| `BefoldQuickLook/` | QuickLook 拡張（appex）。`ViewerRenderer` を直接使い 1 回描画 |
| `BefoldCLI/` / `befold-cli/` | CLI 共有ライブラリと `befold` 実行ファイル |
| `BefoldTestSupport/` / `befoldTests/` / `befoldCLITests/` | テスト共有ヘルパーと Swift Testing テスト |

- ファイル変更は `FileWatcher → ViewerStore → ViewerRenderer(evaluateJavaScript)` の
  同一プロセス内伝搬で反映する。
- CLI 起動は `befold-cli → BefoldCLI → befold.app` で伝搬する。
- 自動アップデートは Sparkle 2（`AppDelegate` が `SPUStandardUpdaterController` を保持）。

## 技術スタック

- Swift 6 / AppKit + SwiftUI（macOS 14+）
- WKWebView（mermaid.js / markdown-it.js レンダリング）
- DispatchSource（ファイル監視）
- XcodeGen（プロジェクト生成）/ Swift Package Manager（ビルド）

## コマンド

```bash
# Swift ネイティブアプリ（BefoldApp/）
cd BefoldApp
swift build                  # ビルド
swift test                   # テスト（要 Xcode.app）
xcodegen generate            # .xcodeproj を再生成
xcodebuild build -scheme befold  # Xcode ビルド（要 Xcode.app）
```

## Swift コーディング規約

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）
- `@MainActor @Observable` を ViewerStore に使用
- FileWatcher は `@unchecked Sendable`（内部 GCD キューでスレッド安全性を保証）
- UI コンポーネントは SwiftUI、ウィンドウ管理は AppKit（NSWindowController）

## テスト規約

- **ユニットテスト**: `befoldTests/` — Swift Testing フレームワーク
- テスト関数名は英語 camelCase（SwiftLint の `identifier_name` が非 ASCII 開始の名前を弾く）。
  日本語の説明が必要なら `@Test("日本語の説明")` の表示名で付ける
- FileWatcher: 一時ファイルによる実ファイルシステムテスト
- ViewerStore: `@MainActor` テスト（状態遷移検証）
- WebView/GUI 層: 自動テスト対象外（リリース前手動チェック）

## 完了基準

- タスク中に発見したリファクタリング課題は「次回触るときに」と後回しにせず、同じタスク内で完了する
- TDD の原則に従い、動作する状態にした後、設計のブラッシュアップまでを 1 タスクとする
- スコープが大きすぎる場合はユーザーに相談して判断を仰ぐ（勝手に先送りしない）

## コミット規約

Conventional Commits + 日本語:

```
feat: Mermaid ビューア画面を追加する
fix: ファイル変更検知が2回通知される問題を修正する
chore: XcodeGen 設定を更新する
```

## フィーチャーゲート（開発中機能の dev 限定露出）

- 未完成機能は `FeatureGate.inProgressFeaturesEnabled` で囲い、dev/DEBUG ビルドでのみ露出する。
  判定は「バージョン文字列のプレリリース接尾辞（`-dev.N`）」由来で、`UpdateChannel`（ユーザー設定）は流用しない。
- フラグは一時的な足場。stable に載せると決めた時点で分岐を撤去しデフォルト有効化し、撤去タスクを backlog に登録する。
- 検証は「ロジックはユニットテスト、ON は dev リリースの dogfood、OFF は次回 stable リリース」で担保する。
