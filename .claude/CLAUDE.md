# befold

macOS 向け Mermaid ダイアグラム・ビューアアプリ。
`.mmd` / `.md` ファイルを監視し、mermaid.js でリアルタイムにプレビューする。

## アーキテクチャ

```
befold.app (Swift / AppKit + SwiftUI)
  ├── AppDelegate            # ライフサイクル・メニュー・各コーディネータの束ね
  │     ├── ViewerWindowManager    # ウィンドウ生成・管理とセッション記録の更新
  │     ├── SessionRestorer        # 前回セッションのタブ構成の保存/復元
  │     └── UpdateCheckCoordinator # 更新チェックの実行と表示ポリシー
  ├── FileWatcher        # DispatchSource によるファイル監視（0.2s デバウンス）
  ├── ViewerStore        # @Observable 表示状態（content / error / deleted、FileReading で読込を抽象化）
  └── ViewerWebView      # WKWebView（NSViewRepresentable）
        ├── 同梱アセット（viewer.html / mermaid.min.js / markdown-it.min.js / style.css）
        └── JS ブリッジ: ViewerBridge 経由で evaluateJavaScript("render(content, type)")
```

ファイル変更は `FileWatcher → ViewerStore → evaluateJavaScript` の
同一プロセス内伝搬で反映する。

## 技術スタック

- Swift 6 / AppKit + SwiftUI（macOS 14+）
- WKWebView（mermaid.js / markdown-it.js レンダリング）
- DispatchSource（ファイル監視）
- XcodeGen（プロジェクト生成）/ Swift Package Manager（ビルド）

## プロジェクト構成

```
BefoldApp/
├── project.yml              # XcodeGen 定義
├── Package.swift            # SPM ビルド用
├── befold/
│   ├── App/                 # AppDelegate, DocumentController, ViewerWindowController
│   ├── Viewer/              # ViewerStore, ViewerWebView, ViewerContentView, FileType
│   ├── FileWatching/        # FileWatcher, Debouncer
│   └── Resources/           # viewer.html, style.css, mermaid.min.js, markdown-it.min.js
└── befoldTests/            # Swift Testing テスト
```

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
