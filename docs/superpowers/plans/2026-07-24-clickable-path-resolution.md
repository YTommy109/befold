# クリック可能なパス解決（表示時解決）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ドキュメント中のファイルパス参照を表示時に解決し、実在するもの（相対・絶対・git 追跡ファイルへのサフィックス一致）だけをクリック可能なリンクとして表示する。

**Architecture:** 純ロジック（サフィックス一致・近さランキング・パス分類）を BefoldKit に置き、副作用（git 実行）を app 層に分離する。git 実行は再利用可能なシーム（`GitCommandRunner` = Process ラッパ、`GitRepository` = ルート検出/追跡ファイル列挙/index fingerprint）に切り出し、`GitCommandFileIndex` がその最初の利用者としてルート単位でキャッシュする。キャッシュ無効化は `.git/index` の更新日時（subprocess 不要のファイル stat・worktree の `.git` ファイルにも対応）で行い、外部のブランチ/ワークツリー切替・commit を自動追従する。JS は描画後に候補パスを収集して `resolveReferences` ブリッジで Swift に送り、Swift が同一の `TrackedPathResolver` で解決した結果（書かれたパス→解決済み絶対パス）を返し、JS が解決済みのものだけをリンク化する。同じ `TrackedPathResolver` をクリック時の `handleOpenReference` でも使い、解決の単一情報源とする。`GitRepository` はブランチ/ワークツリー切替・差分表示など将来の git 機能の拡張点として設計する（本計画ではスコープ外）。

**Tech Stack:** Swift 6（strict concurrency）/ Swift Testing / AppKit + WKWeb
View / バニラ JS（viewer-main.js）/ Foundation.Process（git 実行）

## Global Constraints

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）。新規型は `Sendable` 準拠、副作用を持つ参照型は `@unchecked Sendable` + ロックで安全性を担保する。
- テスト関数名は英語 camelCase（SwiftLint `identifier_name` が非 ASCII 開始名を弾く）。日本語説明は `@Test("...")` 表示名で付ける。
- 純ロジックは BefoldKit（依存は Foundation のみ）、Process 等の副作用は app（befold）ターゲットへ置く。
- ブリッジ文字列を変更する箇所は viewer-main.js と ViewerBridge.swift の両方を揃える（`ViewerBridgeTests` がソース整合を検証する）。
- コミットは Conventional Commits + 日本語。
- ビルド/テストは `cd BefoldApp && swift build` / `swift test`（要 Xcode.app）。

---

### Task 1: SuffixPathMatcher（構成要素単位サフィックス一致＋近さランキング）

書かれたパスを候補ファイル群に構成要素単位のサフィックスとして照合し、開いているファイルからのツリー距離が最小の 1 件を決定論的に選ぶ純ロジック。

**Files:**
- Create: `BefoldApp/BefoldKit/SuffixPathMatcher.swift`
- Test: `BefoldApp/befoldTests/SuffixPathMatcherTests.swift`

**Interfaces:**
- Consumes: なし（Foundation の URL のみ）
- Produces:
  - `public enum SuffixPathMatcher`
  - `public static func bestMatch(writtenPath: String, candidates: [URL], baseURL: URL) -> URL?`

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/SuffixPathMatcherTests.swift`:

```swift
import Foundation
import Testing
@testable import BefoldKit

struct SuffixPathMatcherTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test("構成要素単位のサフィックス一致で候補を絞る")
    func matchesOnComponentBoundary() {
        let candidates = [url("/repo/src/utils.swift"), url("/repo/src/myutils.swift")]
        let base = url("/repo/docs/guide.md")
        // "utils.swift" は myutils.swift の部分文字列だが構成要素境界では一致しない
        #expect(SuffixPathMatcher.bestMatch(writtenPath: "utils.swift", candidates: candidates, baseURL: base)
            == url("/repo/src/utils.swift"))
    }

    @Test("複数候補は開いているファイルに近いものを選ぶ")
    func picksClosestToBase() {
        let candidates = [url("/repo/packages/web/src/utils.swift"),
                          url("/repo/packages/api/src/utils.swift")]
        let base = url("/repo/packages/web/docs/guide.md")
        #expect(SuffixPathMatcher.bestMatch(writtenPath: "utils.swift", candidates: candidates, baseURL: base)
            == url("/repo/packages/web/src/utils.swift"))
    }

    @Test("多段のサフィックスはより長く一致する候補に絞られる")
    func matchesMultiComponentSuffix() {
        let candidates = [url("/repo/packages/web/src/foo/bar.ts"),
                          url("/repo/other/bar.ts")]
        let base = url("/repo/README.md")
        #expect(SuffixPathMatcher.bestMatch(writtenPath: "src/foo/bar.ts", candidates: candidates, baseURL: base)
            == url("/repo/packages/web/src/foo/bar.ts"))
    }

    @Test("先頭の ./ ../ / は無視して照合する")
    func ignoresLeadingDots() {
        let candidates = [url("/repo/src/a.swift")]
        let base = url("/repo/docs/guide.md")
        #expect(SuffixPathMatcher.bestMatch(writtenPath: "../src/a.swift", candidates: candidates, baseURL: base)
            == url("/repo/src/a.swift"))
    }

    @Test("該当なしは nil")
    func noMatchReturnsNil() {
        #expect(SuffixPathMatcher.bestMatch(writtenPath: "nope.swift",
                                            candidates: [url("/repo/a.swift")],
                                            baseURL: url("/repo/x.md")) == nil)
    }

    @Test("距離同点は up 段数最小→path 昇順で決定論的に確定する")
    func deterministicTieBreak() {
        let candidates = [url("/repo/b/x.swift"), url("/repo/a/x.swift")]
        let base = url("/repo/base/guide.md") // 両候補とも距離2・up1で同点
        #expect(SuffixPathMatcher.bestMatch(writtenPath: "x.swift", candidates: candidates, baseURL: base)
            == url("/repo/a/x.swift"))
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd BefoldApp && swift test --filter SuffixPathMatcherTests`
Expected: FAIL（`SuffixPathMatcher` が未定義でコンパイルエラー）

- [ ] **Step 3: 最小実装を書く**

`BefoldApp/BefoldKit/SuffixPathMatcher.swift`:

```swift
import Foundation

/// 書かれたパスを候補ファイル群へ「/ 区切りの構成要素単位」でサフィックス照合し、
/// 開いているファイル(baseURL)からのディレクトリツリー距離が最小の 1 件を返す。
/// 曖昧さは 距離最小 → up 段数最小 → path 昇順 のタイブレークで決定論的に解消する。
public enum SuffixPathMatcher {
    public static func bestMatch(writtenPath: String, candidates: [URL], baseURL: URL) -> URL? {
        let needle = meaningfulComponents(writtenPath)
        guard !needle.isEmpty else { return nil }
        let baseDir = components(of: baseURL.deletingLastPathComponent())

        let matches = candidates.filter { hasComponentSuffix(components(of: $0), needle) }
        guard !matches.isEmpty else { return nil }

        return matches.min { lhs, rhs in
            let a = distance(baseDir, components(of: lhs.deletingLastPathComponent()))
            let b = distance(baseDir, components(of: rhs.deletingLastPathComponent()))
            if a.total != b.total { return a.total < b.total }
            if a.up != b.up { return a.up < b.up }
            return lhs.standardizedFileURL.path < rhs.standardizedFileURL.path
        }
    }

    /// "/", ".", "..", 空要素を除いたパス構成要素。
    static func meaningfulComponents(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init).filter { $0 != "." && $0 != ".." && !$0.isEmpty }
    }

    /// ルート "/" を除いた URL の構成要素。
    static func components(of url: URL) -> [String] {
        url.standardizedFileURL.pathComponents.filter { $0 != "/" }
    }

    /// haystack の末尾 needle.count 個が needle と一致するか。
    static func hasComponentSuffix(_ haystack: [String], _ needle: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        return Array(haystack.suffix(needle.count)) == needle
    }

    /// 共通接頭辞を除いた (合計距離, 上がる段数)。
    static func distance(_ a: [String], _ b: [String]) -> (total: Int, up: Int) {
        var i = 0
        while i < a.count, i < b.count, a[i] == b[i] { i += 1 }
        let up = a.count - i
        let down = b.count - i
        return (up + down, up)
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd BefoldApp && swift test --filter SuffixPathMatcherTests`
Expected: PASS（6 テスト）

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/BefoldKit/SuffixPathMatcher.swift BefoldApp/befoldTests/SuffixPathMatcherTests.swift
git commit -m "feat: パスのサフィックス一致と近さランキングを追加する"
```

---

### Task 2: ReferenceResolver 拡張 + TrackedPathResolver（解決の単一情報源）

`ReferenceResolver` に「ローカルパス文字列だけを取り出す」公開ヘルパーを足し、`TrackedPathResolver` が「相対で実在 → git 追跡ファイルへのサフィックス一致」の順で解決する。git 実行はプロトコル `GitFileIndexing` で注入する。

**Files:**
- Modify: `BefoldApp/BefoldKit/ReferenceResolver.swift`（全面差し替え。既存 `resolve` の挙動は不変）
- Create: `BefoldApp/BefoldKit/TrackedPathResolver.swift`
- Test: `BefoldApp/befoldTests/TrackedPathResolverTests.swift`
- 既存回帰: `BefoldApp/befoldTests/ReferenceResolverTests.swift`（変更なし・緑のままを確認）

**Interfaces:**
- Consumes: `SuffixPathMatcher.bestMatch(writtenPath:candidates:baseURL:)`（Task 1）、`FileReading`（既存）
- Produces:
  - `ReferenceResolver.localPathString(from href: String) -> String?`（ローカルパスなら整形済み相対/絶対文字列、外部/未対応/アンカーは nil）
  - `public protocol GitFileIndexing: Sendable { func trackedFiles(forFileAt url: URL) -> [URL]? }`
  - `public enum ResolvedReference: Equatable, Sendable { case external(URL); case resolved(URL); case unresolved; case ignored }`
  - `public struct TrackedPathResolver: Sendable`
    - `init(fileReader: FileReading = DefaultFileReader(), gitIndex: GitFileIndexing)`
    - `func resolve(href: String, baseURL: URL) -> ResolvedReference`

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/TrackedPathResolverTests.swift`:

```swift
import Foundation
import Testing
@testable import BefoldKit

private struct FakeGitIndex: GitFileIndexing {
    let files: [URL]?
    func trackedFiles(forFileAt url: URL) -> [URL]? { files }
}

private struct FakeFileReader: FileReading {
    let existing: Set<String>
    func fileExists(at url: URL) -> Bool { existing.contains(url.standardizedFileURL.path) }
    func isDirectory(at url: URL) -> Bool { false }
    func isExistingFile(at url: URL) -> Bool { existing.contains(url.standardizedFileURL.path) }
    func readString(from url: URL) throws -> String { "" }
    func readData(from url: URL) throws -> Data { Data() }
    func isBinary(at url: URL) -> Bool { false }
    func fileSize(at url: URL) -> Int? { nil }
    func modificationDate(at url: URL) -> Date? { nil }
}

struct TrackedPathResolverTests {
    private func url(_ p: String) -> URL { URL(fileURLWithPath: p) }

    @Test("相対で実在すればそのまま解決する(git を見ない)")
    func resolvesExistingRelative() {
        let base = url("/repo/docs/guide.md")
        let target = url("/repo/docs/img.png")
        let sut = TrackedPathResolver(
            fileReader: FakeFileReader(existing: [target.path]),
            gitIndex: FakeGitIndex(files: nil))
        #expect(sut.resolve(href: "img.png", baseURL: base) == .resolved(target))
    }

    @Test("相対で実在しなければ git 追跡ファイルへサフィックス一致で解決する")
    func resolvesViaGitSuffix() {
        let base = url("/repo/docs/guide.md")
        let tracked = url("/repo/src/utils.swift")
        let sut = TrackedPathResolver(
            fileReader: FakeFileReader(existing: []),
            gitIndex: FakeGitIndex(files: [tracked]))
        #expect(sut.resolve(href: "utils.swift", baseURL: base) == .resolved(tracked))
    }

    @Test("git 管理外かつ相対で実在しなければ unresolved")
    func unresolvedWithoutGit() {
        let sut = TrackedPathResolver(
            fileReader: FakeFileReader(existing: []),
            gitIndex: FakeGitIndex(files: nil))
        #expect(sut.resolve(href: "utils.swift", baseURL: url("/repo/x.md")) == .unresolved)
    }

    @Test("外部 URL は external、アンカー/空は ignored")
    func classifiesExternalAndIgnored() {
        let sut = TrackedPathResolver(fileReader: FakeFileReader(existing: []),
                                      gitIndex: FakeGitIndex(files: nil))
        let base = url("/repo/x.md")
        #expect(sut.resolve(href: "https://example.com", baseURL: base)
            == .external(URL(string: "https://example.com")!))
        #expect(sut.resolve(href: "#section", baseURL: base) == .ignored)
    }

    @Test("行番号サフィックス付きでも解決できる")
    func resolvesWithLineSuffix() {
        let base = url("/repo/docs/guide.md")
        let tracked = url("/repo/src/utils.swift")
        let sut = TrackedPathResolver(
            fileReader: FakeFileReader(existing: []),
            gitIndex: FakeGitIndex(files: [tracked]))
        #expect(sut.resolve(href: "utils.swift:42", baseURL: base) == .resolved(tracked))
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd BefoldApp && swift test --filter TrackedPathResolverTests`
Expected: FAIL（`GitFileIndexing` / `TrackedPathResolver` / `localPathString` が未定義）

- [ ] **Step 3: ReferenceResolver に localPathString を足す（resolve の挙動は不変）**

`BefoldApp/BefoldKit/ReferenceResolver.swift` を全面差し替え:

```swift
import Foundation

public enum ReferenceTarget: Equatable, Sendable {
    case external(URL)
    case localFile(URL)
    case unsupported
}

public enum ReferenceResolver {
    public static func resolve(href: String, baseURL: URL) -> ReferenceTarget {
        switch classify(href: href) {
        case .external(let url):
            return .external(url)
        case .unsupported:
            return .unsupported
        case .local(let pathString):
            if pathString.hasPrefix("/") {
                return .localFile(URL(fileURLWithPath: pathString).standardized)
            }
            let baseDir = baseURL.deletingLastPathComponent()
            return .localFile(baseDir.appendingPathComponent(pathString).standardized)
        }
    }

    /// ローカルパスとして解釈できる href のみ、整形済み(fragment・行番号サフィックス除去、
    /// パーセントデコード済み)のパス文字列を返す。外部 URL・未対応スキーム・アンカーは nil。
    public static func localPathString(from href: String) -> String? {
        if case let .local(pathString) = classify(href: href) { return pathString }
        return nil
    }

    // MARK: - 内部分類

    private enum Classified {
        case external(URL)
        case local(String)
        case unsupported
    }

    private static func classify(href: String) -> Classified {
        guard !href.isEmpty, !href.hasPrefix("#") else { return .unsupported }
        let decoded = href.removingPercentEncoding ?? href

        if let url = URL(string: href), let scheme = url.scheme {
            switch scheme.lowercased() {
            case "http", "https":
                return .external(url)
            default:
                // URL(string: "notes.md:12") は scheme="notes.md" と解釈される。
                // ドットを含む scheme はファイル名の誤認とみなしローカルパスへ回す。
                if !scheme.contains(".") { return .unsupported }
            }
        }

        // #fragment を除去（クロスドキュメントリンク other.md#section 対応）
        let withoutFragment: String = if let hashIndex = decoded.firstIndex(of: "#") {
            String(decoded[..<hashIndex])
        } else {
            decoded
        }

        // 行番号・行列サフィックス (:数字) を繰り返し除去
        let pathString: String = if let colonRange = withoutFragment.range(
            of: #"(?::\d+)+$"#, options: .regularExpression
        ) {
            String(withoutFragment[..<colonRange.lowerBound])
        } else {
            withoutFragment
        }

        guard !pathString.isEmpty else { return .unsupported }
        return .local(pathString)
    }
}
```

- [ ] **Step 4: TrackedPathResolver を書く**

`BefoldApp/BefoldKit/TrackedPathResolver.swift`:

```swift
import Foundation

/// url を含む git リポジトリの追跡ファイル絶対 URL 一覧を返す。git 管理外なら nil。
public protocol GitFileIndexing: Sendable {
    func trackedFiles(forFileAt url: URL) -> [URL]?
}

/// パス参照の解決結果。
public enum ResolvedReference: Equatable, Sendable {
    case external(URL)   // http/https。リンク維持(ブラウザで開く)
    case resolved(URL)   // 実在を確認できたローカルファイル
    case unresolved      // ローカルパスだが解決できなかった(リンクにしない)
    case ignored         // 空 / #anchor / 未対応スキーム(据え置き)
}

/// 「相対/絶対で実在 → git 追跡ファイルへの構成要素サフィックス一致(近さ最小)」の順で
/// パス参照を解決する。表示時(リンク化判定)とクリック時(オープン)の両方から使う単一情報源。
public struct TrackedPathResolver: Sendable {
    private let fileReader: FileReading
    private let gitIndex: GitFileIndexing

    public init(fileReader: FileReading = DefaultFileReader(), gitIndex: GitFileIndexing) {
        self.fileReader = fileReader
        self.gitIndex = gitIndex
    }

    public func resolve(href: String, baseURL: URL) -> ResolvedReference {
        switch ReferenceResolver.resolve(href: href, baseURL: baseURL) {
        case let .external(url):
            return .external(url)
        case .unsupported:
            return .ignored
        case let .localFile(url):
            if fileReader.isExistingFile(at: url) {
                return .resolved(url)
            }
            guard let written = ReferenceResolver.localPathString(from: href),
                  let candidates = gitIndex.trackedFiles(forFileAt: baseURL),
                  let match = SuffixPathMatcher.bestMatch(
                      writtenPath: written, candidates: candidates, baseURL: baseURL)
            else { return .unresolved }
            return .resolved(match)
        }
    }
}
```

- [ ] **Step 5: テストが通ることを確認（既存回帰も含む）**

Run: `cd BefoldApp && swift test --filter TrackedPathResolverTests`
Expected: PASS（5 テスト）
Run: `cd BefoldApp && swift test --filter ReferenceResolverTests`
Expected: PASS（既存テスト緑のまま）

- [ ] **Step 6: コミット**

```bash
git add BefoldApp/BefoldKit/ReferenceResolver.swift BefoldApp/BefoldKit/TrackedPathResolver.swift BefoldApp/befoldTests/TrackedPathResolverTests.swift
git commit -m "feat: git 追跡ファイルへのフォールバックを含むパス解決を追加する"
```

---

### Task 3: GitCommandRunner + GitRepository（再利用可能な git シーム）

git を呼ぶ全機能の共通土台。`GitCommandRunner` は Process 実行を一元化し、`GitRepository` はルート検出・追跡ファイル列挙・index fingerprint（キャッシュ無効化シグネチャ）を提供する。副作用（Process）を持つため app（befold）ターゲットに置く。ブランチ/ワークツリー切替・差分表示など将来の git 機能はここを拡張点にする。

**Files:**
- Create: `BefoldApp/befold/App/GitCommandRunner.swift`
- Create: `BefoldApp/befold/App/GitRepository.swift`
- Test: `BefoldApp/befoldTests/GitRepositoryTests.swift`

**Interfaces:**
- Consumes: `FileReading`（既存）、`TempDir`（`BefoldTestSupport`、既存）
- Produces:
  - `struct GitCommandRunner: Sendable`
    - `func run(_ args: [String], in workingDirectory: URL?) -> Data?`
    - `func runString(_ args: [String], in workingDirectory: URL?) -> String?`
  - `protocol GitRepositoryReading: Sendable`
    - `func root(forFileAt url: URL) -> URL?`
    - `func trackedFiles(at root: URL) -> [URL]`
    - `func indexFingerprint(at root: URL) -> Date?`
  - `struct GitRepository: GitRepositoryReading`
    - `init(runner: GitCommandRunner = GitCommandRunner(), fileReader: FileReading = DefaultFileReader())`

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/GitRepositoryTests.swift`:

```swift
import Foundation
import Testing
import BefoldTestSupport
@testable import befold

struct GitRepositoryTests {
    private func git(_ dir: URL, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", dir.path] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    private func makeRepo(_ dir: URL) throws {
        git(dir, ["init"])
        git(dir, ["config", "user.email", "t@example.com"])
        git(dir, ["config", "user.name", "t"])
        try "print(1)".write(to: dir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        git(dir, ["add", "main.swift"])
        git(dir, ["commit", "-m", "init"])
    }

    @Test("root と追跡ファイルを取得する")
    func rootAndTrackedFiles() throws {
        let temp = TempDir()
        try makeRepo(temp.url)
        let repo = GitRepository()
        let root = repo.root(forFileAt: temp.url.appendingPathComponent("main.swift"))
        #expect(root?.standardizedFileURL == temp.url.standardizedFileURL)
        #expect(repo.trackedFiles(at: root!).map { $0.lastPathComponent } == ["main.swift"])
    }

    @Test("git 管理外は root が nil")
    func noRootOutsideRepo() {
        let temp = TempDir()
        #expect(GitRepository().root(forFileAt: temp.url.appendingPathComponent("x.md")) == nil)
    }

    @Test("index の更新で fingerprint が変わる")
    func fingerprintChangesOnIndexUpdate() throws {
        let temp = TempDir()
        try makeRepo(temp.url)
        let repo = GitRepository()
        let before = repo.indexFingerprint(at: temp.url)
        #expect(before != nil)
        try "x".write(to: temp.url.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        git(temp.url, ["add", "b.txt"])
        let after = repo.indexFingerprint(at: temp.url)
        #expect(after != before)
    }

    @Test("worktree 形式の .git ファイルは gitdir を辿って index を見る")
    func resolvesWorktreeGitFile() throws {
        let gitdir = TempDir() // 実 gitdir 相当
        let indexURL = gitdir.url.appendingPathComponent("index")
        try "".write(to: indexURL, atomically: true, encoding: .utf8)
        let work = TempDir()
        try "gitdir: \(gitdir.url.path)\n".write(
            to: work.url.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        let fp = GitRepository().indexFingerprint(at: work.url)
        let expected = try FileManager.default.attributesOfItem(atPath: indexURL.path)[.modificationDate] as? Date
        #expect(fp != nil)
        #expect(fp == expected)
    }
}
```

（`TempDir` の API はプロジェクトの既存テスト（例: `FileWatcherTests`）に合わせること。`TempDir()` 生成 + `.url` プロパティが無い場合は既存ヘルパーのシグネチャに読み替える。）

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd BefoldApp && swift test --filter GitRepositoryTests`
Expected: FAIL（`GitCommandRunner` / `GitRepository` が未定義）

- [ ] **Step 3: GitCommandRunner を書く**

`BefoldApp/befold/App/GitCommandRunner.swift`:

```swift
import Foundation

/// git コマンド実行を一元化する薄い Process ラッパ。
/// git 未インストール・実行失敗・非 0 終了はすべて nil に倒す。
/// git を呼ぶ全機能(パス解決・将来のブランチ/差分)の共通土台。
struct GitCommandRunner: Sendable {
    func run(_ args: [String], in workingDirectory: URL? = nil) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    func runString(_ args: [String], in workingDirectory: URL? = nil) -> String? {
        guard let data = run(args, in: workingDirectory) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

- [ ] **Step 4: GitRepository を書く**

`BefoldApp/befold/App/GitRepository.swift`:

```swift
import BefoldKit
import Foundation

/// git リポジトリの検出・identity・追跡ファイル列挙を提供する読み取りシーム。
/// 差し替え可能にしてキャッシュ層(GitCommandFileIndex)を純粋にテストできるようにする。
protocol GitRepositoryReading: Sendable {
    /// url を含む作業ツリールート。git 管理外なら nil。
    func root(forFileAt url: URL) -> URL?
    /// root 配下の追跡ファイル絶対 URL 一覧(作業ツリー)。
    func trackedFiles(at root: URL) -> [URL]
    /// 追跡集合が変わると変化する軽量シグネチャ(.git/index の最終更新日時)。
    func indexFingerprint(at root: URL) -> Date?
}

/// git コマンド + ファイル stat による GitRepositoryReading 実装。
/// ブランチ/ワークツリー切替・差分など将来の git 機能の拡張点。
struct GitRepository: GitRepositoryReading {
    private let runner: GitCommandRunner
    private let fileReader: FileReading

    init(runner: GitCommandRunner = GitCommandRunner(), fileReader: FileReading = DefaultFileReader()) {
        self.runner = runner
        self.fileReader = fileReader
    }

    func root(forFileAt url: URL) -> URL? {
        let dir = url.deletingLastPathComponent()
        guard let out = runner.runString(["rev-parse", "--show-toplevel"], in: dir),
              let first = out.split(separator: "\n").first
        else { return nil }
        return URL(fileURLWithPath: String(first), isDirectory: true).standardizedFileURL
    }

    func trackedFiles(at root: URL) -> [URL] {
        guard let data = runner.run(["ls-files", "-z"], in: root) else { return [] }
        return data.split(separator: 0).compactMap { slice in
            guard let rel = String(data: Data(slice), encoding: .utf8), !rel.isEmpty else { return nil }
            return root.appendingPathComponent(rel).standardizedFileURL
        }
    }

    /// add/rm/checkout/commit で `.git/index` が更新されるため、その最終更新日時を
    /// キャッシュ無効化シグネチャに使う。外部のブランチ/ワークツリー切替を subprocess
    /// なしのファイル stat だけで検知できる。
    func indexFingerprint(at root: URL) -> Date? {
        fileReader.modificationDate(at: gitDirectory(at: root).appendingPathComponent("index"))
    }

    /// root/.git がディレクトリならそれ、ファイル(worktree/submodule)なら
    /// `gitdir: <path>` を解決した実 gitdir を返す。
    private func gitDirectory(at root: URL) -> URL {
        let dotGit = root.appendingPathComponent(".git")
        if fileReader.isDirectory(at: dotGit) { return dotGit }
        guard fileReader.isExistingFile(at: dotGit),
              let content = try? fileReader.readString(from: dotGit)
        else { return dotGit }
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("gitdir:") else { continue }
            let path = String(trimmed.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespaces)
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            }
            return root.appendingPathComponent(path).standardizedFileURL
        }
        return dotGit
    }
}
```

- [ ] **Step 5: テストが通ることを確認**

Run: `cd BefoldApp && swift test --filter GitRepositoryTests`
Expected: PASS（4 テスト）

- [ ] **Step 6: コミット**

```bash
git add BefoldApp/befold/App/GitCommandRunner.swift BefoldApp/befold/App/GitRepository.swift BefoldApp/befoldTests/GitRepositoryTests.swift
git commit -m "feat: 再利用可能な git コマンド実行とリポジトリ検出を追加する"
```

---

### Task 4: GitCommandFileIndex（fingerprint によるキャッシュ無効化）

`GitFileIndexing` の実装。`GitRepository` を使ってルート単位で追跡ファイルをキャッシュし、`.git/index` の fingerprint が変われば再取得する。`GitRepositoryReading` を注入してキャッシュ/無効化を純粋にテストする。

**Files:**
- Create: `BefoldApp/befold/App/GitCommandFileIndex.swift`
- Test: `BefoldApp/befoldTests/GitCommandFileIndexTests.swift`

**Interfaces:**
- Consumes: `GitFileIndexing`（Task 2）、`GitRepositoryReading`（Task 3）
- Produces:
  - `final class GitCommandFileIndex: GitFileIndexing, @unchecked Sendable`
    - `init(repository: GitRepositoryReading = GitRepository())`
    - `func trackedFiles(forFileAt url: URL) -> [URL]?`
    - `func warm(forFileAt url: URL)`（背景でキャッシュを温める）

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/GitCommandFileIndexTests.swift`:

```swift
import Foundation
import Testing
@testable import befold

private final class FakeRepository: GitRepositoryReading, @unchecked Sendable {
    var stubRoot: URL?
    var fingerprint: Date?
    var files: [URL]
    private(set) var trackedCallCount = 0

    init(root: URL?, fingerprint: Date?, files: [URL]) {
        self.stubRoot = root
        self.fingerprint = fingerprint
        self.files = files
    }

    func root(forFileAt url: URL) -> URL? { stubRoot }
    func trackedFiles(at root: URL) -> [URL] { trackedCallCount += 1; return files }
    func indexFingerprint(at root: URL) -> Date? { fingerprint }
}

struct GitCommandFileIndexTests {
    private func url(_ p: String) -> URL { URL(fileURLWithPath: p) }

    @Test("追跡ファイルを返す")
    func returnsTrackedFiles() {
        let repo = FakeRepository(root: url("/repo"), fingerprint: Date(timeIntervalSince1970: 1),
                                  files: [url("/repo/a.swift")])
        let sut = GitCommandFileIndex(repository: repo)
        #expect(sut.trackedFiles(forFileAt: url("/repo/docs/x.md")) == [url("/repo/a.swift")])
    }

    @Test("git 管理外は nil")
    func returnsNilOutsideRepo() {
        let repo = FakeRepository(root: nil, fingerprint: nil, files: [])
        #expect(GitCommandFileIndex(repository: repo).trackedFiles(forFileAt: url("/x/y.md")) == nil)
    }

    @Test("同一 fingerprint では再列挙しない(キャッシュ命中)")
    func cachesWhileFingerprintUnchanged() {
        let repo = FakeRepository(root: url("/repo"), fingerprint: Date(timeIntervalSince1970: 1),
                                  files: [url("/repo/a.swift")])
        let sut = GitCommandFileIndex(repository: repo)
        _ = sut.trackedFiles(forFileAt: url("/repo/docs/x.md"))
        _ = sut.trackedFiles(forFileAt: url("/repo/docs/y.md"))
        #expect(repo.trackedCallCount == 1)
    }

    @Test("fingerprint が変われば再列挙する(無効化)")
    func refetchesWhenFingerprintChanges() {
        let repo = FakeRepository(root: url("/repo"), fingerprint: Date(timeIntervalSince1970: 1),
                                  files: [url("/repo/a.swift")])
        let sut = GitCommandFileIndex(repository: repo)
        _ = sut.trackedFiles(forFileAt: url("/repo/docs/x.md"))
        repo.fingerprint = Date(timeIntervalSince1970: 2) // 外部の checkout / commit 相当
        repo.files = [url("/repo/a.swift"), url("/repo/b.swift")]
        let after = sut.trackedFiles(forFileAt: url("/repo/docs/x.md"))
        #expect(repo.trackedCallCount == 2)
        #expect(after == [url("/repo/a.swift"), url("/repo/b.swift")])
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd BefoldApp && swift test --filter GitCommandFileIndexTests`
Expected: FAIL（`GitCommandFileIndex` が未定義）

- [ ] **Step 3: 実装を書く**

`BefoldApp/befold/App/GitCommandFileIndex.swift`:

```swift
import BefoldKit
import Foundation

/// GitRepository を使って追跡ファイル一覧を返し、リポジトリルート単位でキャッシュする。
/// キャッシュは .git/index の fingerprint で無効化するため、外部のブランチ/ワークツリー
/// 切替・commit で追跡集合が変わっても自動で再取得する。git 管理外は nil。
/// 参照は少数(開いているウィンドウ分)のため、単一 NSLock で直列化する
/// (subprocess を lock 内で回すが、fingerprint 一致時はキャッシュ命中で subprocess 無し)。
final class GitCommandFileIndex: GitFileIndexing, @unchecked Sendable {
    private let repository: GitRepositoryReading
    private let lock = NSLock()
    private var rootByDir: [String: URL?] = [:]
    private var entryByRoot: [String: (fingerprint: Date?, files: [URL])] = [:]

    init(repository: GitRepositoryReading = GitRepository()) {
        self.repository = repository
    }

    func trackedFiles(forFileAt url: URL) -> [URL]? {
        let dirKey = url.deletingLastPathComponent().standardizedFileURL.path

        lock.lock(); defer { lock.unlock() }

        let root: URL?
        if let cached = rootByDir[dirKey] {
            root = cached
        } else {
            root = repository.root(forFileAt: url)
            rootByDir[dirKey] = root
        }
        guard let root else { return nil }

        let fingerprint = repository.indexFingerprint(at: root)
        if let entry = entryByRoot[root.path], entry.fingerprint == fingerprint {
            return entry.files
        }
        let files = repository.trackedFiles(at: root)
        entryByRoot[root.path] = (fingerprint, files)
        return files
    }

    /// 開いた/切り替えたタイミングで背景実行し、解決要求時のキャッシュ命中を狙う。
    func warm(forFileAt url: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = self?.trackedFiles(forFileAt: url)
        }
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd BefoldApp && swift test --filter GitCommandFileIndexTests`
Expected: PASS（4 テスト）

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/GitCommandFileIndex.swift BefoldApp/befoldTests/GitCommandFileIndexTests.swift
git commit -m "feat: index fingerprint で無効化する追跡ファイルキャッシュを追加する"
```

---

### Task 5: handleOpenReference を TrackedPathResolver に切り替える（クリック時の曖昧解決）

クリック時の解決を `ReferenceResolver` + 存在確認から `TrackedPathResolver` に置き換え、相対で解決できないパスも git サフィックス一致で開けるようにする（表示時と同じ解決結果になる）。

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift:285-303`（`handleOpenReference`）、および resolver / gitIndex のプロパティ追加
- Test: `BefoldApp/befoldTests/ViewerWindowControllerTests.swift`（既存ファイルにテスト追加。無ければ新規作成）

**Interfaces:**
- Consumes: `TrackedPathResolver`（Task 2）、`GitCommandFileIndex`（Task 4）
- Produces:
  - `ViewerWindowController` に internal な `var pathResolver: TrackedPathResolver`（テスト差し替え可能）
  - `ViewerWindowController` に `let gitFileIndex: GitCommandFileIndex`
  - `func resolveReferences(_ paths: [String]) -> [String: String]`（Task 6 で使用。書かれたパス→解決済み絶対パス。resolved のみ収録）

- [ ] **Step 1: プロパティを追加する**

`ViewerWindowController` のプロパティ宣言部（既存プロパティ群の近く）に追加:

```swift
    /// git 追跡ファイルの索引(リポジトリルート単位でキャッシュ)。
    let gitFileIndex = GitCommandFileIndex()
    /// パス参照の解決器。テストから差し替えられるよう var。
    lazy var pathResolver = TrackedPathResolver(gitIndex: gitFileIndex)
```

- [ ] **Step 2: handleOpenReference を書き換える**

`ViewerWindowController.swift:285-303` を差し替え:

```swift
    func handleOpenReference(href: String, newWindow: Bool) {
        switch pathResolver.resolve(href: href, baseURL: fileURL) {
        case let .external(url):
            NSWorkspace.shared.open(url)
        case let .resolved(url):
            if newWindow {
                openFileInNewWindow(url)
            } else {
                switchFile(to: url)
            }
        case .unresolved:
            // 解決できなかったパスは、素朴な相対解決結果を「見つかりません」表示に使う。
            if case let .localFile(url) = ReferenceResolver.resolve(href: href, baseURL: fileURL) {
                showFileNotFoundAlert(url: url)
            }
        case .ignored:
            break
        }
    }

    /// パス参照群を解決し、実在するものだけ「書かれたパス→解決済み絶対パス」で返す(表示時解決用)。
    func resolveReferences(_ paths: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for path in paths {
            if case let .resolved(url) = pathResolver.resolve(href: path, baseURL: fileURL) {
                result[path] = url.path
            }
        }
        return result
    }
```

- [ ] **Step 3: 失敗するテストを書く**

`ViewerWindowControllerTests.swift` に追加（`@testable import befold` と `@MainActor` テストは既存の同ファイルの流儀に合わせる）:

```swift
    @Test("resolveReferences は実在パスのみ解決済み絶対パスで返す")
    @MainActor
    func resolveReferencesReturnsResolvedOnly() throws {
        // 一時 git リポジトリを作り、controller.fileURL 配下として解決させる。
        // controller の生成は同ファイル既存テストのヘルパーに合わせる。
        // ここでは pathResolver をフェイク index で差し替えて純粋に検証する。
        let base = URL(fileURLWithPath: "/repo/docs/guide.md")
        let tracked = URL(fileURLWithPath: "/repo/src/utils.swift")
        struct FakeIndex: GitFileIndexing { func trackedFiles(forFileAt url: URL) -> [URL]? { [tracked] }
            let tracked: URL }
        let controller = try makeControllerForTest(fileURL: base) // 既存ヘルパー名に合わせる
        controller.pathResolver = TrackedPathResolver(
            fileReader: PermissiveExistingFileReader(existing: []), // 相対は実在しない前提
            gitIndex: FakeIndex(tracked: tracked))
        let map = controller.resolveReferences(["utils.swift", "https://x.com", "nope.swift"])
        #expect(map == ["utils.swift": "/repo/src/utils.swift"])
    }
```

補助 `PermissiveExistingFileReader` は Task 2 の `FakeFileReader` と同等。テストターゲット内で共有ヘルパー化してもよい。`makeControllerForTest` は既存テストの生成手順（無ければ、同ファイルの `ViewerWindowController` 生成箇所を流用して最小構成で作る）に置き換える。

- [ ] **Step 4: テストが失敗→実装済みで通ることを確認**

Run: `cd BefoldApp && swift test --filter ViewerWindowControllerTests`
Expected: PASS（追加テスト含む。既存テストも緑）

- [ ] **Step 5: warm 呼び出しを足す**

ファイルを開く/切り替える経路でキャッシュを温める。`switchFile(to:)`（`ViewerWindowController.swift:342`）の先頭付近と、コントローラ初期化直後に追加:

```swift
        gitFileIndex.warm(forFileAt: newURL)   // switchFile(to:) の performFileSwitch 前
```

初期表示のため、`fileURL` 確定後（init 末尾など fileURL が使える箇所）に:

```swift
        gitFileIndex.warm(forFileAt: fileURL)
```

- [ ] **Step 6: コミット**

```bash
git add BefoldApp/befold/App/ViewerWindowController.swift BefoldApp/befoldTests/ViewerWindowControllerTests.swift
git commit -m "feat: クリック時のパス参照解決を git フォールバック対応にする"
```

---

### Task 6: ブリッジ配線（resolveReferences メッセージ + 適用スクリプト + Renderer 配線）

JS→Swift の `resolveReferences` メッセージと、Swift→JS の解決結果適用スクリプトを追加し、`ViewerRenderer` に受信ディスパッチと `onResolveReferences` コールバックを配線する。

**Files:**
- Modify: `BefoldApp/BefoldKit/ViewerBridge.swift`（メッセージ名 + 適用スクリプト）
- Modify: `BefoldApp/BefoldRenderKit/ViewerRenderer.swift`（`onResolveReferences` プロパティ + `messageHandlerNames`）
- Modify: `BefoldApp/BefoldRenderKit/ViewerRenderer+MessageHandling.swift`（受信分岐）
- Test: `BefoldApp/befoldTests/ViewerBridgeTests.swift`（文字列整合）

**Interfaces:**
- Consumes: `ViewerBridge`（既存）
- Produces:
  - `ViewerBridge.resolveReferencesMessageName = "resolveReferences"`
  - `ViewerBridge.applyResolvedReferencesScript(_ resolutions: [String: String]) -> String`
  - `ViewerRenderer.onResolveReferences: (@MainActor (_ paths: [String]) -> [String: String])?`

- [ ] **Step 1: ViewerBridge に追加する**

`ViewerBridge.swift` の `loadMoreLinesMessageName`（:114）付近に追加:

```swift
    /// JS 側が検出したパス参照の解決を要求するときに postMessage されるメッセージハンドラ名。
    /// payload: { paths: [String] }
    public static let resolveReferencesMessageName = "resolveReferences"

    /// 解決結果(書かれたパス -> 解決済み絶対パス。未解決は含めない)を JS へ適用する
    /// スクリプトを組み立てる。viewer.html 側は _mmdApplyResolvedReferences() が受け取り、
    /// 収録されたパスだけをリンク化する。
    public static func applyResolvedReferencesScript(_ resolutions: [String: String]) -> String {
        "_mmdApplyResolvedReferences(\(jsonLiteral(resolutions) ?? "{}"))"
    }
```

- [ ] **Step 2: ViewerRenderer に配線する**

`ViewerRenderer.swift`：`onOpenReference` 宣言（:13）の直後に:

```swift
    /// JS が検出したパス参照群の解決を要求したときに呼ばれる。
    /// 戻り値: 書かれたパス -> 解決済み絶対パス(実在するもののみ)。
    public var onResolveReferences: (@MainActor (_ paths: [String]) -> [String: String])?
```

`messageHandlerNames(for:)`（:151-162）の `allowsInteractiveBridging` 分岐へ追加:

```swift
        if features.allowsInteractiveBridging {
            names.append(ViewerBridge.loadMoreLinesMessageName)
            names.append(ViewerBridge.referenceActivatedMessageName)
            names.append(ViewerBridge.resolveReferencesMessageName)
        }
```

- [ ] **Step 3: 受信ディスパッチを足す**

`ViewerRenderer+MessageHandling.swift` の `userContentController(_:didReceive:)`、`loadMoreLines` 分岐（:56-58）の後に追加:

```swift
        } else if message.name == ViewerBridge.resolveReferencesMessageName,
                  let body = message.body as? [String: Any],
                  let paths = body["paths"] as? [String]
        {
            let resolutions = onResolveReferences?(paths) ?? [:]
            webView?.evaluateJavaScript(ViewerBridge.applyResolvedReferencesScript(resolutions))
        }
```

（`webView` は `ViewerRenderer` が `makeWebView` で保持する既存プロパティ。既存 RenderHelpers が `webView.evaluateJavaScript` を使っているのと同じ参照を用いる。optional なら `webView?.` とする。）

- [ ] **Step 4: 文字列整合テストを足す**

`ViewerBridgeTests.swift` に、viewer-main.js のソースを読んで定数一致を検証する既存テストの流儀で追加:

```swift
    @Test("resolveReferences メッセージ名が JS と一致する")
    func resolveReferencesMessageNameMatchesJS() throws {
        let js = try viewerMainJSSource() // 既存ヘルパー名に合わせる
        #expect(js.contains("'\(ViewerBridge.resolveReferencesMessageName)'"))
        #expect(js.contains("_mmdApplyResolvedReferences"))
    }
```

（`viewerMainJSSource()` は同ファイル既存テストが viewer-main.js を読む手段に合わせる。無ければ `Bundle.befoldKitResources` から `viewer-main.js` を読む。）

- [ ] **Step 5: テストが通ることを確認**

Run: `cd BefoldApp && swift test --filter ViewerBridgeTests`
Expected: PASS（追加テスト含む。この時点で JS 側 `_mmdApplyResolvedReferences` は Task 7 で追加するため、Step 4 の JS 参照アサートは Task 7 完了後に緑になる。順序上、本 Task では `resolveReferencesMessageName` の存在アサートのみ先に通し、`_mmdApplyResolvedReferences` 行は Task 7 の Step でまとめて緑にする。）

> 実行順の注意: Task 6 と Task 7 は密結合。`_mmdApplyResolvedReferences` を参照するアサートは Task 7 の JS 追加後に緑になる。両 Task を続けて実装し、最後にまとめて `swift test` を通すこと。

- [ ] **Step 6: コミット**

```bash
git add BefoldApp/BefoldKit/ViewerBridge.swift BefoldApp/BefoldRenderKit/ViewerRenderer.swift BefoldApp/BefoldRenderKit/ViewerRenderer+MessageHandling.swift BefoldApp/befoldTests/ViewerBridgeTests.swift
git commit -m "feat: パス解決要求のブリッジメッセージを追加する"
```

---

### Task 7: 表示時解決（JS 収集・中立化・適用 + CSS + コールバック配線）

描画後に候補パスを収集して `resolveReferences` を送り、解決結果が返るまでは中立表示（リンクに見せない）、返ってきたら解決済みのものだけをリンク化する。`onResolveReferences` コールバックを ViewerWindowController まで配線する。

**Files:**
- Modify: `BefoldApp/BefoldKit/Resources/viewer-main.js`（収集/中立化/適用、click ガード、call sites）
- Modify: `BefoldApp/BefoldKit/Resources/style.css`（pending/dead の中立スタイル）
- Modify: `BefoldApp/befold/Viewer/ViewerWebView.swift`（`onResolveReferences` を renderer へ）
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`（closure 供給）
- Modify: 中間ビュー（`ViewerContentView` 等、`onOpenReference` を仲介している型）に `onResolveReferences` を素通しで追加

**Interfaces:**
- Consumes: `ViewerRenderer.onResolveReferences`（Task 6）、`ViewerWindowController.resolveReferences(_:)`（Task 5）
- Produces: JS グローバル `_mmdApplyResolvedReferences(map)`、`_mmdResolveReferences()`

- [ ] **Step 1: JS に定数と関数を足す**

`viewer-main.js` 冒頭のメッセージ定数（:1-6）に追加:

```javascript
  const _MSG_RESOLVE_REFERENCES = 'resolveReferences';
```

`_annotatePathRefs`（:182）の直後（関数定義群のあたり）に追加:

```javascript
  // href がローカルパス候補か。#アンカー・http(s) 等スキーム付きは除外。
  // file.md:12 が scheme="file.md" と誤解釈される都合、ドットを含むスキームは許可する。
  function _mmdIsLocalPathHref(href) {
    if (!href) return false;
    if (href.charAt(0) === '#') return false;
    var m = href.match(/^([a-zA-Z][a-zA-Z0-9+.\-]*):/);
    if (m && m[1].indexOf('.') === -1) return false; // http:, mailto:, tel: 等
    return true;
  }

  // 描画直後に呼ぶ。ローカルパス候補(<a> と .befold-path-ref)を中立化(pending)し、
  // 一意なパス集合を Swift へ送って解決を要求する。解決が返るまでリンクに見せない。
  function _mmdResolveReferences() {
    if (!isHostFeatureEnabled(window._mmdHostFeatures, 'referenceActivation')) return;
    var wrap = document.getElementById('diagram-wrap');
    if (!wrap) return;
    var targets = [];
    wrap.querySelectorAll('a[href]').forEach(function(a) {
      var href = a.getAttribute('href');
      if (_mmdIsLocalPathHref(href)) {
        a.classList.add('befold-link-pending');
        targets.push({ el: a, raw: href });
      }
    });
    wrap.querySelectorAll('.befold-path-ref').forEach(function(s) {
      s.classList.add('befold-link-pending');
      targets.push({ el: s, raw: s.dataset.path });
    });
    window._mmdPendingRefs = targets;
    if (!targets.length) return;
    var uniq = {};
    targets.forEach(function(t) { if (t.raw) uniq[t.raw] = true; });
    _mmdPostMessage(_MSG_RESOLVE_REFERENCES, { paths: Object.keys(uniq) });
  }

  // Swift からの解決結果(書かれたパス -> 解決済み絶対パス)を適用する。
  // map に含まれるものだけリンク化し、含まれないものは通常テキストに戻す。
  function _mmdApplyResolvedReferences(map) {
    var targets = window._mmdPendingRefs || [];
    targets.forEach(function(t) {
      t.el.classList.remove('befold-link-pending');
      var abs = map && map[t.raw];
      if (abs) {
        t.el.classList.add('befold-link');
        t.el.dataset.resolved = abs;
      } else {
        t.el.classList.add('befold-link-dead');
        if (t.el.tagName === 'A') { t.el.removeAttribute('href'); }
      }
    });
    window._mmdPendingRefs = [];
  }
```

- [ ] **Step 2: 描画後に解決を呼ぶ**

`_annotatePathRefs();` の 2 箇所（:963 と :1129）を、それぞれ直後に解決要求を続ける形へ:

```javascript
        _annotatePathRefs();
        _mmdResolveReferences();
```

（:1129 側も同様に `_annotatePathRefs();` の直後へ `_mmdResolveReferences();` を追加する。）

- [ ] **Step 3: click ハンドラに pending/dead ガードを足す**

`viewer-main.js:143-144`（`var target = anchor || pathRef; if (!target) return;`）の直後に追加:

```javascript
    // 解決待ち・解決失敗の参照はクリック不可(通常テキスト扱い)。
    if (target.classList.contains('befold-link-pending') ||
        target.classList.contains('befold-link-dead')) {
      return;
    }
```

（外部 `<a>`・`#` アンカーは中立化対象外なので pending/dead クラスを持たず、従来どおり動作する。）

- [ ] **Step 4: CSS に中立スタイルを足す**

`style.css` の末尾（:599 の後）に追加:

```css
/* 解決待ち(pending)・解決失敗(dead)のパス参照/リンクは通常テキスト表示にする。
   pending は Swift の解決応答が返るまでの一時状態(偽リンクを見せないため)。
   .befold-path-ref / <a> の基本スタイルより後に置き、同 specificity で上書きする。 */
.befold-link-pending,
.befold-link-dead,
a.befold-link-pending,
a.befold-link-dead {
    text-decoration: none;
    cursor: default;
    color: inherit;
}
.befold-link-pending:hover,
.befold-link-dead:hover,
pre .befold-link-pending,
pre .befold-link-dead {
    color: inherit;
    text-decoration: none;
}
/* cmd 押下時も dead はクリック手がかりを出さない(コードブロック内の実在しないパス対策)。 */
.cmd-held .befold-link-dead,
.cmd-held pre .befold-link-dead {
    text-decoration: none;
    cursor: default;
}
```

- [ ] **Step 5: onResolveReferences を配線する**

`ViewerWebView.swift`：`onOpenReference` プロパティ（:39）の直後に追加:

```swift
    /// JS がパス参照の解決を要求したときに呼ばれる。戻り値: 書かれたパス→解決済み絶対パス。
    let onResolveReferences: @MainActor (_ paths: [String]) -> [String: String]
```

`makeNSView`（:55 の `renderer.onOpenReference = onOpenReference` の後）と `updateNSView`（:70 の同行の後）にそれぞれ追加:

```swift
        renderer.onResolveReferences = onResolveReferences
```

中間ビュー（`onOpenReference` を `ViewerWebView` へ渡している型。`grep -rn "onOpenReference" BefoldApp/befold` で全仲介箇所を特定する）に、`onOpenReference` と同じ形で `onResolveReferences: @MainActor (_ paths: [String]) -> [String: String]` を素通しで追加する。

`ViewerWindowController.swift`：`onOpenReference` クロージャ供給（:238-240）の直後に追加:

```swift
            onResolveReferences: { [weak self] paths in
                self?.resolveReferences(paths) ?? [:]
            },
```

- [ ] **Step 6: ビルドと全テストを通す**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功
Run: `cd BefoldApp && swift test`
Expected: PASS（Task 5 Step 4 の `_mmdApplyResolvedReferences` 参照アサートを含め全緑）

- [ ] **Step 7: WebView スモークで目視確認**

`/webview-smoke` を実行し、実在パス（相対・git 追跡ファイルへのサフィックス）だけがリンク色/下線で表示され、実在しないパスが通常テキストで表示されること、クリックで対象ファイルが開くことを確認する。git 管理外のファイルを開いた場合にパスがリンク化されないことも確認する。

- [ ] **Step 8: コミット**

```bash
git add BefoldApp/BefoldKit/Resources/viewer-main.js BefoldApp/BefoldKit/Resources/style.css BefoldApp/befold/Viewer/ViewerWebView.swift BefoldApp/befold/App/ViewerWindowController.swift
git commit -m "feat: パス参照を表示時に解決し実在するものだけリンク化する"
```

---

## 将来の拡張（本計画ではスコープ外）

ブランチ/ワークツリー切替・ブランチ間比較・差分表示は本計画では実装しない。ただし本計画で導入する git シームを拡張点として使う：

- `GitCommandRunner`：git 呼び出しの共通土台。差分（`git diff`）・ブランチ列挙（`git branch`）等はここを再利用する。
- `GitRepository`：ルート検出・追跡ファイル列挙・fingerprint を提供。将来「現在のブランチ/HEAD」「ワークツリー一覧」「任意 ref のファイル列挙（`git ls-tree <ref>`）」を生やす場所。
- キャッシュ無効化：`.git/index` の fingerprint により、外部のブランチ/ワークツリー切替・commit を subprocess なしで自動追従する（本計画時点で有効）。将来「特定 ref に対するパス解決」に踏み込む場合は `GitRepositoryReading` に ref 引数付きの列挙を追加する。

## Self-Review

**Spec coverage:**
- git ls-files 採用 → Task 3（`GitRepository.trackedFiles`）。
- 再利用可能な git シーム（Runner/Repository 分離）→ Task 3。
- キャッシュ無効化（`.git/index` fingerprint・worktree 対応）→ Task 3（fingerprint）+ Task 4（無効化ロジック）。
- 段階的解決（相対→git root→サフィックス一致）→ Task 2（git root 相対はサフィックス一致が包含）。
- 構成要素単位サフィックス一致 → Task 1。
- 近さランキング + 決定論的タイブレーク → Task 1。
- 表示時解決（方式A: Swift 一括解決の往復）→ Task 6 + 7。
- 解決済みのみリンク化・未解決は中立表示 → Task 7。
- git 管理外は存在確認で通ればリンク（サフィックスのみ git 依存）→ Task 2 のロジック。
- コピー機能への布石（解決済み絶対パスを data 属性保持）→ Task 7 の `dataset.resolved`。
- 解決の単一情報源（表示時とクリック時で同一）→ Task 5 が `TrackedPathResolver` を共用。

**Placeholder scan:** テスト内の `makeControllerForTest` / `viewerMainJSSource` / `TempDir` API は「既存テストの流儀に合わせる」明示のフックとして残す（該当プロジェクト固有ヘルパーの実名は実装時に確認）。それ以外に TBD/TODO は無し。

**Type consistency:**
- `GitFileIndexing.trackedFiles(forFileAt:)` は Task 2 定義・Task 4 実装・テストのフェイクで一致。
- `GitRepositoryReading`（root/trackedFiles/indexFingerprint）は Task 3 定義・実装、Task 4 の消費・フェイクで一致。
- `ResolvedReference` のケース名（external/resolved/unresolved/ignored）は Task 2・5 で一致。
- `onResolveReferences` の型 `(_ paths: [String]) -> [String: String]` は Task 6（renderer）・Task 7（ViewerWebView/中間ビュー/ViewerWindowController）で一致。
- `applyResolvedReferencesScript(_:)` の引数 `[String: String]` と `resolveReferences(_:)` の戻り値 `[String: String]` が一致。
