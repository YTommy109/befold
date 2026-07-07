# befold 開発ガイド

## セットアップ

clone 後に一度だけ実行する（git hooks をインストールする。worktree は
`.git/hooks` を共有するため、以降作成する worktree にも自動的に反映される）:

```bash
bash scripts/setup-git-hooks.sh
```

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
  ├── ViewerStore        # @Observable 表示状態（content / isUnsupported、FileReading で読込を抽象化）
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

## 更新チャンネル

アプリの更新チェックは stable チャンネル（デフォルト）と develop チャンネルを切り替えられる。

| チャンネル | 対象リリース | 用途 |
|---|---|---|
| `stable` | 正式リリースのみ | 一般ユーザー向け（デフォルト） |
| `develop` | pre-release を含む全リリース | 開発者向け |

### 切り替え方法

```bash
# develop チャンネルに切り替える
defaults write com.degino.befold UpdateChannel develop

# stable に戻す
defaults delete com.degino.befold UpdateChannel
```

### develop リリースの作成

```bash
/release dev
```

現在のバージョン（例: `1.4.8`）に対して `v1.4.8-dev.N` タグを自動で作成する。
N は既存の dev タグから自動算出される。CI が DMG をビルドして GitHub の
pre-release に添付する。

## 関連ドキュメント

- [コーディング規約](./coding_rule.md)
- [ネイティブアプリ設計](./native-app-design.md)
