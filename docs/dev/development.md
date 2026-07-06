# befold 開発ガイド

## ビルド

### Swift Package Manager

```bash
cd BefoldApp
swift build
swift test
```

### Xcode

```bash
cd BefoldApp
xcodegen generate            # .xcodeproj を生成
xcodebuild build -scheme befold
```

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

ファイル変更は `FileWatcher → ViewerStore → evaluateJavaScript` の同一プロセス内伝搬で反映する。

## 技術スタック

- Swift 6 / AppKit + SwiftUI（macOS 14+）
- WKWebView（mermaid.js / markdown-it.js レンダリング）
- DispatchSource（ファイル監視）
- XcodeGen（プロジェクト生成）/ Swift Package Manager（ビルド）

## 関連ドキュメント

- [コーディング規約](./coding_rule.md)
- [ネイティブアプリ設計](./native-app-design.md)
