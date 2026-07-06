# befold コーディング規約

このドキュメントは befold プロジェクトのコーディング規約を一元管理する。
CLAUDE.md・スキル・コマンドはこのファイルを参照する。

## プロジェクト概要

macOS 向け Mermaid ダイアグラム・ビューアアプリ。
`.mmd` / `.md` ファイルを監視し、mermaid.js でリアルタイムにプレビューする。
ファイル変更は同一プロセス内伝搬で反映する。

## アーキテクチャ

```
befold.app (Swift / AppKit + SwiftUI)
  ├── AppDelegate        # ライフサイクル・メニュー・ウィンドウ管理
  ├── DocumentController # Recent Documents 連携
  ├── ViewerWindowController # NSWindowController（1 ファイル = 1 ウィンドウ）
  ├── FileWatcher        # DispatchSource によるファイル監視（0.2s デバウンス）
  ├── Debouncer          # GCD ベースのデバウンサー
  ├── ViewerStore        # @Observable 表示状態（content / error / deleted）
  ├── ViewerContentView  # SwiftUI View（ViewerWebView のラッパー）
  └── ViewerWebView      # WKWebView（NSViewRepresentable）
        ├── 同梱アセット（viewer.html / viewer.js / mermaid.min.js / markdown-it.min.js / style.css）
        └── JS ブリッジ: evaluateJavaScript("render(content, type)")
```

ファイル変更の伝搬:
`FileWatcher → ViewerStore → ViewerWebView.updateNSView → evaluateJavaScript`

## 技術スタック

- Swift 6 / AppKit + SwiftUI（macOS 14+）
- WKWebView（mermaid.js / markdown-it.js レンダリング）
- DispatchSource（ファイル監視）
- XcodeGen（プロジェクト生成）/ Swift Package Manager（ビルド）
- SwiftLint（静的解析）/ SwiftFormat（コードフォーマット）— SPM plugin
- Jest（viewer.js のユニットテスト）

## プロジェクト構成

```
BefoldApp/
├── project.yml              # XcodeGen 定義
├── Package.swift            # SPM ビルド用
├── .swiftlint.yml           # SwiftLint 設定
├── .swiftformat             # SwiftFormat 設定
├── befold/
│   ├── App/                 # AppDelegate, DocumentController, ViewerWindowController
│   ├── Viewer/              # ViewerStore, ViewerWebView, ViewerContentView, FileType
│   ├── FileWatching/        # FileWatcher, Debouncer
│   └── Resources/           # viewer.html, viewer.js, style.css, mermaid.min.js, markdown-it.min.js
│       └── __tests__/       # viewer.js の Jest テスト
└── befoldTests/            # Swift Testing テスト
```

## コマンド

```bash
cd BefoldApp
swift build                  # ビルド（SwiftLint も実行される）
swift test                   # テスト（要 Xcode.app）
xcodegen generate            # .xcodeproj を再生成
xcodebuild build -scheme befold  # Xcode ビルド（要 Xcode.app）
npx jest                     # viewer.js のテスト

# コード品質
swift package plugin swiftlint           # SwiftLint を単体実行
swift package plugin --allow-writing-to-package-directory swiftformat  # SwiftFormat 実行
```

## コード品質ツール

### SwiftLint（静的解析）

SPM Build Tool Plugin として組み込み済み。`swift build` 時に自動実行される。

| ルール | warning | error | 用途 |
|--------|---------|-------|------|
| `cyclomatic_complexity` | 10 | 20 | 循環的複雑度 |
| `function_body_length` | 50行 | 100行 | 関数の行数制限 |
| `file_length` | 400行 | 1000行 | ファイルの行数制限 |
| `type_body_length` | 250行 | 350行 | クラス/構造体の行数制限 |
| `line_length` | 120文字 | 200文字 | 行長制限 |

設定ファイル: `.swiftlint.yml`

### SwiftFormat（コードフォーマット）

SPM Command Plugin として利用する。手動実行:

```bash
swift package plugin --allow-writing-to-package-directory swiftformat
```

主な設定（`.swiftformat`）:
- インデント: 4スペース
- 行幅: 120文字
- 不要な `self.` を除去
- 引数リスト・コレクションリテラル: 長い場合は first 要素の前で改行

## Swift コーディング規約

### 言語バージョン・コンパイラ設定

- Swift 6（`swift-tools-version: 6.0`）
- Strict Concurrency: `complete`（`SWIFT_STRICT_CONCURRENCY: complete`）
- デプロイメントターゲット: macOS 14.0

### Concurrency モデル

- **`@MainActor`**: UI 状態を持つクラス（`ViewerStore`, `AppDelegate`）に付与する
- **`@Observable`**: SwiftUI のデータバインディングには `@Observable` マクロを使う（`ObservableObject` + `@Published` は使わない）
- **`@unchecked Sendable`**: GCD キューで内部的にスレッド安全性を保証するクラス（`FileWatcher`, `Debouncer`）に付与する。`NSLock` や専用 `DispatchQueue` で排他制御すること
- **`@Sendable` クロージャ**: スレッド境界を越えるクロージャには `@Sendable` を付与する
- **`nonisolated(unsafe)`**: テストコード内で並行安全でないミュータブル変数を使うときのみ許容する

### 型設計

- **`final class`**: 継承を意図しないクラスにはすべて `final` を付ける
- **`private(set)`**: 外部から読み取り可能・書き込み不可のプロパティには `private(set)` を使う
- **`enum`**: インスタンス化不要な型（`FileType` のような分類型）は `enum` で定義する
- **`Sendable`**: 値型の `enum` には `Sendable` 準拠を付ける
- **`switch` 網羅性**: `enum` の `switch` では `default` を使わず、全ケースを明示する

### 命名規約

- Swift API Design Guidelines に従う
- 型名: UpperCamelCase（`ViewerStore`, `FileWatcher`）
- メソッド・プロパティ: lowerCamelCase（`openFile`, `isDeleted`）
- GCD キューラベル: リバースドメイン（`com.degino.befold.filewatcher`）
- ウィンドウ autosave 名: `Viewer-<パスベースの識別子>`
- `@available(*, unavailable)` + `fatalError()`: Interface Builder 未使用を明示する `required init?(coder:)` に付ける

### パターン

- **guard-let early return**: `guard let filePath else { return }` でオプショナルを早期アンラップする
- **`[weak self]` キャプチャ**: クロージャでの循環参照を防ぐ。`guard let self else { return }` と組み合わせる
- **`defer`**: テストでの一時ファイル削除など、スコープ終了時の後処理に使う

### AppKit / SwiftUI 混在ルール

- **ウィンドウ管理**: AppKit（`NSWindowController`）で行う
- **ビューコンテンツ**: SwiftUI（`View` プロトコル）で定義する
- **ブリッジ**: `NSHostingView` で SwiftUI View を NSWindow に埋め込む
- **WKWebView ラッパー**: `NSViewRepresentable` で SwiftUI に統合する。`Coordinator` パターンでデリゲートを処理する

### WKWebView / JavaScript ブリッジ

- HTML・CSS・JS は `Resources/` に同梱し、`Bundle.main.url(forResource:)` でロードする
- `evaluateJavaScript()` で Swift → JS の呼び出しを行う
- JS に渡す文字列は `JSONEncoder` でエスケープする（XSS 防止）
- コンテンツ差分チェック（`lastRenderedContent`）で不要な再描画を防ぐ

## コメント・ドキュメンテーション規約

### プロダクトコード

- **`// MARK: - <セクション名>`**: ファイル内の論理セクション区切りに使う（Xcode のジャンプバーに反映される）
- **`///` ドキュメンテーションコメント**: 公開クラス・公開メソッドに日本語で付ける
- 非公開メソッド（`private` / `fileprivate`）や自明なヘルパーは省略可
- コードの「なぜ（WHY）」を書く。「何を（WHAT）」は明確な命名で伝える

```swift
/// ファイル変更を DispatchSource で監視し、変更時にコールバックを呼ぶ。
/// ファイル削除後の再作成（アトミック保存）にも対応するため、
/// ファイル本体とディレクトリの両方を監視する。
final class FileWatcher: @unchecked Sendable {
    // ...

    // MARK: - File Monitoring

    /// ファイルの書き込み・削除・リネームを監視する。
    /// 削除時はソースを解放し、ディレクトリ監視側で再作成を検知する。
    private func startFileMonitor() { ... }
}
```

- **インラインコメント**: 非自明な判断・ワークアラウンド・制約がある箇所に日本語で付ける

```swift
// WKWebView の背景を透明にする（公開 API がないため KVC を使用）
webView.setValue(false, forKey: "drawsBackground")

// JSONEncoder でエスケープし、JS インジェクションを防ぐ
guard let jsonData = try? JSONEncoder().encode(content) else { return }
```

- 書かなくてよいコメント:
  - コードをそのまま日本語に訳しただけのもの（`// ファイルを開く` → `openFile()` で自明）
  - タスク番号や変更履歴の参照（コミットメッセージに書く）

### テストコード

- **テスト関数の上**: 何を検証しているかが関数名で不十分な場合に `///` で補足する
- **テスト内のブロックコメント**: Arrange / Act / Assert や前提条件を日本語コメントで区切る

```swift
@Test(.timeLimit(.minutes(1)))
func detectsAtomicSave() async throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let file = tempDir.appendingPathComponent("test.mmd")
    try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

    await confirmation { confirm in
        let watcher = FileWatcher(path: file) {
            confirm()
        }

        // 初期化完了を待つ
        try? await Task.sleep(for: .seconds(0.3))

        // アトミック保存（一時ファイル → rename）をシミュレート
        let tmpFile = tempDir.appendingPathComponent(".test.mmd.tmp")
        try? "graph TD; X-->Y".write(to: tmpFile, atomically: false, encoding: .utf8)
        _ = try? FileManager.default.replaceItemAt(file, withItemAt: tmpFile)

        // コールバック発火を待つ
        try? await Task.sleep(for: .seconds(3))
        watcher.stop()
    }
}
```

## JavaScript コーディング規約

- `viewer.js` にはテスト可能な純粋ロジックのみを置く（DOM 操作は `viewer.html` 側）
- CommonJS 互換の `module.exports` で関数をエクスポートする（Jest テスト用）
- `var` 宣言を使用する（WKWebView 内での互換性）

## テスト規約

### 開発フロー（テスト先行）

- 新機能追加・仕様変更では、**先にテストを書き、そのテストを通す実装を行う**
- テストがすべてグリーンになった時点でタスク完了とみなす
- **不具合を確認したとき**: 先に落ちる回帰テストを追加してから修正する
- リファクタリングでは先に既存挙動をテストで固定してからコードを変更する

### テストフレームワーク

- **Swift**: Swift Testing（`import Testing`）を使う（XCTest は使わない）
- **JavaScript**: Jest を使う

### Swift テスト構造

- **`@Suite` + `struct`**: テストスイートは `struct` で定義し `@Suite` を付ける
- **`@Test`**: 各テスト関数に `@Test` を付ける
- **`#expect`**: アサーションには `#expect` マクロを使う（`XCTAssert` は使わない）
- **`@MainActor`**: `ViewerStore` など MainActor 隔離が必要なテストにはスイートレベルで `@MainActor` を付ける
- **`@Test(arguments:)`**: 同じアサーション構造で入力だけが異なるテストはパラメタライズする（pytest の `@pytest.mark.parametrize` に相当）
- **`confirmation`**: 非同期コールバックのテストには `confirmation { confirm in ... }` を使う
- **`.timeLimit`**: 非同期テストには `@Test(.timeLimit(.minutes(1)))` でタイムアウトを設定する

### テスト関数の命名規約

- テスト関数名は**テスト対象の振る舞いがわかる英語の lowerCamelCase** で付ける
- 形式: `func <動作説明>()` （Swift Testing では `test_` プレフィックス不要だが、慣例として付けてもよい）

```swift
// ✅ 良い例: 何をテストしているか一目でわかる
@Test func detectsFileModification() async throws { ... }
@Test func openNonexistentFileMarksDeleted() { ... }
@Test func coalescesRapidCalls() async { ... }
@Test func fileTypeDetection() { ... }

// ❌ 悪い例: 曖昧・長すぎる
@Test func test1() { ... }
@Test func testThatWhenAFileIsOpenedAndThenDeletedTheStoreMarksItAsDeleted() { ... }
```

### テストパターン

#### ファイルシステムテスト（FileWatcher / ViewerStore）

一時ディレクトリを作成し、`defer` で確実にクリーンアップする:

```swift
private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("befold-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test
func detectsFileModification() async throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    // ...
}
```

#### 非同期コールバックテスト

`confirmation` + `Task.sleep` で非同期イベントの発火を検証する:

```swift
@Test(.timeLimit(.minutes(1)))
func detectsFileModification() async throws {
    await confirmation { confirm in
        let watcher = FileWatcher(path: file) {
            confirm()
        }
        try? await Task.sleep(for: .seconds(0.3))
        // ファイルを変更
        try? await Task.sleep(for: .seconds(3))
        watcher.stop()
    }
}
```

#### 状態遷移テスト（ViewerStore）

同期的に操作して即座にプロパティを検証する:

```swift
@Test
func openMmdFile() throws {
    let store = ViewerStore()
    store.openFile(file)

    #expect(store.content == "graph TD; A-->B")
    #expect(store.fileType == .mmd)
    #expect(!store.isDeleted)

    store.close()
}
```

### パラメタライズテスト（`@Test(arguments:)`）

同じアサーション構造で入力だけが異なるテストは個別の `#expect` を並べず `@Test(arguments:)` にまとめる。
ケースごとに独立実行され、どの入力で失敗したかが明確になる:

```swift
// ✅ 良い例: 入力と期待値のペアをパラメタライズ
@Test(arguments: [
    ("mmd", FileType.mmd),
    ("mermaid", FileType.mmd),
    ("MMD", FileType.mmd),
    ("md", FileType.markdown),
    ("markdown", FileType.markdown),
])
func fileTypeDetection(ext: String, expected: FileType) {
    let url = URL(fileURLWithPath: "/a/b.\(ext)")
    #expect(FileType(url: url) == expected)
}

// ❌ 悪い例: 同じ構造のアサーションを手動で並べる
@Test
func fileTypeDetection() {
    #expect(FileType(url: URL(fileURLWithPath: "/a/b.mmd")) == .mmd)
    #expect(FileType(url: URL(fileURLWithPath: "/a/b.mermaid")) == .mmd)
    #expect(FileType(url: URL(fileURLWithPath: "/a/b.md")) == .markdown)
    // → 最初の失敗で止まり、残りのケースが検証されない
}
```

パラメタライズを使うべき典型的なケース:
- 複数の入力に対して同じ変換結果を期待する（型判定・マッピング）
- 複数の無効入力に対して同じエラーを期待する
- 境界値テスト（最小・最大・境界+1）

### テスト対象外

- WebView / GUI 層: 自動テスト対象外（リリース前手動チェック）
- `viewer.html` 内の DOM 操作ロジック: 手動チェック

## エラーハンドリング規約

- ファイル読み取り失敗は `try?` で握りつぶし、空文字列にフォールバックする（ビューアアプリの特性上、致命的エラーにしない）
- ファイル削除検出は `isDeleted` フラグで UI に伝搬する
- `guard` + early return で異常系を先に処理し、正常系のネストを浅く保つ

## コミット規約

Conventional Commits + 日本語:

```
<type>: <変更内容を動詞で始める日本語>

[body: 必要な場合のみ]
```

type の選択:
- `feat`: 新機能
- `fix`: バグ修正
- `chore`: ビルド・設定・依存関係
- `docs`: ドキュメントのみ
- `refactor`: 機能変更なしのコード整理
- `test`: テストの追加・修正
- `ci`: CI・リリースワークフロー

## 品質チェック手順

以下を順番に実行する:

1. **SwiftFormat**: `swift package plugin --allow-writing-to-package-directory swiftformat`
2. **Swift ビルド + SwiftLint**: `swift build`（SwiftLint はビルド時に自動実行）
3. **Swift テスト**: `swift test`
4. **JS テスト**: `npx jest`

すべてパスしたら完了。

## 応答言語

- **会話**: ユーザーとのやりとりは基本的に**日本語**で行う
- **説明・コメント**: コード外の説明、コミットメッセージも日本語で書く
- **コード**: 変数名・関数名・ファイル名は英語（Swift API Design Guidelines 準拠）
- ユーザーが英語で質問した場合は、返答も英語で行う
