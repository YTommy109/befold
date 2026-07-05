# All Files Sidebar Design

<!-- constrained-by ./2026-07-05-file-list-sidebar-design.md -->

## Summary

サイドバーのファイル一覧を「対応拡張子のみ」から「開いたファイルの親ディレクトリ直下の
全ファイル」に変更する。非対応拡張子のファイルをクリックした場合、内容がテキストであれば
等幅のプレーンテキストとして表示し、バイナリであればウィンドウ中央に未対応であることが
わかるプレースホルダー（Finderアイコン + ファイル名 + 案内文）を表示する。

## Requirements

- サイドバーはディレクトリ直下の全ファイルをフラットに一覧表示する（ディレクトリ自体・隠しファイルは除外、既存方針を維持）
- 対応拡張子（`.mmd`/`.md`/コード対応拡張子）は従来通りレンダリングする
- 対応拡張子以外でもファイル内容がテキストなら等幅のプレーンテキストとして表示する
- ファイル内容がバイナリと判定される場合はレンダリングを試みず、中央にプレースホルダーを表示する
- バイナリ判定は先頭数KBのNULバイトの有無で行う（UTF-8以外の日本語テキストも「テキスト」と正しく判定するため）
- 文字コードはUTF-8のみ対応する（既存の制約を維持し、今回のスコープでは拡張しない）
- `NSOpenPanel` の許可ファイル種別（`FileType.allExtensions`）は変更しない

## Architecture

既存のサイドバー機構（`docs/superpowers/specs/2026-07-05-file-list-sidebar-design.md`）を
そのまま用いる。変更は「一覧のフィルタ条件」「ファイル種別の判定」
「バイナリ時の表示コンポーネント」の3点に閉じる。

```
DirectoryLister.listFiles(in:)          ← 拡張子フィルタを撤去（ディレクトリ・隠しファイルは除外のみ維持）
        │
        ▼
FileListView（既存、変更なし）
        │ ファイルクリック
        ▼
ViewerWindowController.switchFile(to:)（既存、変更なし）
        │
        ▼
ViewerStore.openFile(_:)
        ├── FileReading.isBinary(at:) で先頭数KBを判定
        │     ├── バイナリ → isUnsupported = true（content は読み込まない）
        │     └── テキスト → 従来通り UTF-8 で content を読み込む
        └── FileType(url:) で拡張子判定（未知拡張子は .code(language: "plaintext")）
        │
        ▼
ViewerContentView
        ├── isUnsupported == true  → UnsupportedFileView（新規、ネイティブ SwiftUI）
        └── isUnsupported == false → ViewerWebView（既存、変更なし）
```

## Changes to Existing Files

### `Viewer/DirectoryLister.swift`

- `FileType.allExtensions` によるフィルタ (`.filter { extensions.contains(...) }`) を撤去
- ディレクトリ自体は `contentsOfDirectory` の結果から `isDirectory` を見て除外する（新規に判定を追加）
- 隠しファイル除外（`.skipsHiddenFiles`）・名前順ソートは維持

### `Viewer/FileType.swift`

`init(url:)` の分岐を、`.md`/`.markdown` と「本当に未知の拡張子」を区別するように変更する。

```swift
init(url: URL) {
    let ext = url.pathExtension.lowercased()
    if Self.mermaidExtensions.contains(ext) {
        self = .mmd
    } else if let language = Self.codeExtensionLanguages[ext] {
        self = .code(language: language)
    } else if Self.markdownExtensions.contains(ext) {
        self = .markdown
    } else {
        self = .code(language: "plaintext")
    }
}
```

- `allExtensions`（Open Panel 用の単一情報源）は変更しない
- `plaintext` は同梱 `highlight.min.js` のコア機能（言語未指定/非対応言語向けのフォールバック）であり、
  追加の言語登録は不要

### `Viewer/FileReading.swift`

バイナリ判定用メソッドを protocol に追加する。

```swift
protocol FileReading: Sendable {
    func fileExists(at url: URL) -> Bool
    func readString(from url: URL) throws -> String
    func isBinary(at url: URL) -> Bool
}
```

- `DefaultFileReader.isBinary(at:)`: 先頭 8KB を `FileHandle` で読み、NULバイト（`0x00`）が
  1つでも含まれれば `true`
- 読み込み自体に失敗した場合（権限なし等）は `false`（テキスト扱い、後続の `readString` が
  従来通りエラー処理する）

### `Viewer/ViewerStore.swift`

- 新規プロパティ `private(set) var isUnsupported: Bool = false`
- `loadContent()` の先頭で `fileReader.isBinary(at: resolved)` を判定
  - `true` の場合: `isUnsupported = true` とし、`content` の読み込みはスキップする
    （バイナリを丸ごと文字列化しない）
  - `false` の場合: `isUnsupported = false` とし、従来通り `readString` で読み込む
    （UTF-8デコード失敗時は現状維持で空文字）
- ファイルが存在しない場合（`isDeleted = true`）は `isUnsupported` の判定より前に早期return（現状の分岐順を維持）

### `Viewer/ViewerContentView.swift`

`store.isUnsupported` に応じて表示コンポーネントを切り替える。

```swift
var body: some View {
    if store.isUnsupported {
        UnsupportedFileView(fileURL: store.filePath)
    } else {
        ViewerWebView(...)  // 既存のまま
    }
}
```

## New Components

### `Viewer/UnsupportedFileView.swift`

ネイティブ SwiftUI View。WKWebView を経由せず、バイナリ内容を一切読み込まない。

- `NSWorkspace.shared.icon(forFile:)` で取得したFinderアイコンを大きめ（例: 64x64pt）に表示
- ファイル名（`lastPathComponent`）
- 案内文（例:「このファイル形式はプレビューに対応していません」）
- ウィンドウ中央に配置（`VStack` + `.frame(maxWidth: .infinity, maxHeight: .infinity)`）

## Data Flow

```
1. サイドバーで非対応拡張子のバイナリファイルをクリック
   → ViewerWindowController.switchFile(to:) → ViewerStore.openFile(_:)
   → FileReading.isBinary(at:) が true
   → isUnsupported = true（content は空のまま更新しない）
   → ViewerContentView が UnsupportedFileView を表示

2. サイドバーで非対応拡張子のテキストファイル（例: .txt）をクリック
   → FileReading.isBinary(at:) が false
   → FileType(url:) が .code(language: "plaintext") を返す
   → content を通常通り読み込み、ViewerWebView が plaintext として等幅表示
```

## Testing

- `DirectoryListerTests`: 拡張子を問わず全ファイルを列挙すること／ディレクトリを除外すること／
  隠しファイルを除外することを検証するテストに更新
- `FileTypeTests`: 未知拡張子 → `.code(language: "plaintext")`、`.md`/`.markdown` → `.markdown`
  を維持すること、をそれぞれ追加
- `FileReading` 実装（テスト用差し替え含む）: NULバイトを含む一時ファイル／含まない一時ファイルで
  `isBinary(at:)` の判定結果を検証
- `ViewerStore` テスト: バイナリファイルを開いたときに `isUnsupported == true` かつ `content` が
  更新されないことを検証
- `UnsupportedFileView` / `ViewerContentView` の表示切り替え自体は既存の WebView/GUI 層と同様に
  自動テスト対象外（リリース前の手動チェックで確認）

## Out of Scope

- サブディレクトリの一覧表示・再帰（既存設計と同様に対象外）
- Shift-JIS 等 UTF-8 以外のテキストエンコーディング対応
- `NSOpenPanel` / `Info.plist` の許可ファイル種別の変更
- 巨大バイナリファイルのサムネイル/プレビュー生成
- ファイル種別が変化した場合（例: 監視中にテキスト→バイナリへ書き換わる）の遷移アニメーション等の演出
