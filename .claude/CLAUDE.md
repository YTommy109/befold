# mmdview

macOS 向け Mermaid ダイアグラム・ビューアアプリ。
`.mmd` / `.md` ファイルを監視し、mermaid.js でリアルタイムにプレビューする。

## アーキテクチャ

```
mmdview.app (Swift / AppKit + SwiftUI)
  ├── AppDelegate        # ライフサイクル・メニュー・ウィンドウ管理
  ├── FileWatcher        # DispatchSource によるファイル監視（0.2s デバウンス）
  ├── ViewerStore        # @Observable 表示状態（content / error / deleted）
  └── ViewerWebView      # WKWebView（NSViewRepresentable）
        ├── 同梱アセット（viewer.html / mermaid.min.js / markdown-it.min.js / style.css）
        └── JS ブリッジ: evaluateJavaScript("render(content, type)")
```

HTTP・SSE・ポート管理は不要。ファイル変更は
`FileWatcher → ViewerStore → evaluateJavaScript` の同一プロセス内伝搬で反映する。

## 技術スタック

- Swift 6 / AppKit + SwiftUI（macOS 14+）
- WKWebView（mermaid.js / markdown-it.js レンダリング）
- DispatchSource（ファイル監視）
- XcodeGen（プロジェクト生成）/ Swift Package Manager（ビルド）

## プロジェクト構成

```
MmdviewApp/
├── project.yml              # XcodeGen 定義
├── Package.swift            # SPM ビルド用
├── mmdview/
│   ├── App/                 # AppDelegate, DocumentController, ViewerWindowController
│   ├── Viewer/              # ViewerStore, ViewerWebView, ViewerContentView, FileType
│   ├── FileWatching/        # FileWatcher, Debouncer
│   └── Resources/           # viewer.html, style.css, mermaid.min.js, markdown-it.min.js
└── mmdviewTests/            # Swift Testing テスト
```

## コマンド

```bash
# Swift ネイティブアプリ（MmdviewApp/）
cd MmdviewApp
swift build                  # ビルド
swift test                   # テスト（要 Xcode.app）
xcodegen generate            # .xcodeproj を再生成
xcodebuild build -scheme mmdview  # Xcode ビルド（要 Xcode.app）
```

## Swift コーディング規約

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）
- `@MainActor @Observable` を ViewerStore に使用
- FileWatcher は `@unchecked Sendable`（内部 GCD キューでスレッド安全性を保証）
- UI コンポーネントは SwiftUI、ウィンドウ管理は AppKit（NSWindowController）

## テスト規約

- **ユニットテスト**: `mmdviewTests/` — Swift Testing フレームワーク
- FileWatcher: 一時ファイルによる実ファイルシステムテスト
- ViewerStore: `@MainActor` テスト（状態遷移検証）
- WebView/GUI 層: 自動テスト対象外（リリース前手動チェック）

## コミット規約

Conventional Commits + 日本語:

```
feat: Mermaid ビューア画面を追加する
fix: ファイル変更検知が2回通知される問題を修正する
chore: XcodeGen 設定を更新する
```
