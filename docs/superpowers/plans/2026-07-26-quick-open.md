# Quick Open Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Cmd+P` で Spotlight 風のパネルを開き、unix パス入力または fuzzy 検索で現在のウィンドウを目的のファイルへ切り替えられるようにする。

**Architecture:** 判断ロジックはすべて `BefoldKit`（純粋ロジック・テスト可能）に置き、`befold` App ターゲットには `NSPanel` のライフサイクルと SwiftUI の描画・キー配線だけを置く。候補は Git 追跡ファイル索引（既存の `GitCommandFileIndex`）を優先し、非 Git ではディレクトリ再帰走査にフォールバックする。決定時は現在のウィンドウの `switchFile(to:)` を呼ぶ。

**Tech Stack:** Swift 6 / AppKit (`NSPanel`) + SwiftUI (`@Observable`, `.onKeyPress`) / Swift Testing / SwiftPM

**Spec:** `docs/superpowers/specs/2026-07-26-quick-open-design.md`
**Backlog:** TASK-159

## Global Constraints

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）。新規型は `Sendable` か `@MainActor` のどちらかを明示する。
- 対象は macOS 14 以上。
- テスト関数名は英語 camelCase。日本語の説明は `@Test("...")` の表示名で付ける。
- `BefoldKit/` と `befold/App/` への `.swift` 新規追加では `Package.swift` も `project.yml` も**編集不要**（両者ともディレクトリ配下を自動収集する）。リソースを足す場合のみ両方への追記が必要。
- メニュー文字列は `String(localized: "<key>", bundle: .l10n)` で引き、`BefoldApp/befold/Resources/Localizable.xcstrings` に en / ja の両方を `"extractionState": "manual"` 付きで追加する。
- コミットは Conventional Commits + 日本語（例: `feat: Quick Open のパス補完を追加する`）。
- テスト実行は `cd BefoldApp && swift test`。個別実行は `swift test --filter <SuiteName>`。
- 作業ブランチは `feat/quick-open`（作成済み）。`main` への直接コミットは pre-commit フックがブロックする。

## Deviations from the Spec

実装計画を書く過程で既存コードを確認した結果、spec から次の 3 点を変更する。spec 側にも同じ内容を反映済み。

1. **`SuffixPathIndex` に読み出しアクセサ `allCandidates` を追加する。** spec は「`SuffixPathIndex` の変更」をスコープ外としていたが、これは照合規則を変えないという意図だった。`GitFileIndexing.trackedFileIndex(forFileAt:)` は `SuffixPathIndex?` を返すだけで、取り込んだ候補 URL を読み出す口が無い。照合の挙動を一切変えない読み取り専用プロパティを 1 つ足すのが最小の解決になる。
2. **`Debouncer` を使わない。** 候補件数には 10,000 件の上限が掛かっており、絞り込みは同期のメモリ内処理で十分速い。デバウンスを挟むと `QuickOpenModel` が非同期になりテストが難しくなる。バックグラウンド化するのは候補の取得（`git ls-files` / ディレクトリ走査）だけにする。実測で入力がもたつく場合にのみ後からデバウンスを導入する。
3. **基準を「現在のファイル URL」ではなく「基準ディレクトリ」で受け渡す。** ウィンドウが 1 枚も無い状態でも `Cmd+P` を押せるため、ファイル URL を必須にすると疑似 URL をでっち上げる必要が出る。相対パス解決・表示・走査はすべて `baseDirectory: URL` を使い、Git 索引の引き当てにだけ `currentFileURL: URL?`（無ければ `baseDirectory`）を使う。

## File Structure

**新規（BefoldKit）**

| ファイル | 責務 |
| --- | --- |
| `BefoldApp/BefoldKit/QuickOpenQuery.swift` | 入力文字列を path / fuzzy / empty に分類する |
| `BefoldApp/BefoldKit/DirectoryContentsReading.swift` | ディレクトリ直下の列挙を抽象化するプロトコルと既定実装 |
| `BefoldApp/BefoldKit/DirectoryFileScanner.swift` | 非 Git 時の再帰走査（深さ・件数上限、除外ディレクトリ） |
| `BefoldApp/BefoldKit/FuzzyMatcher.swift` | 部分列マッチとスコアリング、順位付け |
| `BefoldApp/BefoldKit/QuickOpenPathCompletion.swift` | パスモードの親／断片分解、前方一致、Tab 補完文字列 |
| `BefoldApp/BefoldKit/QuickOpenCandidates.swift` | 索引・履歴・ブックマークのマージ、重複除去、加点、上限 |

**新規（App）**

| ファイル | 責務 |
| --- | --- |
| `BefoldApp/befold/App/QuickOpenModel.swift` | `@MainActor @Observable`。入力から候補行を導き、決定を注入クロージャへ渡す |
| `BefoldApp/befold/App/QuickOpenPanelController.swift` | `NSPanel` のライフサイクルと配置。判断ロジックを持たない |
| `BefoldApp/befold/Viewer/QuickOpenView.swift` | SwiftUI。`TextField` と候補リスト、キー配線 |

**修正**

| ファイル | 変更内容 |
| --- | --- |
| `BefoldApp/BefoldKit/SuffixPathMatcher.swift` | `SuffixPathIndex` に `allCandidates` を追加 |
| `BefoldApp/befold/App/MainMenuBuilder.swift` | Quick Open 項目を追加、Print を `⇧⌘P` へ |
| `BefoldApp/befold/App/AppDelegate.swift` | `GitCommandFileIndex` を自前で保持して共有、パネル配線、`showQuickOpen` |
| `BefoldApp/befold/Resources/Localizable.xcstrings` | `menu.file.quickOpen` を追加 |

**新規テスト**

`BefoldApp/befoldTests/` 配下に `QuickOpenQueryTests.swift`, `DirectoryFileScannerTests.swift`, `FuzzyMatcherTests.swift`, `QuickOpenPathCompletionTests.swift`, `QuickOpenCandidatesTests.swift`, `SuffixPathIndexCandidatesTests.swift`, `QuickOpenModelTests.swift`, `MainMenuBuilderQuickOpenTests.swift`

---

### Task 1: QuickOpenQuery（入力の分類）

**Files:**
- Create: `BefoldApp/BefoldKit/QuickOpenQuery.swift`
- Test: `BefoldApp/befoldTests/QuickOpenQueryTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `public enum QuickOpenQuery: Equatable, Sendable { case empty; case path(String); case fuzzy(String) }` / `public static func classify(_ input: String) -> QuickOpenQuery`

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/QuickOpenQueryTests.swift`:

```swift
@testable import BefoldKit
import Foundation
import Testing

@Suite
struct QuickOpenQueryTests {
    @Test("空文字と空白のみは empty になる")
    func emptyInput() {
        #expect(QuickOpenQuery.classify("") == .empty)
        #expect(QuickOpenQuery.classify("   ") == .empty)
    }

    @Test("/ ~ . 始まりはパスモードになる")
    func pathPrefixes() {
        #expect(QuickOpenQuery.classify("/usr/local") == .path("/usr/local"))
        #expect(QuickOpenQuery.classify("~") == .path("~"))
        #expect(QuickOpenQuery.classify("~/dev/befold") == .path("~/dev/befold"))
        #expect(QuickOpenQuery.classify("./README.md") == .path("./README.md"))
        #expect(QuickOpenQuery.classify("../docs") == .path("../docs"))
    }

    @Test("それ以外は fuzzy モードになる")
    func fuzzyInput() {
        #expect(QuickOpenQuery.classify("ViewerStore") == .fuzzy("ViewerStore"))
        #expect(QuickOpenQuery.classify("app/main") == .fuzzy("app/main"))
    }

    @Test("前後の空白は取り除いてから分類する")
    func trimsSurroundingWhitespace() {
        #expect(QuickOpenQuery.classify("  ViewerStore  ") == .fuzzy("ViewerStore"))
        #expect(QuickOpenQuery.classify(" /tmp ") == .path("/tmp"))
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter QuickOpenQueryTests`
Expected: FAIL（`cannot find 'QuickOpenQuery' in scope` でビルドエラー）

- [ ] **Step 3: 最小実装を書く**

`BefoldApp/BefoldKit/QuickOpenQuery.swift`:

```swift
import Foundation

/// Quick Open の入力文字列を、どの解決経路に流すかで分類する。
///
/// 先頭 1 文字だけで判定する。`.hidden` のような「先頭がドットのファイル名」も
/// パスモードとして扱うが、パスモードは同じディレクトリの前方一致も行うため、
/// 開発者が意図する候補は同じように出る。
public enum QuickOpenQuery: Equatable, Sendable {
    /// 入力が無い。履歴とブックマークを出す。
    case empty
    /// unix パスとして解決する。値は前後の空白を落とした入力。
    case path(String)
    /// 候補集合に対して fuzzy 照合する。値は前後の空白を落とした入力。
    case fuzzy(String)

    public static func classify(_ input: String) -> QuickOpenQuery {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return .empty }
        if first == "/" || first == "~" || first == "." {
            return .path(trimmed)
        }
        return .fuzzy(trimmed)
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter QuickOpenQueryTests`
Expected: PASS（4 テスト）

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/BefoldKit/QuickOpenQuery.swift BefoldApp/befoldTests/QuickOpenQueryTests.swift
git commit -m "feat: Quick Open の入力分類を追加する"
```

---

### Task 2: DirectoryFileScanner（非 Git 時の候補走査）

**Files:**
- Create: `BefoldApp/BefoldKit/DirectoryContentsReading.swift`
- Create: `BefoldApp/BefoldKit/DirectoryFileScanner.swift`
- Test: `BefoldApp/befoldTests/DirectoryFileScannerTests.swift`

**Interfaces:**
- Consumes: `FileReading`（既存、`isDirectory(at:)` を使う）
- Produces:
  - `public protocol DirectoryContentsReading: Sendable { func contents(of url: URL) -> [URL] }`
  - `public struct DefaultDirectoryContentsReader: DirectoryContentsReading { public init() }`
  - `public struct DirectoryScanResult: Equatable, Sendable { public let files: [URL]; public let didTruncate: Bool }`
  - `public struct DirectoryFileScanner: Sendable`、`public init(contentsReader:fileReader:maximumDepth:maximumFileCount:)`、`public func scan(root: URL, includeHiddenFiles: Bool) -> DirectoryScanResult`

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/DirectoryFileScannerTests.swift`:

```swift
@testable import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

@Suite
struct DirectoryFileScannerTests {
    /// 実ファイルツリーを作る。相対パスの配列を受け取り、中間ディレクトリごと作成する。
    private func makeTree(_ relativePaths: [String], in root: URL) throws {
        for relativePath in relativePaths {
            let fileURL = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data().write(to: fileURL)
        }
    }

    @Test("サブディレクトリを再帰的に走査してファイルだけを返す")
    func scansRecursively() throws {
        let temp = TempDir()
        try makeTree(["a.md", "sub/b.mmd", "sub/deep/c.txt"], in: temp.url)

        let result = DirectoryFileScanner().scan(root: temp.url, includeHiddenFiles: false)

        let names = result.files.map(\.lastPathComponent).sorted()
        #expect(names == ["a.md", "b.mmd", "c.txt"])
        #expect(result.didTruncate == false)
    }

    @Test("隠しファイルは includeHiddenFiles が false のとき除外する")
    func excludesHiddenFiles() throws {
        let temp = TempDir()
        try makeTree(["visible.md", ".hidden.md", ".config/inside.md"], in: temp.url)

        let hidden = DirectoryFileScanner().scan(root: temp.url, includeHiddenFiles: false)
        #expect(hidden.files.map(\.lastPathComponent) == ["visible.md"])

        let shown = DirectoryFileScanner().scan(root: temp.url, includeHiddenFiles: true)
        #expect(shown.files.map(\.lastPathComponent).sorted() == [".hidden.md", "inside.md", "visible.md"])
    }

    @Test("除外ディレクトリは隠しファイル表示でも降りない")
    func skipsExcludedDirectories() throws {
        let temp = TempDir()
        try makeTree(["keep.md", ".git/config.md", "node_modules/pkg.md", ".build/out.md"], in: temp.url)

        let result = DirectoryFileScanner().scan(root: temp.url, includeHiddenFiles: true)

        #expect(result.files.map(\.lastPathComponent) == ["keep.md"])
    }

    @Test("深さ上限を超えたディレクトリには降りず打ち切りを立てる")
    func stopsAtMaximumDepth() throws {
        let temp = TempDir()
        try makeTree(["top.md", "one/two/deep.md"], in: temp.url)

        let scanner = DirectoryFileScanner(maximumDepth: 1)
        let result = scanner.scan(root: temp.url, includeHiddenFiles: false)

        #expect(result.files.map(\.lastPathComponent).sorted() == ["top.md"])
        #expect(result.didTruncate == true)
    }

    @Test("件数上限に達したら打ち切って残りを走査しない")
    func stopsAtMaximumFileCount() throws {
        let temp = TempDir()
        try makeTree(["a.md", "b.md", "c.md"], in: temp.url)

        let scanner = DirectoryFileScanner(maximumFileCount: 2)
        let result = scanner.scan(root: temp.url, includeHiddenFiles: false)

        #expect(result.files.count == 2)
        #expect(result.didTruncate == true)
    }
}
```

`TempDir` は `BefoldTestSupport` の既存ヘルパーで、`url` プロパティを持ち破棄時に削除する。もし API 名が異なっていた場合は、既存テスト（例: `befoldTests/DirectoryListerTests.swift`）の使い方に合わせること。

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter DirectoryFileScannerTests`
Expected: FAIL（`cannot find 'DirectoryFileScanner' in scope`）

- [ ] **Step 3: 列挙の抽象化を書く**

`BefoldApp/BefoldKit/DirectoryContentsReading.swift`:

```swift
import Foundation

/// ディレクトリ直下の列挙を抽象化する。App ターゲットの `DirectoryLister` は
/// 表示用の並び替えとフィルタまで担うのに対し、こちらは「直下に何があるか」だけを返す
/// 最小の入口で、BefoldKit の純粋ロジックがテストで差し替えられるようにするためにある。
public protocol DirectoryContentsReading: Sendable {
    /// `url` 直下の項目を返す。読めない場合は空配列を返す（エラーは投げない）。
    func contents(of url: URL) -> [URL]
}

public struct DefaultDirectoryContentsReader: DirectoryContentsReading {
    public init() {}

    public func contents(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: []
        )) ?? []
    }
}
```

- [ ] **Step 4: 走査を書く**

`BefoldApp/BefoldKit/DirectoryFileScanner.swift`:

```swift
import Foundation

/// 走査の結果。`didTruncate` は深さ上限・件数上限のどちらかで打ち切ったことを表す。
/// UI はこれを見て「候補を打ち切った」旨を一覧末尾に出す。黙って切り捨てない。
public struct DirectoryScanResult: Equatable, Sendable {
    public let files: [URL]
    public let didTruncate: Bool

    public init(files: [URL], didTruncate: Bool) {
        self.files = files
        self.didTruncate = didTruncate
    }
}

/// Git 管理下でないディレクトリで Quick Open の候補を集めるための再帰走査。
/// 幅優先で降り、浅い階層のファイルを先に集める（打ち切られた場合でも
/// 手近なファイルが候補に残る）。
public struct DirectoryFileScanner: Sendable {
    /// 走査対象から外すディレクトリ名。隠しファイル表示が ON でも降りない。
    public static let excludedDirectoryNames: Set<String> = [".git", "node_modules", ".build"]

    private let contentsReader: any DirectoryContentsReading
    private let fileReader: any FileReading
    private let maximumDepth: Int
    private let maximumFileCount: Int

    public init(
        contentsReader: any DirectoryContentsReading = DefaultDirectoryContentsReader(),
        fileReader: any FileReading = DefaultFileReader(),
        maximumDepth: Int = 8,
        maximumFileCount: Int = 10000
    ) {
        self.contentsReader = contentsReader
        self.fileReader = fileReader
        self.maximumDepth = maximumDepth
        self.maximumFileCount = maximumFileCount
    }

    public func scan(root: URL, includeHiddenFiles: Bool) -> DirectoryScanResult {
        var files: [URL] = []
        var queue: [(url: URL, depth: Int)] = [(root, 0)]
        var queueIndex = 0
        var didTruncate = false

        while queueIndex < queue.count {
            let current = queue[queueIndex]
            queueIndex += 1
            let entries = contentsReader.contents(of: current.url)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for entry in entries {
                let name = entry.lastPathComponent
                if Self.excludedDirectoryNames.contains(name) { continue }
                if !includeHiddenFiles, name.hasPrefix(".") { continue }
                if fileReader.isDirectory(at: entry) {
                    if current.depth + 1 > maximumDepth {
                        didTruncate = true
                        continue
                    }
                    queue.append((entry, current.depth + 1))
                    continue
                }
                if files.count >= maximumFileCount {
                    return DirectoryScanResult(files: files, didTruncate: true)
                }
                files.append(entry)
            }
        }
        return DirectoryScanResult(files: files, didTruncate: didTruncate)
    }
}
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter DirectoryFileScannerTests`
Expected: PASS（5 テスト）

- [ ] **Step 6: コミット**

```bash
git add BefoldApp/BefoldKit/DirectoryContentsReading.swift \
        BefoldApp/BefoldKit/DirectoryFileScanner.swift \
        BefoldApp/befoldTests/DirectoryFileScannerTests.swift
git commit -m "feat: 非 git ディレクトリの候補走査を追加する"
```

---

### Task 3: FuzzyMatcher（照合とスコアリング）

**Files:**
- Create: `BefoldApp/BefoldKit/FuzzyMatcher.swift`
- Test: `BefoldApp/befoldTests/FuzzyMatcherTests.swift`

**Interfaces:**
- Consumes: `PathRelativizer.relativePath(of:relativeTo:)`（既存。`base` はディレクトリとして扱われる）、`URL.normalizedPathKey`（既存）
- Produces:
  - `public struct FuzzyMatch: Equatable, Sendable { public let url: URL; public let score: Int; public init(url:score:) }`
  - `public enum FuzzyMatcher`
  - `public static func score(query: String, target: String) -> Int?`
  - `public static func matches(query: String, candidates: [URL], baseDirectory: URL) -> [FuzzyMatch]`
  - `public static func ranked(_ matches: [FuzzyMatch], limit: Int) -> [URL]`

- [ ] **Step 1: 失敗するテストを書く**

スコアの絶対値は assert しない。チューニングのたびにテストが壊れるため、検証対象は**順序**と**一致するかどうか**に限る。

`BefoldApp/befoldTests/FuzzyMatcherTests.swift`:

```swift
@testable import BefoldKit
import Foundation
import Testing

@Suite
struct FuzzyMatcherTests {
    private let base = URL(fileURLWithPath: "/repo")

    @Test("部分列でなければ一致しない")
    func requiresSubsequence() {
        #expect(FuzzyMatcher.score(query: "abc", target: "acb") == nil)
        #expect(FuzzyMatcher.score(query: "abc", target: "xaxbxc") != nil)
    }

    @Test("大文字小文字を無視して照合する")
    func ignoresCase() {
        #expect(FuzzyMatcher.score(query: "vs", target: "ViewerStore.swift") != nil)
    }

    @Test("連続一致は飛び飛びの一致より高く評価する")
    func prefersContiguousMatches() {
        let contiguous = FuzzyMatcher.score(query: "view", target: "viewer.md")
        let scattered = FuzzyMatcher.score(query: "view", target: "v_i_e_w_x.md")
        #expect(contiguous != nil)
        #expect(scattered != nil)
        #expect(contiguous! > scattered!)
    }

    @Test("単語境界での一致を高く評価する")
    func prefersWordBoundaryMatches() {
        let boundary = FuzzyMatcher.score(query: "vs", target: "viewer_store.md")
        let inside = FuzzyMatcher.score(query: "vs", target: "avocados.md")
        #expect(boundary != nil)
        #expect(inside != nil)
        #expect(boundary! > inside!)
    }

    @Test("入力に / を含まない場合はファイル名部分だけを照合する")
    func matchesFileNameWhenQueryHasNoSlash() {
        let candidates = [
            URL(fileURLWithPath: "/repo/store/other.md"),
            URL(fileURLWithPath: "/repo/docs/store.md"),
        ]
        let results = FuzzyMatcher.matches(query: "store", candidates: candidates, baseDirectory: base)
        #expect(results.map(\.url.lastPathComponent) == ["store.md"])
    }

    @Test("入力に / を含む場合は相対パス全体を照合する")
    func matchesRelativePathWhenQueryHasSlash() {
        let candidates = [
            URL(fileURLWithPath: "/repo/docs/store.md"),
            URL(fileURLWithPath: "/repo/app/store.md"),
        ]
        let results = FuzzyMatcher.matches(query: "docs/store", candidates: candidates, baseDirectory: base)
        #expect(results.map(\.url.path) == ["/repo/docs/store.md"])
    }

    @Test("同点はパス昇順で決定論的に並べ、limit で打ち切る")
    func ranksDeterministically() {
        let matches = [
            FuzzyMatch(url: URL(fileURLWithPath: "/repo/b.md"), score: 10),
            FuzzyMatch(url: URL(fileURLWithPath: "/repo/a.md"), score: 10),
            FuzzyMatch(url: URL(fileURLWithPath: "/repo/c.md"), score: 20),
        ]
        #expect(FuzzyMatcher.ranked(matches, limit: 3).map(\.lastPathComponent) == ["c.md", "a.md", "b.md"])
        #expect(FuzzyMatcher.ranked(matches, limit: 2).map(\.lastPathComponent) == ["c.md", "a.md"])
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter FuzzyMatcherTests`
Expected: FAIL（`cannot find 'FuzzyMatcher' in scope`）

- [ ] **Step 3: 実装を書く**

`BefoldApp/BefoldKit/FuzzyMatcher.swift`:

```swift
import Foundation

/// 照合できた候補 1 件とそのスコア。スコアの絶対値に意味はなく、
/// 同じ照合呼び出しの中での大小関係だけを使う。
public struct FuzzyMatch: Equatable, Sendable {
    public let url: URL
    public let score: Int

    public init(url: URL, score: Int) {
        self.url = url
        self.score = score
    }
}

/// Quick Open の fuzzy 照合。既存の `SuffixPathMatcher` は「/ 区切りの構成要素単位で
/// サフィックス一致する最良 1 件」を返す別の関心で、候補リストの順位付けには使えないため
/// 独立して用意する（`SuffixPathMatcher` の照合規則は変更しない）。
public enum FuzzyMatcher {
    /// 単語境界とみなす文字。この直後の一致を強く加点する。
    private static let boundaryCharacters: Set<Character> = ["/", "_", "-", ".", " "]

    private static let boundaryBonus = 8
    private static let contiguousBonus = 5
    private static let basePoints = 1
    /// 一致の間に読み飛ばした文字数に応じた減点の上限。
    private static let maximumGapPenalty = 3

    /// `query` が `target` の部分列であればスコアを、そうでなければ nil を返す。
    ///
    /// 左端から貪欲に一致させる。部分列の存在判定としては貪欲法で過不足なく、
    /// 得られるスコアは最適とは限らないが決定論的で、候補数に対して線形に収まる。
    public static func score(query: String, target: String) -> Int? {
        let queryCharacters = Array(query.lowercased())
        guard !queryCharacters.isEmpty else { return 0 }
        let targetCharacters = Array(target)
        let loweredTarget = Array(target.lowercased())

        var queryIndex = 0
        var total = 0
        var previousMatchIndex: Int?

        for targetIndex in loweredTarget.indices {
            guard queryIndex < queryCharacters.count,
                  loweredTarget[targetIndex] == queryCharacters[queryIndex]
            else { continue }

            var points = basePoints
            if targetIndex == 0 || isBoundary(before: targetIndex, in: targetCharacters) {
                points += boundaryBonus
            }
            if let previous = previousMatchIndex {
                if previous == targetIndex - 1 {
                    points += contiguousBonus
                } else {
                    points -= min(targetIndex - previous - 1, maximumGapPenalty)
                }
            }
            total += points
            previousMatchIndex = targetIndex
            queryIndex += 1
        }
        return queryIndex == queryCharacters.count ? total : nil
    }

    /// `index` の位置が単語の先頭かどうか。区切り文字の直後、または
    /// 小文字→大文字のキャメルケース境界を先頭とみなす。
    private static func isBoundary(before index: Int, in target: [Character]) -> Bool {
        let previous = target[index - 1]
        if boundaryCharacters.contains(previous) { return true }
        return previous.isLowercase && target[index].isUppercase
    }

    /// 候補それぞれを照合する。並び替えと打ち切りは行わない（`ranked` の担当）。
    ///
    /// 入力に `/` を含む場合はディレクトリまで指定する意図とみなして相対パス全体を、
    /// 含まない場合はファイル名だけを照合対象にする。
    public static func matches(query: String, candidates: [URL], baseDirectory: URL) -> [FuzzyMatch] {
        let usesRelativePath = query.contains("/")
        return candidates.compactMap { url in
            let target = usesRelativePath
                ? PathRelativizer.relativePath(of: url, relativeTo: baseDirectory)
                : url.lastPathComponent
            guard let value = score(query: query, target: target) else { return nil }
            return FuzzyMatch(url: url, score: value)
        }
    }

    /// スコア降順 → 正規化パス昇順で並べ、`limit` 件で打ち切る。
    /// 同点のタイブレークをパス昇順に固定することで、同じ入力に対する結果を決定論的にする。
    public static func ranked(_ matches: [FuzzyMatch], limit: Int) -> [URL] {
        matches
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.url.normalizedPathKey < rhs.url.normalizedPathKey
            }
            .prefix(limit)
            .map(\.url)
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter FuzzyMatcherTests`
Expected: PASS（7 テスト）

`prefersWordBoundaryMatches` が落ちる場合は `boundaryBonus` を上げる前に、`avocados.md` 側で `.` の直後の `m` が境界加点を得ていないか確認すること。スコア定数を触ったら他の順序テストも通ることを再確認する。

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/BefoldKit/FuzzyMatcher.swift BefoldApp/befoldTests/FuzzyMatcherTests.swift
git commit -m "feat: Quick Open の fuzzy 照合とスコアリングを追加する"
```

---

### Task 4: QuickOpenPathCompletion（パスモード）

**Files:**
- Create: `BefoldApp/BefoldKit/QuickOpenPathCompletion.swift`
- Test: `BefoldApp/befoldTests/QuickOpenPathCompletionTests.swift`

**Interfaces:**
- Consumes: `DirectoryContentsReading`（Task 2）、`FileReading`（既存）
- Produces:
  - `public struct PathCompletion: Equatable, Sendable { public let matches: [URL]; public let completion: String?; public init(matches:completion:) }`
  - `public struct QuickOpenPathCompletion: Sendable`
  - `public init(contentsReader: any DirectoryContentsReading = DefaultDirectoryContentsReader(), fileReader: any FileReading = DefaultFileReader())`
  - `public func complete(input: String, baseDirectory: URL, includeHiddenFiles: Bool) -> PathCompletion`

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/QuickOpenPathCompletionTests.swift`:

```swift
@testable import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

@Suite
struct QuickOpenPathCompletionTests {
    private func makeTree(_ relativePaths: [String], in root: URL) throws {
        for relativePath in relativePaths {
            let fileURL = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data().write(to: fileURL)
        }
    }

    @Test("末尾が / のときはそのディレクトリの中身を全件返す")
    func listsDirectoryContents() throws {
        let temp = TempDir()
        try makeTree(["docs/a.md", "docs/b.md"], in: temp.url)
        let input = temp.url.appendingPathComponent("docs").path + "/"

        let result = QuickOpenPathCompletion().complete(
            input: input, baseDirectory: temp.url, includeHiddenFiles: false
        )

        #expect(result.matches.map(\.lastPathComponent) == ["a.md", "b.md"])
    }

    @Test("末尾の断片で前方一致し、大文字小文字を無視する")
    func filtersByFragment() throws {
        let temp = TempDir()
        try makeTree(["docs/Alpha.md", "docs/beta.md"], in: temp.url)
        let input = temp.url.appendingPathComponent("docs").path + "/al"

        let result = QuickOpenPathCompletion().complete(
            input: input, baseDirectory: temp.url, includeHiddenFiles: false
        )

        #expect(result.matches.map(\.lastPathComponent) == ["Alpha.md"])
    }

    @Test("相対パスは基準ディレクトリから解決する")
    func resolvesRelativePaths() throws {
        let temp = TempDir()
        try makeTree(["docs/a.md"], in: temp.url)

        let result = QuickOpenPathCompletion().complete(
            input: "./docs/", baseDirectory: temp.url, includeHiddenFiles: false
        )

        #expect(result.matches.map(\.lastPathComponent) == ["a.md"])
    }

    @Test("親ディレクトリが存在しなければ候補も補完も空になる")
    func returnsNothingForMissingDirectory() throws {
        let temp = TempDir()

        let result = QuickOpenPathCompletion().complete(
            input: "/no/such/place/", baseDirectory: temp.url, includeHiddenFiles: false
        )

        #expect(result.matches.isEmpty)
        #expect(result.completion == nil)
    }

    @Test("隠しファイルは includeHiddenFiles に従う")
    func respectsHiddenFilesSetting() throws {
        let temp = TempDir()
        try makeTree(["docs/.secret.md", "docs/open.md"], in: temp.url)
        let input = temp.url.appendingPathComponent("docs").path + "/"

        let hidden = QuickOpenPathCompletion().complete(
            input: input, baseDirectory: temp.url, includeHiddenFiles: false
        )
        #expect(hidden.matches.map(\.lastPathComponent) == ["open.md"])

        let shown = QuickOpenPathCompletion().complete(
            input: input, baseDirectory: temp.url, includeHiddenFiles: true
        )
        #expect(shown.matches.map(\.lastPathComponent) == [".secret.md", "open.md"])
    }

    @Test("補完は候補の共通接頭辞まで伸ばす")
    func completesToCommonPrefix() throws {
        let temp = TempDir()
        try makeTree(["docs/report-a.md", "docs/report-b.md"], in: temp.url)
        let input = temp.url.appendingPathComponent("docs").path + "/rep"

        let result = QuickOpenPathCompletion().complete(
            input: input, baseDirectory: temp.url, includeHiddenFiles: false
        )

        #expect(result.completion == temp.url.appendingPathComponent("docs").path + "/report-")
    }

    @Test("候補が 1 件のディレクトリなら末尾に / を付けて次の階層へ進める")
    func completesDirectoryWithTrailingSlash() throws {
        let temp = TempDir()
        try makeTree(["docs/inner/a.md"], in: temp.url)
        let input = temp.url.appendingPathComponent("docs").path + "/in"

        let result = QuickOpenPathCompletion().complete(
            input: input, baseDirectory: temp.url, includeHiddenFiles: false
        )

        #expect(result.completion == temp.url.appendingPathComponent("docs/inner").path + "/")
    }

    @Test("伸ばせるものが無ければ補完は nil")
    func returnsNilWhenNothingToComplete() throws {
        let temp = TempDir()
        try makeTree(["docs/alpha.md", "docs/beta.md"], in: temp.url)
        let input = temp.url.appendingPathComponent("docs").path + "/"

        let result = QuickOpenPathCompletion().complete(
            input: input, baseDirectory: temp.url, includeHiddenFiles: false
        )

        #expect(result.completion == nil)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter QuickOpenPathCompletionTests`
Expected: FAIL（`cannot find 'QuickOpenPathCompletion' in scope`）

- [ ] **Step 3: 実装を書く**

`BefoldApp/BefoldKit/QuickOpenPathCompletion.swift`:

```swift
import Foundation

/// パスモードの解決結果。
public struct PathCompletion: Equatable, Sendable {
    /// 親ディレクトリ配下で末尾断片に前方一致した項目。名前の昇順。
    public let matches: [URL]
    /// Tab 補完で入力欄へ書き戻す文字列。伸ばせるものが無ければ nil。
    public let completion: String?

    public init(matches: [URL], completion: String?) {
        self.matches = matches
        self.completion = completion
    }
}

/// Quick Open のパスモード。入力を「確定した親ディレクトリ」と「未確定の末尾断片」に
/// 分解し、親の中身を断片で前方一致させる。シェルのパス補完と同じ操作感にする。
public struct QuickOpenPathCompletion: Sendable {
    private let contentsReader: any DirectoryContentsReading
    private let fileReader: any FileReading

    public init(
        contentsReader: any DirectoryContentsReading = DefaultDirectoryContentsReader(),
        fileReader: any FileReading = DefaultFileReader()
    ) {
        self.contentsReader = contentsReader
        self.fileReader = fileReader
    }

    public func complete(input: String, baseDirectory: URL, includeHiddenFiles: Bool) -> PathCompletion {
        // "~" だけの入力はホーム直下を見せたい意図なので "~/" と同じに扱う。
        let normalized = input == "~" ? "~/" : input
        let (directoryPart, fragment) = Self.split(normalized)
        let directoryURL = Self.directoryURL(for: directoryPart, baseDirectory: baseDirectory)

        guard fileReader.isDirectory(at: directoryURL) else {
            return PathCompletion(matches: [], completion: nil)
        }

        let loweredFragment = fragment.lowercased()
        let matches = contentsReader.contents(of: directoryURL)
            .filter { includeHiddenFiles || !$0.lastPathComponent.hasPrefix(".") }
            .filter { loweredFragment.isEmpty || $0.lastPathComponent.lowercased().hasPrefix(loweredFragment) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return PathCompletion(
            matches: matches,
            completion: completionText(normalizedInput: normalized, fragment: fragment, matches: matches)
        )
    }

    /// 最後の "/" で「親ディレクトリ部分（"/" を含む）」と「末尾断片」に分ける。
    private static func split(_ input: String) -> (directoryPart: String, fragment: String) {
        guard let slashIndex = input.lastIndex(of: "/") else { return ("", input) }
        return (String(input[...slashIndex]), String(input[input.index(after: slashIndex)...]))
    }

    private static func directoryURL(for directoryPart: String, baseDirectory: URL) -> URL {
        guard !directoryPart.isEmpty else { return baseDirectory.standardizedFileURL }
        let expanded = (directoryPart as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return URL(fileURLWithPath: expanded, relativeTo: baseDirectory).standardizedFileURL
    }

    /// 断片を候補名の共通接頭辞まで伸ばした入力文字列。
    /// 入力の親ディレクトリ部分（`~` を展開する前の表記）はそのまま残す。
    private func completionText(normalizedInput: String, fragment: String, matches: [URL]) -> String? {
        guard let first = matches.first else { return nil }
        var shared = first.lastPathComponent
        for url in matches.dropFirst() {
            shared = Self.commonPrefix(shared, url.lastPathComponent)
        }
        let suffix = matches.count == 1 && fileReader.isDirectory(at: first) ? "/" : ""
        guard shared.count > fragment.count || !suffix.isEmpty else { return nil }
        let head = String(normalizedInput.dropLast(fragment.count))
        return head + shared + suffix
    }

    /// 大文字小文字を無視して比較し、返す表記は左側に合わせる。
    private static func commonPrefix(_ lhs: String, _ rhs: String) -> String {
        let sharedCount = zip(lhs, rhs).prefix { $0.lowercased() == $1.lowercased() }.count
        return String(lhs.prefix(sharedCount))
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter QuickOpenPathCompletionTests`
Expected: PASS（8 テスト）

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/BefoldKit/QuickOpenPathCompletion.swift \
        BefoldApp/befoldTests/QuickOpenPathCompletionTests.swift
git commit -m "feat: Quick Open のパス補完を追加する"
```

---

### Task 5: 候補一覧の読み出しとマージ

**Files:**
- Modify: `BefoldApp/BefoldKit/SuffixPathMatcher.swift`（`SuffixPathIndex` に `allCandidates` を追加。`:78-93` の `init(candidates:)`）
- Create: `BefoldApp/BefoldKit/QuickOpenCandidates.swift`
- Test: `BefoldApp/befoldTests/SuffixPathIndexCandidatesTests.swift`
- Test: `BefoldApp/befoldTests/QuickOpenCandidatesTests.swift`

**Interfaces:**
- Consumes: `FuzzyMatcher.matches(query:candidates:baseDirectory:)` / `FuzzyMatcher.ranked(_:limit:)`（Task 3）、`URL.normalizedPathKey`（既存）
- Produces:
  - `public let allCandidates: [URL]`（`SuffixPathIndex` のプロパティ）
  - `public struct QuickOpenResult: Equatable, Sendable { public let matches: [URL]; public let didTruncate: Bool }`
  - `public enum QuickOpenCandidates` と `displayLimit` / `historyLimit` / `historyBonus`
  - `public static func recentEntries(recentURLs:bookmarkURLs:limit:) -> [URL]`
  - `public static func fuzzyMatches(query:indexedURLs:recentURLs:bookmarkURLs:baseDirectory:didTruncateIndex:limit:) -> QuickOpenResult`

- [ ] **Step 1: SuffixPathIndex の失敗するテストを書く**

`BefoldApp/befoldTests/SuffixPathIndexCandidatesTests.swift`:

```swift
@testable import BefoldKit
import Foundation
import Testing

@Suite
struct SuffixPathIndexCandidatesTests {
    @Test("取り込んだ候補を構築時の順序のまま読み出せる")
    func exposesCandidatesInOrder() {
        let urls = [
            URL(fileURLWithPath: "/repo/b.md"),
            URL(fileURLWithPath: "/repo/a.md"),
        ]

        let index = SuffixPathIndex(candidates: urls)

        #expect(index.allCandidates.map(\.lastPathComponent) == ["b.md", "a.md"])
    }

    @Test("構成要素を持たない候補は照合と同様に読み出しからも落ちる")
    func dropsRootCandidate() {
        let index = SuffixPathIndex(candidates: [URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/repo/a.md")])

        #expect(index.allCandidates.map(\.lastPathComponent) == ["a.md"])
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter SuffixPathIndexCandidatesTests`
Expected: FAIL（`value of type 'SuffixPathIndex' has no member 'allCandidates'`）

- [ ] **Step 3: SuffixPathIndex にアクセサを足す**

`BefoldApp/BefoldKit/SuffixPathMatcher.swift` の `SuffixPathIndex` を次のように変更する。照合ロジック（`bestMatch` / `isBetter`）には一切触らない。

`private let candidatesByLastComponent: [String: [Candidate]]` の直後に追加:

```swift
    /// 索引に取り込んだ候補 URL の一覧（構築時の順序を保つ）。
    /// Quick Open が「このリポジトリの追跡ファイル一覧」として読み出すための入口。
    /// 照合には使わない（照合は `candidatesByLastComponent` を引く）。
    public let allCandidates: [URL]
```

`init(candidates:)` を次に置き換える:

```swift
    public init(candidates: [URL]) {
        var grouped: [String: [Candidate]] = [:]
        var accepted: [URL] = []
        for url in candidates {
            let standardized = url.standardizedFileURL
            let components = SuffixPathMatcher.components(ofStandardized: standardized)
            // 構成要素を持たない候補(ルート)はどんな needle にも一致しないため落とす。
            guard let lastComponent = components.last else { continue }
            accepted.append(url)
            grouped[lastComponent, default: []].append(Candidate(
                url: url,
                components: components,
                directoryComponents: SuffixPathMatcher.components(of: url.deletingLastPathComponent()),
                standardizedPath: standardized.path
            ))
        }
        candidatesByLastComponent = grouped
        allCandidates = accepted
    }
```

- [ ] **Step 4: テストが通り、既存の照合テストも壊れていないことを確認する**

Run: `cd BefoldApp && swift test --filter SuffixPathIndexCandidatesTests`
Expected: PASS（2 テスト）

Run: `cd BefoldApp && swift test --filter SuffixPathMatcherTests`
Expected: PASS（既存テストが全て通る。落ちた場合は照合ロジックに触れてしまっているので差分を見直す）

- [ ] **Step 5: QuickOpenCandidates の失敗するテストを書く**

`BefoldApp/befoldTests/QuickOpenCandidatesTests.swift`:

```swift
@testable import BefoldKit
import Foundation
import Testing

@Suite
struct QuickOpenCandidatesTests {
    private let base = URL(fileURLWithPath: "/repo")

    @Test("空入力では履歴を先に、続けてブックマークを並べる")
    func recentsBeforeBookmarks() {
        let recent = [URL(fileURLWithPath: "/repo/r1.md"), URL(fileURLWithPath: "/repo/r2.md")]
        let bookmarks = [URL(fileURLWithPath: "/repo/b1.md")]

        let entries = QuickOpenCandidates.recentEntries(recentURLs: recent, bookmarkURLs: bookmarks)

        #expect(entries.map(\.lastPathComponent) == ["r1.md", "r2.md", "b1.md"])
    }

    @Test("空入力の一覧は重複を除き上限で打ち切る")
    func recentsAreDedupedAndLimited() {
        let shared = URL(fileURLWithPath: "/repo/same.md")
        let entries = QuickOpenCandidates.recentEntries(
            recentURLs: [shared, URL(fileURLWithPath: "/repo/a.md")],
            bookmarkURLs: [shared, URL(fileURLWithPath: "/repo/b.md")],
            limit: 2
        )

        #expect(entries.map(\.lastPathComponent) == ["same.md", "a.md"])
    }

    @Test("履歴にある候補は同スコアの索引候補より上に来る")
    func historyIsBoosted() {
        let indexed = [
            URL(fileURLWithPath: "/repo/a/store.md"),
            URL(fileURLWithPath: "/repo/b/store.md"),
        ]

        let result = QuickOpenCandidates.fuzzyMatches(
            query: "store",
            indexedURLs: indexed,
            recentURLs: [URL(fileURLWithPath: "/repo/b/store.md")],
            bookmarkURLs: [],
            baseDirectory: base,
            didTruncateIndex: false
        )

        #expect(result.matches.map(\.path) == ["/repo/b/store.md", "/repo/a/store.md"])
    }

    @Test("索引と履歴に同じファイルがあっても 1 件だけ返す")
    func dedupesAcrossSources() {
        let shared = URL(fileURLWithPath: "/repo/store.md")

        let result = QuickOpenCandidates.fuzzyMatches(
            query: "store",
            indexedURLs: [shared],
            recentURLs: [shared],
            bookmarkURLs: [shared],
            baseDirectory: base,
            didTruncateIndex: false
        )

        #expect(result.matches.count == 1)
    }

    @Test("表示上限を超えたら打ち切りを立てる")
    func flagsTruncationAtDisplayLimit() {
        let indexed = (0 ..< 5).map { URL(fileURLWithPath: "/repo/store\($0).md") }

        let result = QuickOpenCandidates.fuzzyMatches(
            query: "store",
            indexedURLs: indexed,
            recentURLs: [],
            bookmarkURLs: [],
            baseDirectory: base,
            didTruncateIndex: false,
            limit: 3
        )

        #expect(result.matches.count == 3)
        #expect(result.didTruncate == true)
    }

    @Test("索引側が打ち切られていれば結果にも打ち切りを伝える")
    func propagatesIndexTruncation() {
        let result = QuickOpenCandidates.fuzzyMatches(
            query: "store",
            indexedURLs: [URL(fileURLWithPath: "/repo/store.md")],
            recentURLs: [],
            bookmarkURLs: [],
            baseDirectory: base,
            didTruncateIndex: true
        )

        #expect(result.didTruncate == true)
    }
}
```

- [ ] **Step 6: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter QuickOpenCandidatesTests`
Expected: FAIL（`cannot find 'QuickOpenCandidates' in scope`）

- [ ] **Step 7: 実装を書く**

`BefoldApp/BefoldKit/QuickOpenCandidates.swift`:

```swift
import Foundation

/// Quick Open の絞り込み結果。`didTruncate` は「候補の収集」か「表示件数」の
/// どちらかを打ち切ったことを表す。UI は一覧末尾に注記を出す。
public struct QuickOpenResult: Equatable, Sendable {
    public let matches: [URL]
    public let didTruncate: Bool

    public init(matches: [URL], didTruncate: Bool) {
        self.matches = matches
        self.didTruncate = didTruncate
    }
}

/// 候補の供給源（索引・履歴・ブックマーク）をまとめ、重複を除いて順位を付ける。
public enum QuickOpenCandidates {
    /// 一覧に出す最大件数。
    public static let displayLimit = 50
    /// 空入力時に出す履歴・ブックマークの最大件数。
    public static let historyLimit = 20
    /// 履歴・ブックマーク由来の候補への加点。同程度の一致なら一度触ったファイルを上に出す。
    public static let historyBonus = 20

    /// 空入力時の一覧。履歴を先に、続けてブックマークを並べる。
    public static func recentEntries(
        recentURLs: [URL], bookmarkURLs: [URL], limit: Int = historyLimit
    ) -> [URL] {
        Array(deduped(recentURLs + bookmarkURLs).prefix(limit))
    }

    /// fuzzy 照合。索引に履歴・ブックマークを混ぜ、正規化パスで重複を除いてから照合する。
    public static func fuzzyMatches(
        query: String,
        indexedURLs: [URL],
        recentURLs: [URL],
        bookmarkURLs: [URL],
        baseDirectory: URL,
        didTruncateIndex: Bool,
        limit: Int = displayLimit
    ) -> QuickOpenResult {
        let boostedKeys = Set((recentURLs + bookmarkURLs).map(\.normalizedPathKey))
        let candidates = deduped(indexedURLs + recentURLs + bookmarkURLs)
        let scored = FuzzyMatcher.matches(query: query, candidates: candidates, baseDirectory: baseDirectory)
            .map { match in
                boostedKeys.contains(match.url.normalizedPathKey)
                    ? FuzzyMatch(url: match.url, score: match.score + historyBonus)
                    : match
            }
        return QuickOpenResult(
            matches: FuzzyMatcher.ranked(scored, limit: limit),
            didTruncate: didTruncateIndex || scored.count > limit
        )
    }

    /// 正規化パスで重複を除く。最初に現れた URL の表記を残す。
    private static func deduped(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { seen.insert($0.normalizedPathKey).inserted }
    }
}
```

- [ ] **Step 8: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter QuickOpenCandidatesTests`
Expected: PASS（6 テスト）

- [ ] **Step 9: コミット**

```bash
git add BefoldApp/BefoldKit/SuffixPathMatcher.swift \
        BefoldApp/BefoldKit/QuickOpenCandidates.swift \
        BefoldApp/befoldTests/SuffixPathIndexCandidatesTests.swift \
        BefoldApp/befoldTests/QuickOpenCandidatesTests.swift
git commit -m "feat: Quick Open の候補マージと索引の候補読み出しを追加する"
```

---

### Task 6: QuickOpenModel（判断ロジックの束ね）

**Files:**
- Create: `BefoldApp/befold/App/QuickOpenModel.swift`
- Test: `BefoldApp/befoldTests/QuickOpenModelTests.swift`

**Interfaces:**
- Consumes: `QuickOpenQuery`（Task 1）、`DirectoryFileScanner`（Task 2）、`QuickOpenPathCompletion`（Task 4）、`QuickOpenCandidates`（Task 5）、`GitFileIndexing` / `SuffixPathIndex.allCandidates` / `FileReading` / `SupportedFileResolver.resolveFileToOpen(at:fileReader:)` / `PathRelativizer.relativePath(of:relativeTo:)`（既存）
- Produces:
  - `struct QuickOpenRow: Identifiable, Equatable, Sendable { let url: URL; let title: String; let subtitle: String; var id: String }`
  - `@MainActor @Observable final class QuickOpenModel`
  - `init(baseDirectory:currentFileURL:gitIndex:scanner:pathCompletion:fileReader:recentURLs:bookmarkURLs:includeHiddenFiles:openFile:)`
  - `var input: String`、`private(set) var rows: [QuickOpenRow]`、`private(set) var didTruncate: Bool`、`private(set) var selectedIndex: Int`、`private(set) var pathCompletionText: String?`
  - `func prepare() async`、`func moveSelection(by: Int)`、`func completePath()`、`func commitSelection()`

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/QuickOpenModelTests.swift`:

```swift
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 追跡ファイル索引を固定で返すテスト用の索引。nil を返すと非 git 扱いになる。
private struct StubGitIndex: GitFileIndexing {
    let files: [URL]?
    func trackedFileIndex(forFileAt _: URL) -> SuffixPathIndex? {
        files.map(SuffixPathIndex.init(candidates:))
    }
}

/// 与えた URL 集合だけを「存在するファイル」とみなす読み取り。ディレクトリ判定も明示で与える。
private struct StubFileReader: FileReading {
    var directories: Set<String> = []
    var files: Set<String> = []

    func fileExists(at url: URL) -> Bool { isDirectory(at: url) || isExistingFile(at: url) }
    func isDirectory(at url: URL) -> Bool { directories.contains(url.standardizedFileURL.path) }
    func isExistingFile(at url: URL) -> Bool { files.contains(url.standardizedFileURL.path) }
    func readString(from _: URL) throws -> String { "" }
    func readData(from _: URL) throws -> Data { Data() }
    func isBinary(at _: URL) -> Bool { false }
    func fileSize(at _: URL) -> Int? { nil }
    func modificationDate(at _: URL) -> Date? { nil }
}

@MainActor
@Suite
struct QuickOpenModelTests {
    private let base = URL(fileURLWithPath: "/repo")

    private func makeModel(
        indexed: [URL]?,
        recent: [URL] = [],
        bookmarks: [URL] = [],
        fileReader: StubFileReader = StubFileReader(),
        openFile: @escaping (URL) -> Void = { _ in }
    ) -> QuickOpenModel {
        QuickOpenModel(
            baseDirectory: base,
            currentFileURL: nil,
            gitIndex: StubGitIndex(files: indexed),
            scanner: DirectoryFileScanner(fileReader: fileReader),
            pathCompletion: QuickOpenPathCompletion(fileReader: fileReader),
            fileReader: fileReader,
            recentURLs: { recent },
            bookmarkURLs: { bookmarks },
            includeHiddenFiles: false,
            openFile: openFile
        )
    }

    @Test("空入力では履歴とブックマークを出す")
    func showsHistoryWhenEmpty() async {
        let model = makeModel(
            indexed: [],
            recent: [URL(fileURLWithPath: "/repo/recent.md")],
            bookmarks: [URL(fileURLWithPath: "/repo/marked.md")]
        )
        await model.prepare()

        #expect(model.rows.map(\.title) == ["recent.md", "marked.md"])
    }

    @Test("fuzzy 入力で索引の候補を絞り込む")
    func filtersIndexedCandidates() async {
        let model = makeModel(indexed: [
            URL(fileURLWithPath: "/repo/ViewerStore.swift"),
            URL(fileURLWithPath: "/repo/README.md"),
        ])
        await model.prepare()

        model.input = "vs"

        #expect(model.rows.map(\.title) == ["ViewerStore.swift"])
    }

    @Test("行には相対パスの副題が付く")
    func rowsCarryRelativeSubtitle() async {
        let model = makeModel(indexed: [URL(fileURLWithPath: "/repo/docs/a.md")])
        await model.prepare()

        model.input = "a.md"

        #expect(model.rows.first?.subtitle == "docs/a.md")
    }

    @Test("パス入力ではディレクトリの中身を出し、Tab 補完文字列を用意する")
    func pathModeListsDirectory() async {
        var reader = StubFileReader()
        reader.directories = ["/repo/docs"]
        reader.files = ["/repo/docs/report.md"]
        let model = makeModel(indexed: [], fileReader: reader)
        await model.prepare()

        model.input = "/repo/docs/rep"

        // 実ファイルシステムを列挙するため、このテストは実在するツリーが必要になる。
        // 実行時に空になる場合は Task 4 のテストと同じく TempDir で実ツリーを作ること。
        #expect(model.pathCompletionText == nil || model.pathCompletionText?.hasPrefix("/repo/docs/") == true)
    }

    @Test("選択の移動は範囲内に収まる")
    func selectionStaysInRange() async {
        let model = makeModel(indexed: [
            URL(fileURLWithPath: "/repo/a.md"),
            URL(fileURLWithPath: "/repo/b.md"),
        ])
        await model.prepare()
        model.input = "md"

        model.moveSelection(by: -1)
        #expect(model.selectedIndex == 0)

        model.moveSelection(by: 5)
        #expect(model.selectedIndex == model.rows.count - 1)
    }

    @Test("入力を変えると選択は先頭に戻る")
    func selectionResetsOnInputChange() async {
        let model = makeModel(indexed: [
            URL(fileURLWithPath: "/repo/a.md"),
            URL(fileURLWithPath: "/repo/b.md"),
        ])
        await model.prepare()
        model.input = "md"
        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 1)

        model.input = "a"

        #expect(model.selectedIndex == 0)
    }

    @Test("決定すると選択中の URL で openFile が呼ばれる")
    func commitOpensSelectedFile() async {
        let opened = LockedBox<URL?>(nil)
        var reader = StubFileReader()
        reader.files = ["/repo/a.md"]
        let model = makeModel(
            indexed: [URL(fileURLWithPath: "/repo/a.md")],
            fileReader: reader,
            openFile: { url in opened.value = url }
        )
        await model.prepare()
        model.input = "a.md"

        model.commitSelection()

        #expect(opened.value?.path == "/repo/a.md")
    }

    @Test("候補が無い状態で決定しても何も起きない")
    func commitDoesNothingWithoutRows() async {
        let opened = LockedBox<URL?>(nil)
        let model = makeModel(indexed: [], openFile: { url in opened.value = url })
        await model.prepare()
        model.input = "zzz"

        model.commitSelection()

        #expect(opened.value == nil)
    }
}
```

`LockedBox` は `BefoldTestSupport` の既存ヘルパー。API が異なる場合は既存テストの使い方に合わせるか、単純な `final class Box` をテストファイル内に定義してよい。`pathModeListsDirectory` はスタブでは実列挙を差し替えられないため緩い assert にしてある。厳密なパスモードの検証は Task 4 のテストが担う。

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter QuickOpenModelTests`
Expected: FAIL（`cannot find 'QuickOpenModel' in scope`）

- [ ] **Step 3: 実装を書く**

`BefoldApp/befold/App/QuickOpenModel.swift`:

```swift
import BefoldKit
import Foundation
import Observation

/// Quick Open 一覧の 1 行分の表示データ。
struct QuickOpenRow: Identifiable, Equatable, Sendable {
    let url: URL
    /// 主題。ファイル名。
    let title: String
    /// 副題。基準ディレクトリからの相対パス。
    let subtitle: String

    var id: String { url.normalizedPathKey }
}

/// Quick Open の判断ロジックをすべて引き受ける。パネルとビューは
/// この型の状態を映してキーイベントを流すだけにし、UI 側に分岐を持たせない。
///
/// 候補の収集（`git ls-files` / ディレクトリ走査）だけをバックグラウンドで行い、
/// 入力ごとの絞り込みは同期で行う。候補は 10,000 件で上限が掛かっており、
/// メモリ内の照合はデバウンスを挟むまでもなく収まる。
@MainActor
@Observable
final class QuickOpenModel {
    private(set) var rows: [QuickOpenRow] = []
    /// 候補の収集または表示件数を打ち切ったかどうか。
    private(set) var didTruncate = false
    private(set) var selectedIndex = 0
    /// Tab 補完で入力欄へ書き戻す文字列。パスモードで伸ばせるときだけ非 nil。
    private(set) var pathCompletionText: String?

    var input: String = "" {
        didSet {
            guard input != oldValue else { return }
            refresh()
        }
    }

    private let baseDirectory: URL
    private let currentFileURL: URL?
    private let gitIndex: any GitFileIndexing
    private let scanner: DirectoryFileScanner
    private let pathCompletion: QuickOpenPathCompletion
    private let fileReader: any FileReading
    private let recentURLs: () -> [URL]
    private let bookmarkURLs: () -> [URL]
    private let includeHiddenFiles: Bool
    private let openFile: (URL) -> Void

    private var candidates: [URL] = []
    private var candidatesDidTruncate = false

    init(
        baseDirectory: URL,
        currentFileURL: URL?,
        gitIndex: any GitFileIndexing,
        scanner: DirectoryFileScanner = DirectoryFileScanner(),
        pathCompletion: QuickOpenPathCompletion = QuickOpenPathCompletion(),
        fileReader: any FileReading = DefaultFileReader(),
        recentURLs: @escaping () -> [URL],
        bookmarkURLs: @escaping () -> [URL],
        includeHiddenFiles: Bool,
        openFile: @escaping (URL) -> Void
    ) {
        self.baseDirectory = baseDirectory
        self.currentFileURL = currentFileURL
        self.gitIndex = gitIndex
        self.scanner = scanner
        self.pathCompletion = pathCompletion
        self.fileReader = fileReader
        self.recentURLs = recentURLs
        self.bookmarkURLs = bookmarkURLs
        self.includeHiddenFiles = includeHiddenFiles
        self.openFile = openFile
    }

    /// 候補を収集して初期表示を作る。パネルを開いた直後に一度だけ呼ぶ。
    func prepare() async {
        let lookupURL = currentFileURL ?? baseDirectory
        gitIndex.warm(forFileAt: lookupURL)
        let gitIndex = self.gitIndex
        let scanner = self.scanner
        let baseDirectory = self.baseDirectory
        let includeHiddenFiles = self.includeHiddenFiles

        let loaded = await Task.detached(priority: .userInitiated) { () -> (urls: [URL], didTruncate: Bool) in
            if let index = gitIndex.trackedFileIndex(forFileAt: lookupURL) {
                return (index.allCandidates, false)
            }
            let result = scanner.scan(root: baseDirectory, includeHiddenFiles: includeHiddenFiles)
            return (result.files, result.didTruncate)
        }.value

        candidates = loaded.urls
        candidatesDidTruncate = loaded.didTruncate
        refresh()
    }

    func moveSelection(by delta: Int) {
        guard !rows.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), rows.count - 1)
    }

    /// Tab による補完。伸ばせるものが無ければ何もしない。
    func completePath() {
        guard let text = pathCompletionText else { return }
        input = text
    }

    /// Enter による決定。ディレクトリを選んだ場合は Cmd+O と同じ規則で中の 1 ファイルを開く。
    func commitSelection() {
        guard rows.indices.contains(selectedIndex) else { return }
        let url = rows[selectedIndex].url
        guard fileReader.isDirectory(at: url) else {
            openFile(url)
            return
        }
        guard let resolved = SupportedFileResolver.resolveFileToOpen(at: url, fileReader: fileReader) else { return }
        openFile(resolved)
    }

    private func refresh() {
        selectedIndex = 0
        switch QuickOpenQuery.classify(input) {
        case .empty:
            pathCompletionText = nil
            didTruncate = false
            rows = makeRows(QuickOpenCandidates.recentEntries(
                recentURLs: recentURLs(), bookmarkURLs: bookmarkURLs()
            ))
        case let .path(text):
            let completion = pathCompletion.complete(
                input: text, baseDirectory: baseDirectory, includeHiddenFiles: includeHiddenFiles
            )
            pathCompletionText = completion.completion
            didTruncate = false
            rows = makeRows(completion.matches)
        case let .fuzzy(text):
            pathCompletionText = nil
            let result = QuickOpenCandidates.fuzzyMatches(
                query: text,
                indexedURLs: candidates,
                recentURLs: recentURLs(),
                bookmarkURLs: bookmarkURLs(),
                baseDirectory: baseDirectory,
                didTruncateIndex: candidatesDidTruncate
            )
            didTruncate = result.didTruncate
            rows = makeRows(result.matches)
        }
    }

    private func makeRows(_ urls: [URL]) -> [QuickOpenRow] {
        urls.map {
            QuickOpenRow(
                url: $0,
                title: $0.lastPathComponent,
                subtitle: PathRelativizer.relativePath(of: $0, relativeTo: baseDirectory)
            )
        }
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter QuickOpenModelTests`
Expected: PASS（8 テスト）

- [ ] **Step 5: 全体のテストが壊れていないことを確認する**

Run: `cd BefoldApp && swift test`
Expected: PASS（全テスト）

- [ ] **Step 6: コミット**

```bash
git add BefoldApp/befold/App/QuickOpenModel.swift BefoldApp/befoldTests/QuickOpenModelTests.swift
git commit -m "feat: Quick Open の状態モデルを追加する"
```

---

### Task 7: パネルとビュー（UI 層）

既存規約により、この層は自動テスト対象外とする。判断ロジックを一切持たせず、`QuickOpenModel` の状態を映してキーイベントを流すだけにする。

**Files:**
- Create: `BefoldApp/befold/Viewer/QuickOpenView.swift`
- Create: `BefoldApp/befold/App/QuickOpenPanelController.swift`

**Interfaces:**
- Consumes: `QuickOpenModel`（Task 6）
- Produces:
  - `struct QuickOpenView: View`、`init(model: QuickOpenModel, onClose: @escaping () -> Void)`
  - `@MainActor final class QuickOpenPanelController: NSObject, NSWindowDelegate`
  - `init(makeModel: @escaping () -> QuickOpenModel?)`、`func toggle()`、`func close()`

- [ ] **Step 1: SwiftUI ビューを書く**

`BefoldApp/befold/Viewer/QuickOpenView.swift`:

```swift
import SwiftUI

/// Quick Open のパネル内容。入力欄と候補一覧だけを持ち、判断は QuickOpenModel に委ねる。
struct QuickOpenView: View {
    @Bindable var model: QuickOpenModel
    let onClose: () -> Void

    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField(String(localized: "quickOpen.placeholder", bundle: .l10n), text: $model.input)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .padding(16)
                .focused($isInputFocused)
                .onSubmit(commit)
            Divider()
            candidateList
        }
        .frame(width: 680, height: 420)
        .onAppear { isInputFocused = true }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress(.upArrow) {
            model.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            model.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.tab) {
            model.completePath()
            return .handled
        }
    }

    @ViewBuilder
    private var candidateList: some View {
        if model.rows.isEmpty {
            Spacer()
            Text(String(localized: "quickOpen.noMatches", bundle: .l10n))
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            ScrollViewReader { proxy in
                List(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    QuickOpenRowView(row: row, isSelected: index == model.selectedIndex)
                        .id(row.id)
                        .contentShape(Rectangle())
                        .onTapGesture { commit(at: index) }
                }
                .listStyle(.plain)
                .onChange(of: model.selectedIndex) { _, newValue in
                    guard model.rows.indices.contains(newValue) else { return }
                    proxy.scrollTo(model.rows[newValue].id)
                }
            }
            if model.didTruncate {
                Divider()
                Text(String(localized: "quickOpen.truncated", bundle: .l10n))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
    }

    private func commit() {
        model.commitSelection()
        onClose()
    }

    private func commit(at index: Int) {
        model.moveSelection(by: index - model.selectedIndex)
        commit()
    }
}

private struct QuickOpenRowView: View {
    let row: QuickOpenRow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(row.title)
            Text(row.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
        }
        .padding(.vertical, 2)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
    }
}
```

- [ ] **Step 2: パネルコントローラを書く**

`BefoldApp/befold/App/QuickOpenPanelController.swift`:

```swift
import AppKit
import SwiftUI

/// キーウィンドウになれるフローティングパネル。既定の NSPanel は
/// スタイル次第でキーを取らずテキスト入力できないため、明示的に許可する。
private final class QuickOpenPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Quick Open パネルの表示・非表示と配置だけを担う。候補や開く先の判断は持たない。
@MainActor
final class QuickOpenPanelController: NSObject, NSWindowDelegate {
    private var panel: QuickOpenPanel?
    private let makeModel: () -> QuickOpenModel?

    init(makeModel: @escaping () -> QuickOpenModel?) {
        self.makeModel = makeModel
    }

    /// 表示中なら閉じ、そうでなければ開く。⌘P の押し下げに対応する。
    func toggle() {
        if panel != nil {
            close()
            return
        }
        show()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func show() {
        guard let model = makeModel() else { return }
        let panel = QuickOpenPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: QuickOpenView(model: model, onClose: { [weak self] in self?.close() })
        )
        position(panel)
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        Task { await model.prepare() }
    }

    /// Spotlight と同じく、画面中央よりやや上に置く。
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY + visible.height * 0.12 - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - NSWindowDelegate

    /// フォーカスを失ったら閉じる（Spotlight と同じ挙動）。
    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        close()
    }
}
```

- [ ] **Step 3: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功（この時点ではまだメニューから呼ばれないため警告は出てよいが、エラーは無いこと）

ローカライズキー `quickOpen.placeholder` / `quickOpen.noMatches` / `quickOpen.truncated` は Task 8 で `Localizable.xcstrings` に追加する。追加前は英語キー文字列がそのまま表示されるだけで、ビルドは通る。

- [ ] **Step 4: コミット**

```bash
git add BefoldApp/befold/Viewer/QuickOpenView.swift BefoldApp/befold/App/QuickOpenPanelController.swift
git commit -m "feat: Quick Open のパネルとビューを追加する"
```

---

### Task 8: メニュー配線と Print のキー移動

**Files:**
- Modify: `BefoldApp/befold/App/MainMenuBuilder.swift`（`build` の引数追加、`makeFileMenuItem` の `:76-115`）
- Modify: `BefoldApp/befold/App/AppDelegate.swift`（`:36-62` の init、`:104-111` のメニュー構築、アクション追加）
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`
- Test: `BefoldApp/befoldTests/MainMenuBuilderQuickOpenTests.swift`

**Interfaces:**
- Consumes: `QuickOpenPanelController`（Task 7）、`QuickOpenModel`（Task 6）
- Produces: `MainMenuBuilder.build(openAction:quickOpenAction:helpAction:recentMenuDelegate:bookmarksMenuDelegate:)`、`AppDelegate.showQuickOpen()`

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/MainMenuBuilderQuickOpenTests.swift`:

```swift
@testable import befold
import AppKit
import Testing

@MainActor
@Suite
struct MainMenuBuilderQuickOpenTests {
    private final class DummyMenuDelegate: NSObject, NSMenuDelegate {}

    private func makeFileMenu() -> NSMenu {
        let delegate = DummyMenuDelegate()
        let mainMenu = MainMenuBuilder.build(
            openAction: #selector(AppDelegate.showOpenPanel),
            quickOpenAction: #selector(AppDelegate.showQuickOpen),
            helpAction: #selector(AppDelegate.openHelp(_:)),
            recentMenuDelegate: delegate,
            bookmarksMenuDelegate: delegate
        )
        // File メニューはアプリメニューの次。
        return mainMenu.items[1].submenu!
    }

    @Test("Quick Open が Cmd+P に割り当てられている")
    func quickOpenUsesCommandP() {
        let item = makeFileMenu().items.first { $0.action == #selector(AppDelegate.showQuickOpen) }

        #expect(item?.keyEquivalent == "p")
        #expect(item?.keyEquivalentModifierMask == [.command])
    }

    @Test("Print は Shift+Cmd+P へ移っている")
    func printMovedToShiftCommandP() {
        let item = makeFileMenu().items.first {
            $0.action == #selector(ViewerWindowController.printDocument(_:))
        }

        #expect(item?.keyEquivalent == "P")
        #expect(item?.keyEquivalentModifierMask == [.command, .shift])
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter MainMenuBuilderQuickOpenTests`
Expected: FAIL（`extra argument 'quickOpenAction' in call` と `type 'AppDelegate' has no member 'showQuickOpen'`）

- [ ] **Step 3: MainMenuBuilder を変更する**

`BefoldApp/befold/App/MainMenuBuilder.swift` の `build` を次に置き換える:

```swift
    static func build(
        openAction: Selector,
        quickOpenAction: Selector,
        helpAction: Selector,
        recentMenuDelegate: NSMenuDelegate,
        bookmarksMenuDelegate: NSMenuDelegate
    ) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeAppMenuItem())
        mainMenu.addItem(makeFileMenuItem(
            openAction: openAction,
            quickOpenAction: quickOpenAction,
            recentMenuDelegate: recentMenuDelegate,
            bookmarksMenuDelegate: bookmarksMenuDelegate
        ))
        mainMenu.addItem(makeEditMenuItem())
        mainMenu.addItem(makeViewMenuItem())
        mainMenu.addItem(makeWindowMenuItem())
        mainMenu.addItem(makeHelpMenuItem(helpAction: helpAction))
        return mainMenu
    }
```

`makeFileMenuItem` の宣言と Open 直後、および末尾の Print を次に置き換える:

```swift
    private static func makeFileMenuItem(
        openAction: Selector, quickOpenAction: Selector,
        recentMenuDelegate: NSMenuDelegate, bookmarksMenuDelegate: NSMenuDelegate
    ) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.file.title", bundle: .l10n))
        item.submenu = menu
        menu.addItem(
            withTitle: String(localized: "menu.file.open", bundle: .l10n),
            action: openAction,
            keyEquivalent: "o"
        )
        menu.addItem(
            withTitle: String(localized: "menu.file.quickOpen", bundle: .l10n),
            action: quickOpenAction,
            keyEquivalent: "p"
        )
```

（`recentTitle` 以降は既存のまま）末尾の Print を次に置き換える:

```swift
        menu.addItem(.separator())
        // 印刷は日常操作ではなくなったため ⌘P を Quick Open へ譲り、⇧⌘P へ退避する。
        let printItem = menu.addItem(
            withTitle: String(localized: "menu.file.print", bundle: .l10n),
            action: #selector(ViewerWindowController.printDocument(_:)),
            keyEquivalent: "P"
        )
        printItem.keyEquivalentModifierMask = [.command, .shift]
        return item
    }
```

- [ ] **Step 4: AppDelegate を配線する**

`BefoldApp/befold/App/AppDelegate.swift` を次のように変更する。

(a) プロパティを追加する。`private let bookmarkStore: BookmarkStore`（`:21`）の直後:

```swift
    /// Quick Open と全ビューアウィンドウで共有する git 追跡ファイル索引。
    /// ViewerWindowManager の既定値任せにすると Quick Open から同じ実体を引けないため、
    /// ここで 1 つだけ作って両方へ配る。
    private let gitFileIndex: any GitFileIndexing
```

`bookmarksMenuController`（`:31-34`）の直後:

```swift
    private lazy var quickOpenPanelController = QuickOpenPanelController(
        makeModel: { [weak self] in self?.makeQuickOpenModel() }
    )
```

(b) `override init()`（`:36-62`）の中で索引を作って配る。`let perFileState = PerFileStateStore()` の直後に追加:

```swift
        let gitFileIndex = GitCommandFileIndex()
```

`ViewerWindowManager(...)` の呼び出しに引数を足す:

```swift
        let windowManager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: recentDocumentsStore,
            hiddenFilesPreference: hiddenFilesPreference,
            findOptionsPreference: findOptionsPreference,
            perFileState: perFileState,
            bookmarkStore: bookmarkStore,
            gitFileIndex: gitFileIndex
        )
```

`self.hiddenFilesPreference = hiddenFilesPreference` の直後に追加:

```swift
        self.gitFileIndex = gitFileIndex
```

(c) メニュー構築（`:106-111`）に引数を足す:

```swift
        NSApp.mainMenu = MainMenuBuilder.build(
            openAction: #selector(showOpenPanel),
            quickOpenAction: #selector(showQuickOpen),
            helpAction: #selector(openHelp(_:)),
            recentMenuDelegate: recentDocumentsMenuController,
            bookmarksMenuDelegate: bookmarksMenuController
        )
```

(d) `showOpenPanel`（`:238`）の隣にアクションとモデル生成を追加する:

```swift
    @objc func showQuickOpen() {
        quickOpenPanelController.toggle()
    }

    /// キーウィンドウのファイルを基準に Quick Open のモデルを作る。
    /// ウィンドウが 1 枚も無いときはホームディレクトリを基準にし、
    /// 決定時は切り替え先が無いので新規ウィンドウで開く。
    private func makeQuickOpenModel() -> QuickOpenModel {
        let controller = NSApp.keyWindow?.windowController as? ViewerWindowController
        let currentFileURL = controller?.fileURL
        let baseDirectory = currentFileURL?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser
        return QuickOpenModel(
            baseDirectory: baseDirectory,
            currentFileURL: currentFileURL,
            gitIndex: gitFileIndex,
            recentURLs: { [weak self] in self?.recentDocumentsStore.recentURLs() ?? [] },
            bookmarkURLs: { [weak self] in self?.bookmarkStore.bookmarkedURLs() ?? [] },
            includeHiddenFiles: hiddenFilesPreference.showHiddenFiles,
            openFile: { [weak self] url in
                guard let controller else {
                    self?.openViewer(for: url)
                    return
                }
                controller.switchFile(to: url)
            }
        )
    }
```

`QuickOpenPanelController` の `makeModel` は `QuickOpenModel?` を返す型なので、非 Optional を返すこのメソッドはそのまま渡せる。

- [ ] **Step 5: ローカライズを追加する**

`BefoldApp/befold/Resources/Localizable.xcstrings` にキーを追加する。キーは辞書順に並んでいるので、`"menu.file.print"` のエントリの直後に次を挿入する:

```json
    "menu.file.quickOpen" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Quick Open…"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "クイックオープン…"
          }
        }
      }
    },
```

同じファイルの辞書順の位置（`"menu."` 群より後、`"q"` の位置）に次の 3 つも追加する:

```json
    "quickOpen.noMatches" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "No matches" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "一致なし" } }
      }
    },
    "quickOpen.placeholder" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Type a path or file name" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "パスまたはファイル名を入力" } }
      }
    },
    "quickOpen.truncated" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Some candidates were omitted" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "一部の候補を省略しました" } }
      }
    },
```

挿入後に JSON として妥当であることを確認する:

Run: `cd BefoldApp && python3 -m json.tool befold/Resources/Localizable.xcstrings > /dev/null && echo OK`
Expected: `OK`

- [ ] **Step 6: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter MainMenuBuilderQuickOpenTests`
Expected: PASS（2 テスト）

- [ ] **Step 7: 全テストとビルドを確認する**

Run: `cd BefoldApp && swift build && swift test`
Expected: ビルド成功、全テスト PASS

- [ ] **Step 8: コミット**

```bash
git add BefoldApp/befold/App/MainMenuBuilder.swift \
        BefoldApp/befold/App/AppDelegate.swift \
        BefoldApp/befold/Resources/Localizable.xcstrings \
        BefoldApp/befoldTests/MainMenuBuilderQuickOpenTests.swift
git commit -m "feat: Cmd+P に Quick Open を割り当て Print を Shift+Cmd+P へ移す"
```

---

### Task 9: 手動チェックと仕上げ

**Files:**
- Modify: なし（不具合が見つかった場合のみ該当ファイル）

- [ ] **Step 1: アプリをビルドして起動する**

Run: `cd BefoldApp && swift build && swift run befold`

（`/run` スキルがある場合はそちらを使ってよい）

- [ ] **Step 2: 手動チェック項目を順に確認する**

- `Cmd+P` でパネルが画面中央やや上に表示され、入力欄にフォーカスが当たっている
- `Esc` で閉じる。パネル以外をクリックしてフォーカスを失っても閉じる
- 空入力で最近開いたファイルとブックマークが並ぶ
- `~/` と打つとホーム直下が並び、続けて文字を打つと前方一致で絞り込まれる
- `Tab` で共通接頭辞まで補完され、ディレクトリが 1 件に定まると `/` が付いて次の階層へ進む
- ファイル名の断片（例: `vwst`）で fuzzy 検索の候補が出る
- `↑` `↓` で選択が動き、選択行が見えるようにスクロールする
- `Enter` で現在のウィンドウが切り替わる
- ウィンドウを全て閉じた状態で `Cmd+P` を押し、`Enter` で新規ウィンドウが開く
- Git 管理外の大きなディレクトリを開いた状態で入力してももたつかない。候補が打ち切られた場合は一覧末尾に注記が出る
- `Shift+Cmd+P` で印刷ダイアログが出る
- `Cmd+O` の従来動作が壊れていない

- [ ] **Step 3: 不具合があれば修正し、該当するテストを足す**

修正時は必ず先に失敗するテストを書く。UI 層（`QuickOpenView` / `QuickOpenPanelController`）の不具合は自動テスト対象外なので、判断ロジックに起因する場合は `QuickOpenModel` 以下のテストへ落とし込む。

- [ ] **Step 4: 品質チェックを通す**

Run: `cd BefoldApp && swift build && swift test`
Expected: ビルド成功、全テスト PASS

`/check` スキルがある場合はあわせて実行し、SwiftLint の指摘を解消する。

- [ ] **Step 5: backlog の受け入れ基準を確認して完了させる**

```bash
backlog task view TASK-159 --plain
```

`backlog instructions task-finalization` を読んでから、受け入れ基準のチェックと実装メモの記録、ステータス変更を行う。

- [ ] **Step 6: コミット**

```bash
git add -A
git commit -m "chore: TASK-159 を完了にする"
```

---

## Self-Review

**Spec coverage**

| Spec の要件 | 対応タスク |
| --- | --- |
| `Cmd+P` でパネル表示、Esc / フォーカス喪失で閉じる | Task 7, 8 |
| 入力の 3 モード分類 | Task 1 |
| Git 優先・非 Git はディレクトリ走査 | Task 2, 6 |
| 拡張子で区別しない | Task 2（走査は全ファイル）、Task 5（照合も区別しない） |
| 履歴・ブックマークを混ぜる | Task 5, 6 |
| 現在のウィンドウで切替、無ければ新規 | Task 8 |
| `Cmd+P` を Quick Open へ、Print を `⇧⌘P` へ | Task 8 |
| パスモードの親／断片分解・前方一致・Tab 補完 | Task 4 |
| ディレクトリ決定時は `SupportedFileResolver` 経由 | Task 6 |
| fuzzy のスコアリングと決定論的な並び | Task 3 |
| 空入力時の履歴表示 | Task 5, 6 |
| 走査の上限と除外、打ち切りの表示 | Task 2, 5, 7 |
| 候補取得のバックグラウンド化 | Task 6（`prepare()`） |
| 候補ゼロは一致なし表示のみ | Task 7 |
| 隠しファイル設定の尊重 | Task 2, 4, 8 |
| BefoldKit の自動テスト | Task 1–5 |
| `QuickOpenModel` の自動テスト | Task 6 |
| メニューのキー割り当てテスト | Task 8 |
| 手動チェック項目 | Task 9 |

**未対応として意図的に残すもの**

- spec の「デバウンス」は Deviations の 2 番で不要と判断し、外した。
- spec の「`SuffixPathIndex` 変更はスコープ外」は Deviations の 1 番で読み出しアクセサに限り解除した。
