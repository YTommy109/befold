# All Files Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** サイドバーのファイル一覧を対応拡張子のみから全ファイルに広げ、非対応拡張子のファイルはテキストならプレーンテキスト表示、バイナリなら中央にプレースホルダーを表示する。

**Architecture:** `DirectoryLister` の拡張子フィルタを撤去し、`FileType` の未知拡張子フォールバックを `plaintext` に変更、`FileReading` に先頭数KBのNULバイト判定を追加、`ViewerStore` に `isUnsupported` フラグを追加、`ViewerContentView` がそのフラグでネイティブ `UnsupportedFileView` と既存の `ViewerWebView` を切り替える。

**Tech Stack:** Swift 6 / AppKit + SwiftUI、Swift Testing（`mmdviewTests/`）。

## Global Constraints

- 文字コードはUTF-8のみ対応する（Shift-JIS等のフォールバックは追加しない）
- `NSOpenPanel` / `Info.plist` の許可ファイル種別（`FileType.allExtensions`）は変更しない
- サブディレクトリの一覧表示・再帰は対象外（ディレクトリ自体はサイドバーから除外する）
- バイナリ判定は先頭8KBのNULバイト有無で行う
- テスト関数名は英語camelCase、日本語の説明は `@Test("...")` の表示名で付ける（`.claude/CLAUDE.md` のSwiftテスト規約）
- WebView/GUI層（`UnsupportedFileView`/`ViewerContentView`の表示切り替え自体）は自動テスト対象外。リリース前に手動確認する

---

### Task 1: DirectoryLister — 全ファイル列挙・ディレクトリ除外

**Files:**
- Modify: `MmdviewApp/mmdview/Viewer/DirectoryLister.swift`
- Test: `MmdviewApp/mmdviewTests/DirectoryListerTests.swift`

**Interfaces:**
- Consumes: なし（既存の `FileManager` API のみ）
- Produces: `DirectoryLister.listFiles(in:) -> [URL]`（シグネチャ変更なし。動作のみ「対応拡張子のみ」→「ディレクトリを除く全ファイル」に変更）

- [ ] **Step 1: 既存テストを新しい期待値に書き換える**

`MmdviewApp/mmdviewTests/DirectoryListerTests.swift` の `listFilesFiltersByExtension` を全ファイルが返ることを検証するテストに置き換え、ディレクトリ除外のテストを追加する。ファイル全体を以下に置き換える。

```swift
import Foundation
@testable import mmdview
import Testing

@Suite
struct DirectoryListerTests {
    @Test("拡張子によらず全ファイルが返される")
    func listFilesReturnsAllFilesRegardlessOfExtension() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let mmd = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let md = try tmp.file(named: "readme.md", contents: "# Hi")
        let png = try tmp.file(named: "photo.png", contents: "binary")
        let csv = try tmp.file(named: "data.csv", contents: "a,b")

        let result = DirectoryLister.listFiles(in: tmp.url)

        let names = result.map(\.lastPathComponent)
        #expect(names.contains("diagram.mmd"))
        #expect(names.contains("readme.md"))
        #expect(names.contains("photo.png"))
        #expect(names.contains("data.csv"))
    }

    @Test("サブディレクトリは一覧から除外される")
    func listFilesExcludesDirectories() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "visible.mmd", contents: "")
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent("subdir"),
            withIntermediateDirectories: true
        )

        let result = DirectoryLister.listFiles(in: tmp.url)

        #expect(result.map(\.lastPathComponent) == ["visible.mmd"])
    }

    @Test("結果がファイル名でローカライズソートされる")
    func listFilesSortsByName() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "c.mmd", contents: "")
        _ = try tmp.file(named: "a.mmd", contents: "")
        _ = try tmp.file(named: "b.mmd", contents: "")

        let result = DirectoryLister.listFiles(in: tmp.url)

        #expect(result.map(\.lastPathComponent) == ["a.mmd", "b.mmd", "c.mmd"])
    }

    @Test("隠しファイルは除外される")
    func listFilesExcludesHidden() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "")
        _ = try tmp.file(named: "visible.mmd", contents: "")

        let result = DirectoryLister.listFiles(in: tmp.url)

        let names: [String] = result.map(\.lastPathComponent)
        #expect(names == ["visible.mmd"])
    }

    @Test("存在しないディレクトリでは空配列を返す")
    func listFilesReturnsEmptyForMissingDir() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let result = DirectoryLister.listFiles(in: missing)
        #expect(result.isEmpty)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter DirectoryListerTests`
Expected: `listFilesReturnsAllFilesRegardlessOfExtension` と `listFilesExcludesDirectories` が FAIL（photo.png/data.csv が結果に含まれない／`subdir` がまだ除外されていない実装なので `visible.mmd` 単体の期待と一致しない）

- [ ] **Step 3: DirectoryLister を実装する**

`MmdviewApp/mmdview/Viewer/DirectoryLister.swift` を以下に置き換える。

```swift
import Foundation

enum DirectoryLister {
    static func listFiles(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .filter { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return !isDirectory
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter DirectoryListerTests`
Expected: PASS（全5テスト）

- [ ] **Step 5: コミット**

```bash
git add MmdviewApp/mmdview/Viewer/DirectoryLister.swift MmdviewApp/mmdviewTests/DirectoryListerTests.swift
git commit -m "feat: サイドバーのファイル一覧を全ファイル表示にする"
```

---

### Task 2: FileReading にバイナリ判定を追加する

**Files:**
- Modify: `MmdviewApp/mmdview/Viewer/FileReading.swift`
- Modify: `MmdviewApp/mmdviewTests/InMemoryFileReader.swift`
- Test: `MmdviewApp/mmdviewTests/DefaultFileReaderTests.swift`（新規）

**Interfaces:**
- Consumes: なし
- Produces: `protocol FileReading` に `func isBinary(at url: URL) -> Bool` を追加。`DefaultFileReader.isBinary(at:)`（先頭8KBにNULバイトが含まれれば `true`）。テスト用 `InMemoryFileReader.setBinary(_:at:)` でパスをバイナリとしてマーク可能にする（デフォルトは `false`）。Task 4 がこの2つの実装をそのまま使う。

- [ ] **Step 1: DefaultFileReader の失敗するテストを書く**

`MmdviewApp/mmdviewTests/DefaultFileReaderTests.swift` を新規作成する。

```swift
import Foundation
@testable import mmdview
import Testing

@Suite
struct DefaultFileReaderTests {
    @Test("NULバイトを含むファイルはバイナリと判定される")
    func isBinaryTrueForNulByte() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "photo.png", contents: "PNG\0\0\0data")

        #expect(DefaultFileReader().isBinary(at: file))
    }

    @Test("NULバイトを含まないテキストファイルはバイナリと判定されない")
    func isBinaryFalseForPlainText() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "notes.txt", contents: "hello world")

        #expect(!DefaultFileReader().isBinary(at: file))
    }

    @Test("存在しないファイルはテキスト扱い(false)になる")
    func isBinaryFalseForMissingFile() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(!DefaultFileReader().isBinary(at: missing))
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter DefaultFileReaderTests`
Expected: FAIL（コンパイルエラー: `isBinary` が `FileReading`/`DefaultFileReader` に存在しない）

- [ ] **Step 3: protocol と DefaultFileReader を実装する**

`MmdviewApp/mmdview/Viewer/FileReading.swift` を以下に置き換える。

```swift
import Foundation

/// ファイルの存在確認と内容読み込みを抽象化する(テストでの差し替え用)。
protocol FileReading: Sendable {
    func fileExists(at url: URL) -> Bool
    func readString(from url: URL) throws -> String
    /// 先頭数KBにNULバイトが含まれるかでバイナリかどうかを判定する。
    func isBinary(at url: URL) -> Bool
}

/// FileManager / String(contentsOf:) による標準実装。
struct DefaultFileReader: FileReading {
    /// バイナリ判定に読む先頭バイト数。
    private static let binarySniffLength = 8192

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func readString(from url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// 先頭 8KB を読み、NULバイト(0x00)が1つでも含まれればバイナリと判定する。
    /// ファイルを開けない場合はテキスト扱い(false)とし、readString 側の
    /// エラー処理に委ねる。
    func isBinary(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.binarySniffLength) else { return false }
        return data.contains(0)
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter DefaultFileReaderTests`
Expected: PASS（3テスト）

- [ ] **Step 5: InMemoryFileReader にテスト用のバイナリマーキングを追加する**

`MmdviewApp/mmdviewTests/InMemoryFileReader.swift` を以下に置き換える（この時点では `ViewerStoreTests.swift` はまだ `isBinary` を使わないため、この変更単体でもビルドは通る）。

```swift
import Foundation
@testable import mmdview

/// メモリ上の辞書でファイルシステムを模す FileReading 実装。
/// キーは URL.path(テストではシンボリックリンクを含まないパスを使うこと)。
final class InMemoryFileReader: FileReading, Sendable {
    private let files: LockedBox<[String: String]>
    private let binaryPaths: LockedBox<Set<String>>

    init(files: [String: String] = [:]) {
        self.files = LockedBox(files)
        binaryPaths = LockedBox([])
    }

    /// ファイルを作成/上書きする。nil を渡すと削除する。
    func setFile(_ contents: String?, at url: URL) {
        files.update { $0[url.path] = contents }
    }

    /// このパスをバイナリファイルとしてマークする(isBinary(at:) が true を返すようになる)。
    func setBinary(_ isBinary: Bool, at url: URL) {
        binaryPaths.update { paths in
            if isBinary {
                paths.insert(url.path)
            } else {
                paths.remove(url.path)
            }
        }
    }

    func fileExists(at url: URL) -> Bool {
        files.get()[url.path] != nil
    }

    func readString(from url: URL) throws -> String {
        guard let contents = files.get()[url.path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return contents
    }

    func isBinary(at url: URL) -> Bool {
        binaryPaths.get().contains(url.path)
    }
}
```

- [ ] **Step 6: 全体テストが通ることを確認する**

Run: `cd MmdviewApp && swift test`
Expected: PASS（既存テストを含め全て）

- [ ] **Step 7: コミット**

```bash
git add MmdviewApp/mmdview/Viewer/FileReading.swift MmdviewApp/mmdviewTests/InMemoryFileReader.swift MmdviewApp/mmdviewTests/DefaultFileReaderTests.swift
git commit -m "feat: FileReading に先頭バイトによるバイナリ判定を追加する"
```

---

### Task 3: FileType — 未知拡張子を plaintext にフォールバックする

**Files:**
- Modify: `MmdviewApp/mmdview/Viewer/FileType.swift`
- Test: `MmdviewApp/mmdviewTests/FileTypeTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `FileType.init(url:)` の変更後の挙動 — `.md`/`.markdown` は引き続き `.markdown`、それ以外の未知拡張子（`.txt` 等、拡張子なしも含む）は `.code(language: "plaintext")`。`FileType.allExtensions` はシグネチャ・値とも変更なし。Task 4 (`ViewerStore`) がこの新しい `.code(language: "plaintext")` フォールバックに依存する。

- [ ] **Step 1: 失敗するテストに書き換える**

`MmdviewApp/mmdviewTests/FileTypeTests.swift` の `unknownExtensionsFallbackToMarkdown` を以下に置き換える（他のテストはそのまま）。

```swift
    /// 未知の拡張子は plaintext(等幅プレーンテキスト表示)にフォールバックすること
    @Test(arguments: ["txt", "html", ""])
    func unknownExtensionsFallbackToPlaintext(ext: String) {
        let path = ext.isEmpty ? "/a/b" : "/a/b.\(ext)"
        let url = URL(fileURLWithPath: path)
        #expect(FileType(url: url) == .code(language: "plaintext"))
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter FileTypeTests`
Expected: FAIL（`unknownExtensionsFallbackToPlaintext` — 現状は `.markdown` が返るため）

- [ ] **Step 3: FileType.init(url:) を実装する**

`MmdviewApp/mmdview/Viewer/FileType.swift` の `init(url:)` (43-52行目) を以下に置き換える。

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

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter FileTypeTests`
Expected: PASS（全テスト。`knownExtensions` の `.md`/`.markdown` ケースが引き続き通ることも確認する）

- [ ] **Step 5: コミット**

```bash
git add MmdviewApp/mmdview/Viewer/FileType.swift MmdviewApp/mmdviewTests/FileTypeTests.swift
git commit -m "feat: 未知拡張子のファイル種別を plaintext にフォールバックする"
```

---

### Task 4: ViewerStore に isUnsupported を追加する

**Files:**
- Modify: `MmdviewApp/mmdview/Viewer/ViewerStore.swift`
- Test: `MmdviewApp/mmdviewTests/ViewerStoreTests.swift`

**Interfaces:**
- Consumes: `FileReading.isBinary(at:) -> Bool`（Task 2）、`FileType.init(url:)` の plaintext フォールバック（Task 3）
- Produces: `ViewerStore.isUnsupported: Bool`（`isDeleted` と同様 `private(set)`）。Task 5 (`ViewerContentView`) がこのプロパティを読む。

- [ ] **Step 1: 失敗するテストを書く**

`MmdviewApp/mmdviewTests/ViewerStoreTests.swift` に以下のテストを追加する（`reopenDifferentFile` の後に挿入）。

```swift
    @Test
    func openBinaryFileMarksUnsupported() {
        let file = URL(fileURLWithPath: "/files/photo.png")
        let reader = InMemoryFileReader()
        reader.setFile("binary-ish", at: file)
        reader.setBinary(true, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(store.isUnsupported)
        #expect(store.content == "")
        #expect(!store.isDeleted)

        store.close()
    }

    @Test
    func openTextFileWithUnknownExtensionIsNotUnsupported() {
        let file = URL(fileURLWithPath: "/files/notes.txt")
        let reader = InMemoryFileReader()
        reader.setFile("hello", at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(!store.isUnsupported)
        #expect(store.content == "hello")
        #expect(store.fileType == .code(language: "plaintext"))

        store.close()
    }

    @Test
    func switchingFromBinaryToTextResetsUnsupported() {
        let binaryFile = URL(fileURLWithPath: "/files/photo.png")
        let textFile = URL(fileURLWithPath: "/files/readme.md")
        let reader = InMemoryFileReader()
        reader.setFile("binary-ish", at: binaryFile)
        reader.setBinary(true, at: binaryFile)
        reader.setFile("# Hello", at: textFile)

        let store = makeStore(reader: reader)
        store.openFile(binaryFile)
        #expect(store.isUnsupported)

        store.openFile(textFile)
        #expect(!store.isUnsupported)
        #expect(store.content == "# Hello")

        store.close()
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter ViewerStoreTests`
Expected: FAIL（コンパイルエラー: `ViewerStore` に `isUnsupported` が存在しない）

- [ ] **Step 3: ViewerStore を実装する**

`MmdviewApp/mmdview/Viewer/ViewerStore.swift` を以下に置き換える。

```swift
import Foundation

/// ビューアの表示状態を管理する。
/// ファイルの読み込み・監視・削除検知を行い、UI にバインドされるプロパティを更新する。
@MainActor
@Observable
final class ViewerStore {
    typealias WatcherFactory = @MainActor @Sendable (
        URL,
        @escaping @MainActor @Sendable () -> Void,
        (@MainActor @Sendable (URL) -> Void)?
    ) -> FileWatching

    private(set) var content: String = ""
    private(set) var fileType: FileType = .mmd
    private(set) var isDeleted: Bool = false
    /// 開いたファイルがバイナリなど非対応内容と判定された場合に true になる。
    /// true の間 content は更新されない(バイナリを丸ごと文字列化しない)。
    private(set) var isUnsupported: Bool = false
    private(set) var filePath: URL?

    /// 開いているファイルが rename / move されたときに新 URL を通知する。
    /// ウィンドウ側がタイトル・representedURL・セッション記録を更新するために使う。
    var onFileRenamed: ((URL) -> Void)?

    private var fileWatcher: FileWatching?
    private let makeWatcher: WatcherFactory
    private let fileReader: any FileReading

    init(watcherFactory: WatcherFactory? = nil, fileReader: any FileReading = DefaultFileReader()) {
        makeWatcher = watcherFactory ?? { url, onChange, onRename in
            FileWatcher(path: url, onChange: onChange, onRename: onRename)
        }
        self.fileReader = fileReader
    }

    /// 指定 URL のファイルを開き、ファイル監視を開始する。
    /// 既に別のファイルを開いている場合は、先に監視を停止してから切り替える。
    func openFile(_ url: URL) {
        fileWatcher?.stop()
        filePath = url
        fileType = FileType(url: url)
        loadContent()

        fileWatcher = makeWatcher(url, { [weak self] in
            self?.loadContent()
        }, { [weak self] newURL in
            self?.handleRename(to: newURL)
        })
    }

    /// 監視対象ファイルの rename / move を反映する。
    /// filePath / fileType を新 URL に更新し、コンテンツを再読込したうえでウィンドウ側へ通知する。
    private func handleRename(to newURL: URL) {
        filePath = newURL
        fileType = FileType(url: newURL)
        loadContent()
        onFileRenamed?(newURL)
    }

    private func loadContent() {
        guard let filePath else { return }
        let resolved = filePath.resolvingSymlinksInPath()
        guard fileReader.fileExists(at: resolved) else {
            isDeleted = true
            isUnsupported = false
            return
        }
        isDeleted = false

        guard !fileReader.isBinary(at: resolved) else {
            isUnsupported = true
            content = ""
            return
        }
        isUnsupported = false
        content = (try? fileReader.readString(from: resolved)) ?? ""
    }

    /// ファイル監視を停止し、リソースを解放する。
    func close() {
        fileWatcher?.stop()
        fileWatcher = nil
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter ViewerStoreTests`
Expected: PASS（既存テスト＋追加した3テストすべて）

- [ ] **Step 5: 全体テストを実行する**

Run: `cd MmdviewApp && swift test`
Expected: PASS

- [ ] **Step 6: コミット**

```bash
git add MmdviewApp/mmdview/Viewer/ViewerStore.swift MmdviewApp/mmdviewTests/ViewerStoreTests.swift
git commit -m "feat: ViewerStore にバイナリファイル検知(isUnsupported)を追加する"
```

---

### Task 5: UnsupportedFileView の追加と ViewerContentView への統合

**Files:**
- Create: `MmdviewApp/mmdview/Viewer/UnsupportedFileView.swift`
- Modify: `MmdviewApp/mmdview/Viewer/ViewerContentView.swift`

**Interfaces:**
- Consumes: `ViewerStore.isUnsupported`（Task 4）、`ViewerStore.filePath: URL?`（既存）
- Produces: `UnsupportedFileView(fileURL: URL?)`（`ViewerContentView` 以外からは使わないため他タスクからの参照はなし）

このタスクは SwiftUI/WebView 層の変更で自動テスト対象外（`.claude/CLAUDE.md` のテスト規約）。手動確認を Step に含める。

- [ ] **Step 1: UnsupportedFileView を作成する**

`MmdviewApp/mmdview/Viewer/UnsupportedFileView.swift` を新規作成する。

```swift
import SwiftUI

/// バイナリなど非対応内容のファイルを開いたときに、ウィンドウ中央に
/// アイコン・ファイル名・案内文を表示する。WKWebView は経由しない
/// (バイナリ内容を文字列として読み込む必要がないため)。
struct UnsupportedFileView: View {
    let fileURL: URL?

    var body: some View {
        VStack(spacing: 12) {
            if let fileURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                    .resizable()
                    .frame(width: 64, height: 64)
                Text(fileURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("このファイル形式はプレビューに対応していません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: ViewerContentView を isUnsupported で分岐させる**

`MmdviewApp/mmdview/Viewer/ViewerContentView.swift` を以下に置き換える。

```swift
import SwiftUI

struct ViewerContentView: View {
    let store: ViewerStore
    let initialZoom: Double
    let onZoomChanged: @MainActor (Double) -> Void
    let webViewProxy: WebViewProxy

    var body: some View {
        if store.isUnsupported {
            UnsupportedFileView(fileURL: store.filePath)
        } else {
            ViewerWebView(
                content: store.content,
                fileType: store.fileType,
                isDeleted: store.isDeleted,
                initialZoom: initialZoom,
                onZoomChanged: onZoomChanged,
                webViewProxy: webViewProxy
            )
        }
    }
}
```

- [ ] **Step 3: ビルドが通ることを確認する**

Run: `cd MmdviewApp && swift build`
Expected: ビルド成功（エラーなし）

- [ ] **Step 4: 全体テストを実行する**

Run: `cd MmdviewApp && swift test`
Expected: PASS（既存テストすべて。この Task 自体に新規ユニットテストはない）

- [ ] **Step 5: コミット**

```bash
git add MmdviewApp/mmdview/Viewer/UnsupportedFileView.swift MmdviewApp/mmdview/Viewer/ViewerContentView.swift
git commit -m "feat: 非対応バイナリファイル用のプレースホルダー表示を追加する"
```

- [ ] **Step 6: 手動スモークテスト**

`/run` スキル（または `xcodebuild build -scheme mmdview` → 起動）でアプリを実際に起動し、以下を確認する。

1. `.mmd`/`.md`/対応コード拡張子のファイルを開き、サイドバーに `.png`・`.zip` など任意の拡張子のファイルも一覧表示されることを確認する
2. サイドバーで `.txt` など未知だがテキストのファイルをクリックし、等幅フォントでそのまま表示されることを確認する（Markdown記法として解釈されないこと）
3. サイドバーで `.png`/`.zip` など実際のバイナリファイルをクリックし、ウィンドウ中央にFinderアイコン・ファイル名・案内文が表示されることを確認する
4. バイナリファイル表示中に View メニューの Zoom In/Out/Actual Size を実行してもクラッシュしないこと（`webViewProxy.webView` が nil になり no-op になることの確認）
5. ダークモード/ライトモード双方でプレースホルダーの背景色がウィンドウ地の色（`ViewerTheme.canvas`）と違和感なく一致していることを確認する

問題があれば該当タスクに戻って修正しコミットし直す。問題なければ完了。
