# 「最近使ったリポジトリを開く」メニュー Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** git リポジトリ内のファイルを開くと、そのリポジトリ/worktree のルートを自動記憶し、File メニューの新規サブメニュー「Recent Repositories」から選ぶと、最後のタブ構成があれば復元し、無ければルートフォルダを新規ウィンドウで開けるようにする。

**Architecture:** 既存の `RecentDocumentsStore` + `RecentDocumentsMenuController` と同型の `RecentRepositoriesStore` + `RecentRepositoriesMenuController` を新設する。`RecentRepositoriesStore` は識別情報(ルートパス・表示ラベル)に加えて「最後のタブ構成」(`SessionLayout.TabGroup`)も1エントリにまとめて UserDefaults へ永続化する。`ViewerWindowManager.openViewer` がウィンドウ生成時に git ルートを解決してエントリを記録し、`viewerWindowWillClose` のたびにそのウィンドウのタブ構成を最新状態として上書きする。メニュー選択時は `SessionRestorer` に新設する `openRepository(root:savedTabGroup:)` が、保存済みタブ構成があれば既存の `restoreTabGroup` ロジックで復元し、無ければ従来の「フォルダを開く」経路にフォールバックする。

**Tech Stack:** Swift 6 / AppKit、`git` subprocess(`GitCommandRunner`)、UserDefaults(JSON エンコードした `[RecentRepositoryEntry]`)、Swift Testing。

## Global Constraints

- 対応 Backlog タスク: task-190。参照する設計: `docs/superpowers/specs/2026-07-30-recent-repositories-menu-design.md`
- 保持件数上限は 10 件(`RecentDocumentsStore` と同じ)
- worktree ラベルは `"<本体のディレクトリ名> (<worktreeのディレクトリ名>)"`、本体は `"<ディレクトリ名>"`(接尾辞なし)
- worktree 判定は `git rev-parse --git-common-dir --git-dir` の比較で行う(一致=本体、不一致=worktree)
- タブ構成の記録はウィンドウが閉じるたび(`viewerWindowWillClose`)に上書きする。専用の「アプリ終了時に一括保存」経路は設けない
- git 呼び出しはウィンドウ生成という一度きりのコスト内で同期的に行ってよい(`ViewerWindowController.init` が `directoryLister` を同期取得しているのと同じ方針)。繰り返し呼ばれる経路(フォルダ移動時のヘッダー表示等)は対象外
- Swift ファイルはすべて `BefoldApp/befold/App/` 配下、対応テストは `BefoldApp/befoldTests/` 配下に置く
- コミットメッセージは Conventional Commits + 日本語(例: `feat: 最近使ったリポジトリを開くメニューを追加する`)。本 Plan の実装はすべて1つの機能追加であり、関連コミットは `--amend` でまとめてよい(ただし push 済みでない場合に限る)

---

### Task 1: GitRepository にリポジトリ表示ラベルの解決を追加する

**Files:**
- Modify: `BefoldApp/befold/App/GitRepository.swift`
- Test: `BefoldApp/befoldTests/GitRepositoryTests.swift`

**Interfaces:**
- Produces: `GitRepository.repositoryLabel(forRoot root: URL) -> String`(以降のタスクがラベル解決に使う)

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/GitRepositoryTests.swift` の `struct GitRepositoryTests` 内、既存の `@Test("index の更新で fingerprint が変わる")` の直後に以下を追加する。

```swift
    @Test("本体リポジトリのラベルは接尾辞なしのディレクトリ名になる")
    func repositoryLabelForMainRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)

        let label = makeRepository().repositoryLabel(forRoot: temp.url)

        #expect(label == temp.url.standardizedFileURL.lastPathComponent)
    }

    @Test("worktree のラベルは本体名とworktreeディレクトリ名を併記する")
    func repositoryLabelForWorktree() throws {
        let main = try TempDir(prefix: "main-repo")
        defer { withExtendedLifetime(main) {} }
        try makeRepo(main.url)
        let worktreeParent = try TempDir(prefix: "worktree-parent")
        defer { withExtendedLifetime(worktreeParent) {} }
        let worktreeDir = worktreeParent.url.appendingPathComponent("feature-x")
        git(main.url, ["worktree", "add", worktreeDir.path, "-b", "feature-x"])

        let label = makeRepository().repositoryLabel(forRoot: worktreeDir)

        let mainName = main.url.standardizedFileURL.lastPathComponent
        #expect(label == "\(mainName) (feature-x)")
    }

    @Test("git を実行できない場合はディレクトリ名のみに縮退する")
    func repositoryLabelFallsBackWhenGitUnavailable() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)
        let repo = GitRepository(runner: GitCommandRunner(timeout: 0.001))

        let label = repo.repositoryLabel(forRoot: temp.url)

        #expect(label == temp.url.standardizedFileURL.lastPathComponent)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter GitRepositoryTests`
Expected: FAIL(`repositoryLabel` が存在せずビルドエラー)

- [ ] **Step 3: 実装する**

`BefoldApp/befold/App/GitRepository.swift` の `struct GitRepository` 内、`indexFingerprint` メソッドの直後(72行目の `private func gitDirectory` の前)に以下を追加する。

```swift
    /// メニュー表示用のリポジトリラベルを返す。本体なら "<ディレクトリ名>"、worktree なら
    /// "<本体のディレクトリ名> (<このworktreeのディレクトリ名>)"。
    /// `--git-common-dir` と `--git-dir` を比較し、一致すれば本体、不一致なら worktree と判定する
    /// (worktree の `.git` はファイルで実 gitdir を指すため両者が食い違う)。
    /// git 呼び出しに失敗した場合はディレクトリ名のみ(本体扱い)に縮退する。
    func repositoryLabel(forRoot root: URL) -> String {
        let directoryName = root.standardizedFileURL.lastPathComponent
        guard case let .output(data) = runner.run(["rev-parse", "--git-common-dir", "--git-dir"], in: root),
              let text = String(data: data, encoding: .utf8)
        else { return directoryName }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.count == 2 else { return directoryName }
        let commonDir = URL(fileURLWithPath: lines[0], relativeTo: root).standardizedFileURL
        let gitDir = URL(fileURLWithPath: lines[1], relativeTo: root).standardizedFileURL
        guard commonDir.path != gitDir.path else { return directoryName }
        let mainRepositoryName = commonDir.deletingLastPathComponent().lastPathComponent
        return "\(mainRepositoryName) (\(directoryName))"
    }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter GitRepositoryTests`
Expected: PASS(既存テストも含め全て)

- [ ] **Step 5: コミット**

```bash
cd BefoldApp
git add befold/App/GitRepository.swift befoldTests/GitRepositoryTests.swift
git commit -m "feat: GitRepository にリポジトリ表示ラベルの解決を追加する"
```

---

### Task 2: RecentRepositoryEntry / RecentRepositoriesStore を追加する

**Files:**
- Create: `BefoldApp/befold/App/RecentRepositoriesStore.swift`
- Test: `BefoldApp/befoldTests/RecentRepositoriesStoreTests.swift`

**Interfaces:**
- Consumes: `BefoldKit` の `URL.normalizedPathKey`、`FileReading` / `DefaultFileReader`(`BefoldKit/FileReading.swift`)、`SessionStore.swift` で定義済みの `SessionLayout.TabGroup`
- Produces:
  - `struct RecentRepositoryEntry: Codable, Equatable { var rootPath: String; var label: String; var lastTabGroup: SessionLayout.TabGroup?; var root: URL { get } }`
  - `@MainActor final class RecentRepositoriesStore` with:
    - `init(defaults: UserDefaults = .standard, maximumCount: Int = 10, fileReader: any FileReading = DefaultFileReader())`
    - `func entries() -> [RecentRepositoryEntry]`
    - `func record(root: URL, label: String)`
    - `func updateLastTabGroup(root: URL, _ group: SessionLayout.TabGroup)`
    - `func pruneMissing()`
    - `func clear()`

- [ ] **Step 1: 失敗するテストを書く**

Create `BefoldApp/befoldTests/RecentRepositoriesStoreTests.swift`:

```swift
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

@Suite
@MainActor
struct RecentRepositoriesStoreTests {
    private let defaults = makeIsolatedDefaults(prefix: "RecentRepositoriesStoreTests")

    private func makeStore(maximumCount: Int = 10) -> RecentRepositoriesStore {
        RecentRepositoriesStore(defaults: defaults, maximumCount: maximumCount)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Users/test/\(name)")
    }

    @Test("初期状態では一覧は空")
    func startsEmpty() {
        #expect(makeStore().entries().isEmpty)
    }

    @Test("記録した順の逆(新しい順)で並ぶ")
    func recordOrdersMostRecentFirst() {
        let store = makeStore()

        store.record(root: url("repoA"), label: "repoA")
        store.record(root: url("repoB"), label: "repoB")

        #expect(store.entries().map(\.label) == ["repoB", "repoA"])
    }

    @Test("既存エントリを開き直すと先頭に移動し重複しない")
    func recordMovesExistingEntryToFront() {
        let store = makeStore()

        store.record(root: url("repoA"), label: "repoA")
        store.record(root: url("repoB"), label: "repoB")
        store.record(root: url("repoA"), label: "repoA")

        #expect(store.entries().map(\.label) == ["repoA", "repoB"])
    }

    @Test("上限を超えた分は古い方から捨てられる")
    func recordDropsOldestBeyondMaximumCount() {
        let store = makeStore(maximumCount: 2)

        store.record(root: url("repoA"), label: "repoA")
        store.record(root: url("repoB"), label: "repoB")
        store.record(root: url("repoC"), label: "repoC")

        #expect(store.entries().map(\.label) == ["repoC", "repoB"])
    }

    @Test("record は既存エントリの lastTabGroup を保持する")
    func recordPreservesExistingLastTabGroup() {
        let store = makeStore()
        store.record(root: url("repoA"), label: "repoA")
        let group = SessionLayout.TabGroup(paths: [url("repoA/a.md").path], selectedPath: url("repoA/a.md").path)
        store.updateLastTabGroup(root: url("repoA"), group)

        store.record(root: url("repoA"), label: "repoA")

        #expect(store.entries().first?.lastTabGroup == group)
    }

    @Test("updateLastTabGroup は該当エントリのタブ構成のみ更新し並び順は変えない")
    func updateLastTabGroupUpdatesWithoutReordering() {
        let store = makeStore()
        store.record(root: url("repoA"), label: "repoA")
        store.record(root: url("repoB"), label: "repoB")
        let group = SessionLayout.TabGroup(paths: [url("repoA/a.md").path], selectedPath: url("repoA/a.md").path)

        store.updateLastTabGroup(root: url("repoA"), group)

        #expect(store.entries().map(\.label) == ["repoB", "repoA"])
        #expect(store.entries().first { $0.label == "repoA" }?.lastTabGroup == group)
    }

    @Test("記録されていないルートへの updateLastTabGroup は何もしない")
    func updateLastTabGroupIgnoresUnknownRoot() {
        let store = makeStore()
        let group = SessionLayout.TabGroup(paths: ["/x"], selectedPath: "/x")

        store.updateLastTabGroup(root: url("unknown"), group)

        #expect(store.entries().isEmpty)
    }

    @Test("clear で一覧が全て消える")
    func clearRemovesAllEntries() {
        let store = makeStore()
        store.record(root: url("repoA"), label: "repoA")

        store.clear()

        #expect(store.entries().isEmpty)
    }

    @Test("別インスタンス(再起動相当)でも一覧が読める")
    func entriesPersistAcrossStoreInstances() {
        makeStore().record(root: url("repoA"), label: "repoA")

        let relaunched = makeStore()

        #expect(relaunched.entries().map(\.label) == ["repoA"])
    }

    @Test("pruneMissing は存在しないルートを取り除く")
    func pruneMissingRemovesNonExistentRoots() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        let missing = temp.url.appendingPathComponent("gone")
        let store = RecentRepositoriesStore(defaults: defaults, fileReader: DefaultFileReader())
        store.record(root: temp.url, label: "kept")
        store.record(root: missing, label: "gone")

        store.pruneMissing()

        #expect(store.entries().map(\.label) == ["kept"])
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter RecentRepositoriesStoreTests`
Expected: FAIL(`RecentRepositoriesStore` が存在せずビルドエラー)

- [ ] **Step 3: 実装する**

Create `BefoldApp/befold/App/RecentRepositoriesStore.swift`:

```swift
import BefoldKit
import Foundation

/// 「最近使ったリポジトリ」1件分。識別情報(ルート・表示ラベル)に加えて、
/// このリポジトリで最後に開いていたタブ構成も1エントリにまとめて持つ。
/// ラベルは記録時点(record 呼び出し時)に確定させ、表示のたびに git を呼び直さない。
struct RecentRepositoryEntry: Codable, Equatable {
    var rootPath: String
    var label: String
    var lastTabGroup: SessionLayout.TabGroup?

    var root: URL {
        URL(fileURLWithPath: rootPath)
    }
}

/// "Recent Repositories" 履歴を UserDefaults に永続化するストア。
/// RecentDocumentsStore と同じ理由(ad-hoc 署名では sharedfilelistd 由来の履歴が
/// アップデートのたびに失われる)で、自前に持つ。
@MainActor
final class RecentRepositoriesStore {
    private static let defaultsKey = "RecentRepositories"

    private let defaults: UserDefaults
    private let maximumCount: Int
    private let fileReader: any FileReading

    init(
        defaults: UserDefaults = .standard, maximumCount: Int = 10,
        fileReader: any FileReading = DefaultFileReader()
    ) {
        self.defaults = defaults
        self.maximumCount = maximumCount
        self.fileReader = fileReader
    }

    /// 一覧を最終利用順(新しい順)で返す。
    func entries() -> [RecentRepositoryEntry] {
        savedEntries()
    }

    /// リポジトリが開かれたことを記録する。既存の同一ルートは先頭へ移動し
    /// (lastTabGroup は保持したまま)、無ければ lastTabGroup なしで新規追加する。
    /// 上限を超えた分は古い方から捨てる。
    func record(root: URL, label: String) {
        let path = root.normalizedPathKey
        var entries = savedEntries()
        let existingLastTabGroup = entries.first { $0.rootPath == path }?.lastTabGroup
        entries.removeAll { $0.rootPath == path }
        entries.insert(
            RecentRepositoryEntry(rootPath: path, label: label, lastTabGroup: existingLastTabGroup), at: 0
        )
        save(Array(entries.prefix(maximumCount)))
    }

    /// 該当ルートのエントリの lastTabGroup のみ上書きする(並び順は変えない)。
    /// 記録されていないルートを渡された場合は何もしない。
    func updateLastTabGroup(root: URL, _ group: SessionLayout.TabGroup) {
        let path = root.normalizedPathKey
        var entries = savedEntries()
        guard let index = entries.firstIndex(where: { $0.rootPath == path }) else { return }
        entries[index].lastTabGroup = group
        save(entries)
    }

    /// もはやディレクトリとして存在しないルート(worktree 削除など)を一覧から取り除く。
    func pruneMissing() {
        save(savedEntries().filter { fileReader.isDirectory(at: URL(fileURLWithPath: $0.rootPath)) })
    }

    /// 一覧を全て消す(Clear Menu)。
    func clear() {
        save([])
    }

    private func savedEntries() -> [RecentRepositoryEntry] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let entries = try? JSONDecoder().decode([RecentRepositoryEntry].self, from: data)
        else { return [] }
        return entries
    }

    private func save(_ entries: [RecentRepositoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter RecentRepositoriesStoreTests`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
cd BefoldApp
git add befold/App/RecentRepositoriesStore.swift befoldTests/RecentRepositoriesStoreTests.swift
git commit -m "feat: RecentRepositoriesStore を追加する"
```

---

### Task 3: RecentRepositoriesMenuController と l10n キーを追加する

**Files:**
- Create: `BefoldApp/befold/App/RecentRepositoriesMenuController.swift`
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`
- Test: `BefoldApp/befoldTests/RecentRepositoriesMenuControllerTests.swift`

**Interfaces:**
- Consumes: `RecentRepositoryEntry`(Task 2)、既存 l10n キー `menu.file.clearMenu`
- Produces:
  - l10n キー `menu.file.recentRepositories`(en: "Recent Repositories" / ja: "最近使ったリポジトリ")
  - `@MainActor final class RecentRepositoriesMenuController: NSObject, NSMenuDelegate` with
    `init(pruneMissing: @escaping () -> Void, entries: @escaping () -> [RecentRepositoryEntry], openHandler: @escaping (RecentRepositoryEntry) -> Void, clearHandler: @escaping () -> Void)`

- [ ] **Step 1: l10n キーを追加する**

`BefoldApp/befold/Resources/Localizable.xcstrings` は JSON。`"strings"` オブジェクトへ、既存の `"menu.file.quickOpen"` の直後に(キー順はアルファベット順である必要はないが、`menu.file.*` の並びに揃えるため `openRecent` の直前に)以下のエントリを追加する。以下の Python で確実に反映する:

```bash
cd BefoldApp
python3 - <<'PY'
import json
path = "befold/Resources/Localizable.xcstrings"
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["strings"]["menu.file.recentRepositories"] = {
    "extractionState": "manual",
    "localizations": {
        "en": {"stringUnit": {"state": "translated", "value": "Recent Repositories"}},
        "ja": {"stringUnit": {"state": "translated", "value": "最近使ったリポジトリ"}},
    },
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
PY
git diff --stat befold/Resources/Localizable.xcstrings
```

Expected diff: 1件追加のみ(`sort_keys=True` で全体が並び替わり差分が大きく見える場合は、`sort_keys` を外して手動で該当キーだけを挿入すること。既存ファイルのトップレベルキー順を `git diff` で確認し、崩れていたら `json.dump(..., sort_keys=False)` に変更してやり直す)。

- [ ] **Step 2: 失敗するテストを書く**

Create `BefoldApp/befoldTests/RecentRepositoriesMenuControllerTests.swift`:

```swift
import AppKit
@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct RecentRepositoriesMenuControllerTests {
    private func makeController(
        entries: [RecentRepositoryEntry],
        onPrune: @escaping () -> Void = {},
        onOpen: @escaping (RecentRepositoryEntry) -> Void = { _ in },
        onClear: @escaping () -> Void = {}
    ) -> RecentRepositoriesMenuController {
        RecentRepositoriesMenuController(
            pruneMissing: onPrune, entries: { entries }, openHandler: onOpen, clearHandler: onClear
        )
    }

    private func entry(_ name: String) -> RecentRepositoryEntry {
        RecentRepositoryEntry(rootPath: "/tmp/\(name)", label: name, lastTabGroup: nil)
    }

    @Test("ラベルでメニュー項目が構築される")
    func populatesMenuItemsFromEntries() {
        let entries = [entry("befold"), entry("befold (worktree-a)")]
        let controller = makeController(entries: entries)
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)

        #expect(menu.items.count == 4)
        #expect(menu.items[0].title == "befold")
        #expect(menu.items[1].title == "befold (worktree-a)")
        #expect(menu.items[0].representedObject as? RecentRepositoryEntry == entries[0])
        #expect(menu.items[2].isSeparatorItem)
        #expect(menu.items[3].title == String(localized: "menu.file.clearMenu", bundle: .l10n))
    }

    @Test("表示直前に毎回 pruneMissing が呼ばれる")
    func callsPruneMissingOnEveryUpdate() {
        var pruneCount = 0
        let controller = makeController(entries: [], onPrune: { pruneCount += 1 })
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)
        controller.menuNeedsUpdate(menu)

        #expect(pruneCount == 2)
    }

    @Test("一覧が空でも Clear Menu だけは表示される")
    func showsOnlyClearMenuWhenEntriesIsEmpty() {
        let controller = makeController(entries: [])
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)

        #expect(menu.items.count == 1)
        #expect(menu.items[0].title == String(localized: "menu.file.clearMenu", bundle: .l10n))
    }

    @Test("項目選択で openHandler に該当エントリが渡る")
    func passesEntryToOpenHandlerWhenItemSelected() {
        var opened: [RecentRepositoryEntry] = []
        let target = entry("befold")
        let controller = makeController(entries: [target]) { opened.append($0) }
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)
        let item = menu.items[0]
        _ = item.target?.perform(item.action, with: item)

        #expect(opened == [target])
    }

    @Test("Clear Menu 選択でクリアハンドラが呼ばれる")
    func invokesClearHandlerWhenClearMenuSelected() {
        var cleared = false
        let controller = makeController(entries: [], onClear: { cleared = true })
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)
        let item = menu.items[0]
        _ = item.target?.perform(item.action, with: item)

        #expect(cleared)
    }
}
```

- [ ] **Step 3: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter RecentRepositoriesMenuControllerTests`
Expected: FAIL(`RecentRepositoriesMenuController` が存在せずビルドエラー)

- [ ] **Step 4: 実装する**

Create `BefoldApp/befold/App/RecentRepositoriesMenuController.swift`:

```swift
import AppKit

/// "Recent Repositories" サブメニューを RecentRepositoriesStore の一覧から自前で構築する。
/// RecentDocumentsMenuController と同じく NSMenuDelegate で表示直前に毎回再生成し、
/// 併せて存在しなくなった worktree 等の一覧メンテナンス(pruneMissing)もここで行う。
@MainActor
final class RecentRepositoriesMenuController: NSObject, NSMenuDelegate {
    private let pruneMissing: () -> Void
    private let entries: () -> [RecentRepositoryEntry]
    private let openHandler: (RecentRepositoryEntry) -> Void
    private let clearHandler: () -> Void

    init(
        pruneMissing: @escaping () -> Void,
        entries: @escaping () -> [RecentRepositoryEntry],
        openHandler: @escaping (RecentRepositoryEntry) -> Void,
        clearHandler: @escaping () -> Void
    ) {
        self.pruneMissing = pruneMissing
        self.entries = entries
        self.openHandler = openHandler
        self.clearHandler = clearHandler
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        pruneMissing()
        menu.removeAllItems()
        let currentEntries = entries()
        for entry in currentEntries {
            let item = NSMenuItem(
                title: entry.label,
                action: #selector(openRecentRepository(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = entry
            let icon = NSWorkspace.shared.icon(forFile: entry.rootPath)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !currentEntries.isEmpty {
            menu.addItem(.separator())
        }
        let clearItem = NSMenuItem(
            title: String(localized: "menu.file.clearMenu", bundle: .l10n),
            action: #selector(clearRecentRepositories(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)
    }

    @objc private func openRecentRepository(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? RecentRepositoryEntry else { return }
        openHandler(entry)
    }

    @objc private func clearRecentRepositories(_ sender: Any?) {
        clearHandler()
    }
}
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter RecentRepositoriesMenuControllerTests`
Expected: PASS

- [ ] **Step 6: コミット**

```bash
cd BefoldApp
git add befold/App/RecentRepositoriesMenuController.swift befold/Resources/Localizable.xcstrings befoldTests/RecentRepositoriesMenuControllerTests.swift
git commit -m "feat: RecentRepositoriesMenuController を追加する"
```

---

### Task 4: MainMenuBuilder に Recent Repositories サブメニューを追加する

**Files:**
- Modify: `BefoldApp/befold/App/MainMenuBuilder.swift`
- Modify: `BefoldApp/befoldTests/MainMenuBuilderTests.swift`

**Interfaces:**
- Consumes: なし(delegate は呼び出し元が注入する `NSMenuDelegate` の型のみ)
- Produces: `MainMenuBuilder.build(openAction:helpAction:recentMenuDelegate:bookmarksMenuDelegate:recentRepositoriesMenuDelegate:) -> NSMenu`(引数が1つ増える)

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/MainMenuBuilderTests.swift` の `buildMenu()` を以下に置き換える(既存呼び出し全てが自動的に新引数を使うようになる):

```swift
    private func buildMenu() -> NSMenu {
        // swift test のプロセスでは NSApp が未初期化のため、
        // MainMenuBuilder が参照する前に NSApplication.shared で初期化する
        _ = NSApplication.shared
        return MainMenuBuilder.build(
            openAction: #selector(AppDelegate.showOpenPanel),
            helpAction: #selector(AppDelegate.openHelp(_:)),
            recentMenuDelegate: StubMenuDelegate(),
            bookmarksMenuDelegate: StubMenuDelegate(),
            recentRepositoriesMenuDelegate: StubMenuDelegate()
        )
    }
```

続けて、既存の `@Test("File メニューに Open Recent と並んで Bookmarks サブメニューがある")` の直後に以下を追加する:

```swift
    @Test("File メニューに Recent Repositories サブメニューがある")
    func fileMenuHasRecentRepositoriesSubmenu() throws {
        let mainMenu = buildMenu()
        let file = try #require(submenu(titledKey: "menu.file.title", in: mainMenu))

        let recentRepositoriesItem = try #require(file.items.first {
            $0.submenu?.title == localizedTitle("menu.file.recentRepositories")
        })
        #expect(recentRepositoriesItem.submenu?.delegate != nil)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter MainMenuBuilderTests`
Expected: FAIL(`build` に `recentRepositoriesMenuDelegate` 引数が存在せずビルドエラー)

- [ ] **Step 3: 実装する**

`BefoldApp/befold/App/MainMenuBuilder.swift` を編集する。

`build` のシグネチャと呼び出しを変更:

```swift
    static func build(
        openAction: Selector,
        helpAction: Selector,
        recentMenuDelegate: NSMenuDelegate,
        bookmarksMenuDelegate: NSMenuDelegate,
        recentRepositoriesMenuDelegate: NSMenuDelegate
    ) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeAppMenuItem())
        mainMenu.addItem(makeFileMenuItem(
            openAction: openAction,
            recentMenuDelegate: recentMenuDelegate,
            bookmarksMenuDelegate: bookmarksMenuDelegate,
            recentRepositoriesMenuDelegate: recentRepositoriesMenuDelegate
        ))
        mainMenu.addItem(makeEditMenuItem())
        mainMenu.addItem(makeViewMenuItem())
        mainMenu.addItem(makeWindowMenuItem())
        mainMenu.addItem(makeHelpMenuItem(helpAction: helpAction))
        return mainMenu
    }
```

`makeFileMenuItem` のシグネチャと、Bookmarks サブメニュー構築の直後に以下を追加:

```swift
    private static func makeFileMenuItem(
        openAction: Selector, recentMenuDelegate: NSMenuDelegate, bookmarksMenuDelegate: NSMenuDelegate,
        recentRepositoriesMenuDelegate: NSMenuDelegate
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
            action: #selector(AppDelegate.showQuickOpen(_:)),
            keyEquivalent: "p"
        )

        let recentTitle = String(localized: "menu.file.openRecent", bundle: .l10n)
        let recentItem = NSMenuItem(title: recentTitle, action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: recentTitle)
        recentMenu.delegate = recentMenuDelegate
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        let bookmarksTitle = String(localized: "menu.file.bookmarks", bundle: .l10n)
        let bookmarksItem = NSMenuItem(title: bookmarksTitle, action: nil, keyEquivalent: "")
        let bookmarksMenu = NSMenu(title: bookmarksTitle)
        bookmarksMenu.delegate = bookmarksMenuDelegate
        bookmarksItem.submenu = bookmarksMenu
        menu.addItem(bookmarksItem)

        let recentRepositoriesTitle = String(localized: "menu.file.recentRepositories", bundle: .l10n)
        let recentRepositoriesItem = NSMenuItem(title: recentRepositoriesTitle, action: nil, keyEquivalent: "")
        let recentRepositoriesMenu = NSMenu(title: recentRepositoriesTitle)
        recentRepositoriesMenu.delegate = recentRepositoriesMenuDelegate
        recentRepositoriesItem.submenu = recentRepositoriesMenu
        menu.addItem(recentRepositoriesItem)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.file.close", bundle: .l10n),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        menu.addItem(.separator())
        // ⌘P は Quick Open に譲り、Print は ⇧⌘P へ移す。
        let print = menu.addItem(
            withTitle: String(localized: "menu.file.print", bundle: .l10n),
            action: #selector(ViewerWindowController.printDocument(_:)),
            keyEquivalent: "p"
        )
        // 小文字 + shift マスクで統一する(同ファイルの redo / findPrevious / hideOthers と同方式)。
        print.keyEquivalentModifierMask = [.command, .shift]
        return item
    }
```

(`recentRepositoriesItem` の追加ブロック以外は既存コードのまま。差分は「Bookmarks 構築の直後、`menu.addItem(.separator())` の前」に新ブロックを挿入するだけ。)

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter MainMenuBuilderTests`
Expected: PASS

- [ ] **Step 5: ビルド全体が壊れていないことを確認する**

Run: `cd BefoldApp && swift build`
Expected: `MainMenuBuilder.build` の呼び出し元は `AppDelegate.swift` の1箇所のみだが、まだ更新していないためここでビルドエラーになる。エラーメッセージが `AppDelegate.swift` の `MainMenuBuilder.build(...)` 呼び出しを指していることを確認する(Task 8 で解消する)。

- [ ] **Step 6: コミット**

```bash
cd BefoldApp
git add befold/App/MainMenuBuilder.swift befoldTests/MainMenuBuilderTests.swift
git commit -m "feat: MainMenuBuilder に Recent Repositories サブメニューを追加する"
```

---

### Task 5: ViewerWindowController に repositoryRoot を追加する

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`

**Interfaces:**
- Produces: `ViewerWindowController.repositoryRoot: URL?`(初期値 nil、外部から設定可能な var)

このタスクは既存の `delegate` プロパティ(`weak var delegate: ViewerWindowControllerDelegate?`)と同じ「生成後に外部(ViewerWindowManager)が設定する」パターンのプロパティを1つ追加するだけで、単体では観測可能な振る舞いの変化が無いため専用のテストは書かない(Task 6 で ViewerWindowManager 経由の振る舞いとして検証する)。

- [ ] **Step 1: 実装する**

`BefoldApp/befold/App/ViewerWindowController.swift` の `weak var delegate: ViewerWindowControllerDelegate?`(81行目)の直後に以下を追加する:

```swift
    /// このウィンドウが属する git リポジトリ(worktree の場合はそのルート)。
    /// 非 git ファイルの場合は nil。ViewerWindowManager.openViewer が解決結果を設定する。
    var repositoryRoot: URL?
```

- [ ] **Step 2: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: 成功(単なるプロパティ追加のため既存ビルドエラー(Task 4 由来)以外に新規エラーは出ない)

- [ ] **Step 3: コミット**

```bash
cd BefoldApp
git add befold/App/ViewerWindowController.swift
git commit -m "feat: ViewerWindowController に repositoryRoot を追加する"
```

---

### Task 6: ViewerWindowManager でリポジトリの記録・タブ構成の更新を行う

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowManager.swift`
- Modify: `BefoldApp/befoldTests/MockedViewerWindowManager.swift`
- Test: `BefoldApp/befoldTests/ViewerWindowManagerRecentRepositoriesTests.swift`(新規)

**Interfaces:**
- Consumes: `RecentRepositoriesStore`(Task 2)、`GitRepository.repositoryLabel(forRoot:)`(Task 1)、`ViewerWindowController.repositoryRoot`(Task 5)
- Produces: `ViewerWindowManager.init(...)` に `recentRepositoriesStore: RecentRepositoriesStore = RecentRepositoriesStore()` パラメータを追加(既定値ありのため既存呼び出し元は無変更で動く)

- [ ] **Step 1: MockedViewerWindowManager にフィクスチャを追加する**

`BefoldApp/befoldTests/MockedViewerWindowManager.swift` の `struct MockedViewerWindowManager` に以下を追加する。

`let gitFileIndex: RecordingGitFileIndex` の直後にフィールドを追加:

```swift
    let recentRepositoriesStore: RecentRepositoriesStore
```

`init` 内、`let gitFileIndex = RecordingGitFileIndex()` の直後に生成コードを追加:

```swift
        let gitFileIndex = RecordingGitFileIndex()
        self.gitFileIndex = gitFileIndex
        let recentRepositoriesStore = RecentRepositoriesStore(defaults: defaults)
        self.recentRepositoriesStore = recentRepositoriesStore
```

`manager = ViewerWindowManager(...)` の引数末尾(`gitFileIndex: gitFileIndex` の後)にカンマ区切りで追加:

```swift
            gitFileIndex: gitFileIndex,
            recentRepositoriesStore: recentRepositoriesStore
```

- [ ] **Step 2: 失敗するテストを書く**

Create `BefoldApp/befoldTests/ViewerWindowManagerRecentRepositoriesTests.swift`:

```swift
import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// git リポジトリのファイルを開く/ウィンドウを閉じる操作が RecentRepositoriesStore に
/// 正しく反映されることを検証する。実 git は起動せず、gitFileIndex を
/// RecordingGitFileIndex 派生のフェイクへ差し替えて root 解決を固定する。
@Suite
@MainActor
struct ViewerWindowManagerRecentRepositoriesTests {
    /// 常に固定の root を返すフェイク。実 git を起動しない。
    private final class FixedRootGitFileIndex: GitFileIndexing, @unchecked Sendable {
        let root: URL?
        init(root: URL?) { self.root = root }
        func trackedFileIndex(forFileAt _: URL) -> SuffixPathIndex? { nil }
        func repositoryRoot(forFileAt _: URL) -> URL? { root }
        func warm(forFileAt _: URL) {}
    }

    private func makeManager(
        files: [URL], root: URL?, defaults: UserDefaults
    ) -> (manager: ViewerWindowManager, recentRepositoriesStore: RecentRepositoriesStore) {
        let fileReader = InMemoryFileReader(
            files: Dictionary(uniqueKeysWithValues: files.map { ($0.path, "graph TD;") })
        )
        let sessionStore = SessionStore(defaults: defaults)
        let recentDocumentsStore = RecentDocumentsStore(defaults: defaults)
        let recentRepositoriesStore = RecentRepositoriesStore(defaults: defaults)
        let manager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: recentDocumentsStore,
            perFileState: PerFileStateStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            fileReader: fileReader,
            makeStore: { _ in
                ViewerStore(
                    watcherFactory: { _, _, _ in MockFileWatcher() },
                    fileReader: fileReader,
                    defaults: defaults
                )
            },
            directoryLister: { _, _, _ in [] },
            gitFileIndex: FixedRootGitFileIndex(root: root),
            recentRepositoriesStore: recentRepositoriesStore
        )
        return (manager, recentRepositoriesStore)
    }

    @Test("git リポジトリ内のファイルを開くと最近使ったリポジトリに記録される")
    func openingFileInsideRepositoryRecordsIt() {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentRepos")
        let file = URL(fileURLWithPath: "/repo/a.md")
        let root = URL(fileURLWithPath: "/repo")
        let (manager, store) = makeManager(files: [file], root: root, defaults: defaults)

        manager.openViewer(for: file)

        #expect(store.entries().map(\.rootPath) == [root.normalizedPathKey])
        #expect(manager.controllers[file.normalizedPathKey]?.first?.repositoryRoot == root)
        manager.allControllers.forEach { $0.close() }
    }

    @Test("git 管理外のファイルを開いても記録されない")
    func openingFileOutsideRepositoryDoesNotRecordAnything() {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentRepos")
        let file = URL(fileURLWithPath: "/standalone/a.md")
        let (manager, store) = makeManager(files: [file], root: nil, defaults: defaults)

        manager.openViewer(for: file)

        #expect(store.entries().isEmpty)
        #expect(manager.controllers[file.normalizedPathKey]?.first?.repositoryRoot == nil)
        manager.allControllers.forEach { $0.close() }
    }

    @Test("リポジトリのウィンドウを閉じるとタブ構成が記録される")
    func closingWindowRecordsLastTabGroup() throws {
        let defaults = makeIsolatedDefaults(prefix: "VWMRecentRepos")
        let file = URL(fileURLWithPath: "/repo/a.md")
        let root = URL(fileURLWithPath: "/repo")
        let (manager, store) = makeManager(files: [file], root: root, defaults: defaults)
        manager.openViewer(for: file)
        let controller = try #require(manager.controllers[file.normalizedPathKey]?.first)

        controller.close()

        let saved = store.entries().first { $0.rootPath == root.normalizedPathKey }
        #expect(saved?.lastTabGroup?.paths == [file.normalizedPathKey])
        #expect(saved?.lastTabGroup?.selectedPath == file.normalizedPathKey)
    }
}
```

- [ ] **Step 3: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowManagerRecentRepositoriesTests`
Expected: FAIL(`ViewerWindowManager.init` に `recentRepositoriesStore` 引数が存在せずビルドエラー)

- [ ] **Step 4: 実装する**

`BefoldApp/befold/App/ViewerWindowManager.swift` を編集する。

プロパティ追加(`private let bookmarkStore: BookmarkStore` の直後、41行目 `let gitFileIndex` の前後どちらでも可、ここでは `gitFileIndex` の直後):

```swift
    let gitFileIndex: any GitFileIndexing
    /// 「最近使ったリポジトリ」の記録先。git ルートを持つファイルを開いた際に record、
    /// そのウィンドウが閉じるたびに updateLastTabGroup で最新のタブ構成へ更新する。
    private let recentRepositoriesStore: RecentRepositoriesStore
    /// root からメニュー表示用ラベルを解決する。既定は実 GitRepository。
    /// テストは実 git を起動しないフェイクへ差し替える。
    private let repositoryLabelResolver: (URL) -> String
```

`init` のシグネチャに2引数追加(`gitFileIndex: any GitFileIndexing = GitCommandFileIndex()` の直後):

```swift
    init(
        sessionStore: SessionStore, recentDocumentsStore: RecentDocumentsStore,
        hiddenFilesPreference: HiddenFilesPreference = HiddenFilesPreference(),
        findOptionsPreference: FindOptionsPreference = FindOptionsPreference(),
        codeFontPreference: CodeFontPreference = CodeFontPreference(),
        perFileState: PerFileStateStore = PerFileStateStore(),
        bookmarkStore: BookmarkStore,
        fileReader: any FileReading = DefaultFileReader(),
        makeStore: ((URL) -> ViewerStore)? = nil,
        directoryLister: @escaping (URL, SortOrder, Bool) -> [FileListEntry] = DirectoryLister.listEntries,
        gitFileIndex: any GitFileIndexing = GitCommandFileIndex(),
        recentRepositoriesStore: RecentRepositoriesStore = RecentRepositoriesStore(),
        repositoryLabelResolver: @escaping (URL) -> String = { GitRepository().repositoryLabel(forRoot: $0) }
    ) {
        self.gitFileIndex = gitFileIndex
        self.sessionStore = sessionStore
        self.recentDocumentsStore = recentDocumentsStore
        self.hiddenFilesPreference = hiddenFilesPreference
        self.findOptionsPreference = findOptionsPreference
        self.codeFontPreference = codeFontPreference
        self.perFileState = perFileState
        self.bookmarkStore = bookmarkStore
        self.fileReader = fileReader
        self.makeStore = makeStore
        self.directoryLister = directoryLister
        self.recentRepositoriesStore = recentRepositoriesStore
        self.repositoryLabelResolver = repositoryLabelResolver
    }
```

`openViewer` 内、`NSDocumentController.shared.noteNewRecentDocumentURL(url)` の直後(215行目)に追加:

```swift
        sessionStore.noteOpened(url)
        recentDocumentsStore.noteOpened(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        recordRecentRepositoryIfNeeded(for: url, controller: controller)
    }
```

同ファイル内、`window(forPath:)` メソッドの直前あたりに新しい private メソッドを追加:

```swift
    /// url が git リポジトリ内なら「最近使ったリポジトリ」に記録し、ウィンドウへ
    /// ルートをキャッシュする(ウィンドウを閉じる際に再度 git を呼ばずに済ませるため)。
    /// git 呼び出しはウィンドウ生成という一度きりのコストとして同期的に払う
    /// (ViewerWindowController.init が directoryLister を同期取得しているのと同じ方針)。
    private func recordRecentRepositoryIfNeeded(for url: URL, controller: ViewerWindowController) {
        guard let root = gitFileIndex.repositoryRoot(forFileAt: url) else { return }
        controller.repositoryRoot = root
        recentRepositoriesStore.record(root: root, label: repositoryLabelResolver(root))
    }

    /// window(自身のタブグループ)を SessionLayout.TabGroup として組み立てる。
    /// タブが1枚も無ければ nil(ビューアウィンドウでない・既に全タブが閉じた等)。
    private func tabGroup(of window: NSWindow) -> SessionLayout.TabGroup? {
        let tabWindows = window.tabGroup?.windows ?? [window]
        let paths = tabWindows.compactMap(viewerPath(of:))
        guard !paths.isEmpty else { return nil }
        let selectedWindow = window.tabGroup?.selectedWindow ?? window
        return SessionLayout.TabGroup(paths: paths, selectedPath: viewerPath(of: selectedWindow))
    }
```

`ViewerWindowControllerDelegate` 実装の `viewerWindowWillClose` を以下に変更:

```swift
    func viewerWindowWillClose(_ controller: ViewerWindowController) {
        if let root = controller.repositoryRoot, let window = controller.window,
           let group = tabGroup(of: window)
        {
            recentRepositoriesStore.updateLastTabGroup(root: root, group)
        }
        detach(controller, fromKey: controller.fileURL.normalizedPathKey)
        sessionStore.noteClosed(controller.fileURL)
    }
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowManagerRecentRepositoriesTests`
Expected: PASS

- [ ] **Step 6: 既存の ViewerWindowManager 系テストが壊れていないことを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowManager`
Expected: PASS(`ViewerWindowManagerTests` / `ViewerWindowManagerIntegrationTests` / `ViewerWindowManagerDisplayOverridesTests` / `ViewerWindowManagerDisplayOverridesIntegrationTests` / `ViewerWindowManagerBookmarkTests` / `ViewerWindowManagerRecentRepositoriesTests` 全て。新規パラメータはデフォルト値ありのため既存呼び出しは無変更で通るはず)

- [ ] **Step 7: SessionRestorerTests が壊れていないことを確認する(MockedViewerWindowManager 変更の影響確認)**

Run: `cd BefoldApp && swift test --filter SessionRestorerTests`
Expected: PASS

- [ ] **Step 8: コミット**

```bash
cd BefoldApp
git add befold/App/ViewerWindowManager.swift befoldTests/MockedViewerWindowManager.swift befoldTests/ViewerWindowManagerRecentRepositoriesTests.swift
git commit -m "feat: ViewerWindowManager でリポジトリの記録・タブ構成の更新を行う"
```

---

### Task 7: SessionRestorer.openRepository を追加する

**Files:**
- Modify: `BefoldApp/befold/App/SessionRestorer.swift`
- Test: `BefoldApp/befoldTests/SessionRestorerTests.swift`

**Interfaces:**
- Consumes: `SessionLayout.TabGroup`(`SessionStore.swift`)、既存 private `restoreTabGroup(_:urlByPath:options:)`
- Produces: `SessionRestorer.openRepository(root: URL, savedTabGroup: SessionLayout.TabGroup?, options: CLIOpenOptions = CLIOpenOptions())`

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/SessionRestorerTests.swift` の末尾(最後の `}` の直前)に以下を追加する:

```swift
    @Test("保存済みタブ構成が全て実在すればタブごと復元する")
    func openRepositoryRestoresSavedTabGroupWhenAllPathsExist() {
        let fileA = URL(fileURLWithPath: "/repo/a.md")
        let fileB = URL(fileURLWithPath: "/repo/b.md")
        let fixture = MockedViewerWindowManager(files: [fileA, fileB], prefix: "SessionRestorerOpenRepo")
        let restorer = makeRestorer(fixture)
        let group = SessionLayout.TabGroup(
            paths: [fileA.normalizedPathKey, fileB.normalizedPathKey], selectedPath: fileB.normalizedPathKey
        )

        restorer.openRepository(root: URL(fileURLWithPath: "/repo"), savedTabGroup: group)

        #expect(fixture.manager.controllers[fileA.normalizedPathKey] != nil)
        #expect(fixture.manager.controllers[fileB.normalizedPathKey] != nil)
        fixture.closeAll()
    }

    @Test("保存済みタブ構成の一部が消えていれば残存パスだけで復元する")
    func openRepositoryFiltersMissingPathsFromSavedTabGroup() {
        let fileA = URL(fileURLWithPath: "/repo/a.md")
        let missing = URL(fileURLWithPath: "/repo/gone.md")
        let fixture = MockedViewerWindowManager(files: [fileA], prefix: "SessionRestorerOpenRepo")
        let restorer = makeRestorer(fixture)
        let group = SessionLayout.TabGroup(
            paths: [fileA.normalizedPathKey, missing.normalizedPathKey], selectedPath: missing.normalizedPathKey
        )

        restorer.openRepository(root: URL(fileURLWithPath: "/repo"), savedTabGroup: group)

        #expect(fixture.manager.controllers[fileA.normalizedPathKey] != nil)
        #expect(fixture.manager.controllers[missing.normalizedPathKey] == nil)
        fixture.closeAll()
    }

    @Test("保存済みタブ構成が無ければルートフォルダをサイドバー表示で開く")
    func openRepositoryFallsBackToFolderWhenNoSavedTabGroup() {
        let root = URL(fileURLWithPath: "/repo")
        let entry = URL(fileURLWithPath: "/repo/a.md")
        let fixture = MockedViewerWindowManager(files: [root, entry], prefix: "SessionRestorerOpenRepo")
        let restorer = makeRestorer(fixture)

        restorer.openRepository(root: root, savedTabGroup: nil)

        #expect(fixture.manager.controllers[root.normalizedPathKey] != nil)
        fixture.closeAll()
    }

    @Test("保存済みタブ構成の全パスが消えていればルートフォルダにフォールバックする")
    func openRepositoryFallsBackToFolderWhenAllSavedPathsAreMissing() {
        let root = URL(fileURLWithPath: "/repo")
        let fixture = MockedViewerWindowManager(files: [root], prefix: "SessionRestorerOpenRepo")
        let restorer = makeRestorer(fixture)
        let group = SessionLayout.TabGroup(
            paths: [URL(fileURLWithPath: "/repo/gone.md").normalizedPathKey], selectedPath: nil
        )

        restorer.openRepository(root: root, savedTabGroup: group)

        #expect(fixture.manager.controllers[root.normalizedPathKey] != nil)
        fixture.closeAll()
    }
```

`MockedViewerWindowManager(files:)` はディレクトリの区別を持たない(InMemoryFileReader は常に `isDirectory(at:) == false`)ため、`root` をそのまま `files` に含めれば `fileReader.fileExists(at: root) == true` となり `ViewerWindowManager.openViewer(for: root, ...)` のガードを通過できる(フォールバック検証用)。

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter SessionRestorerTests`
Expected: FAIL(`openRepository` が存在せずビルドエラー)

- [ ] **Step 3: 実装する**

`BefoldApp/befold/App/SessionRestorer.swift` の `restoreLastSession` メソッドの直後に以下を追加する:

```swift
    /// 「最近使ったリポジトリ」から選ばれたリポジトリを開く。
    /// savedTabGroup があり実在するパスが残っていればタブ構成ごと復元し、
    /// 無い/全て消えている場合はルートフォルダをサイドバー表示で開くフォールバックへ縮退する。
    func openRepository(
        root: URL, savedTabGroup: SessionLayout.TabGroup?, options: CLIOpenOptions = CLIOpenOptions()
    ) {
        guard let savedTabGroup else {
            windowManager.openViewer(for: root, forceSidebarVisible: true)
            return
        }
        let existingPaths = Set(savedTabGroup.paths.filter { path in
            fileReader.isExistingFile(at: URL(fileURLWithPath: path))
        })
        let filtered = SessionLayout(groups: [savedTabGroup]).filtered(to: existingPaths)
        guard let group = filtered.groups.first else {
            windowManager.openViewer(for: root, forceSidebarVisible: true)
            return
        }
        let urlByPath = Dictionary(uniqueKeysWithValues: group.paths.map { ($0, URL(fileURLWithPath: $0)) })
        restoreTabGroup(group, urlByPath: urlByPath, options: options)
    }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter SessionRestorerTests`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
cd BefoldApp
git add befold/App/SessionRestorer.swift befoldTests/SessionRestorerTests.swift
git commit -m "feat: SessionRestorer.openRepository を追加する"
```

---

### Task 8: AppDelegate を配線する

**Files:**
- Modify: `BefoldApp/befold/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `RecentRepositoriesStore`(Task 2)、`RecentRepositoriesMenuController`(Task 3)、`MainMenuBuilder.build(...)`(Task 4、`recentRepositoriesMenuDelegate` 引数)、`ViewerWindowManager.init(...)`(Task 6、`recentRepositoriesStore` 引数)、`SessionRestorer.openRepository(root:savedTabGroup:)`(Task 7)

AppDelegate に対する自動テストは存在しない(`befoldTests/` に `AppDelegate*Tests.swift` は無い)ため、このタスクはビルド成功と手動スモークで検証する。

- [ ] **Step 1: 実装する**

`BefoldApp/befold/App/AppDelegate.swift` を編集する。

プロパティ追加。`private let bookmarkStore: BookmarkStore` の直後に追加:

```swift
    private let recentDocumentsStore: RecentDocumentsStore
    private let bookmarkStore: BookmarkStore
    private let recentRepositoriesStore: RecentRepositoriesStore
```

`lazy var bookmarksMenuController = ...` の直後に追加:

```swift
    private lazy var bookmarksMenuController = BookmarksMenuController(
        bookmarkedURLs: { [weak self] in self?.bookmarkStore.bookmarkedURLs() ?? [] },
        openHandler: { [weak self] url in self?.openViewer(for: url) }
    )
    private lazy var recentRepositoriesMenuController = RecentRepositoriesMenuController(
        pruneMissing: { [weak self] in self?.recentRepositoriesStore.pruneMissing() },
        entries: { [weak self] in self?.recentRepositoriesStore.entries() ?? [] },
        openHandler: { [weak self] entry in
            self?.sessionRestorer.openRepository(root: entry.root, savedTabGroup: entry.lastTabGroup)
        },
        clearHandler: { [weak self] in self?.recentRepositoriesStore.clear() }
    )
```

`override init()` を編集。`let bookmarkStore = BookmarkStore(defaults: .standard)` の直後に追加:

```swift
        let bookmarkStore = BookmarkStore(defaults: .standard)
        let recentRepositoriesStore = RecentRepositoriesStore()
```

`ViewerWindowManager(...)` の呼び出しに引数追加(`bookmarkStore: bookmarkStore` の直後):

```swift
        let windowManager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: recentDocumentsStore,
            hiddenFilesPreference: hiddenFilesPreference,
            findOptionsPreference: findOptionsPreference,
            codeFontPreference: codeFontPreference,
            perFileState: perFileState,
            bookmarkStore: bookmarkStore,
            recentRepositoriesStore: recentRepositoriesStore
        )
```

`self.bookmarkStore = bookmarkStore` の直後に追加:

```swift
        self.bookmarkStore = bookmarkStore
        self.recentRepositoriesStore = recentRepositoriesStore
```

`applicationDidFinishLaunching` 内の `MainMenuBuilder.build(...)` 呼び出しに引数追加:

```swift
        NSApp.mainMenu = MainMenuBuilder.build(
            openAction: #selector(showOpenPanel),
            helpAction: #selector(openHelp(_:)),
            recentMenuDelegate: recentDocumentsMenuController,
            bookmarksMenuDelegate: bookmarksMenuController,
            recentRepositoriesMenuDelegate: recentRepositoriesMenuController
        )
```

- [ ] **Step 2: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: 成功(Task 4 で確認した未解消のビルドエラーもここで解消される)

- [ ] **Step 3: 全テストスイートを実行する**

Run: `cd BefoldApp && swift test`
Expected: PASS(全件)

- [ ] **Step 4: 手動スモークテスト**

`/run` スキル(または `xcodebuild build -scheme befold` → 起動)でアプリを起動し、以下を目視確認する:

1. git 管理下のファイルを開く → File > Recent Repositories にそのリポジトリ名が表示される
2. `git worktree add` で作った worktree 内のファイルを開く → `"<本体名> (<worktree ディレクトリ名>)"` の形式でメニューに表示される
3. 同じリポジトリで複数タブを開いてからウィンドウを閉じる → File > Recent Repositories から選び直すと、閉じた時のタブ構成(複数タブ・選択タブ)が復元される
4. 一度も開いていないファイルだけのフォルダを開く(タブ構成の記憶なし)→ Recent Repositories から選ぶとルートフォルダがサイドバー表示で開く
5. worktree を `git worktree remove` で削除した後、File メニューを開く → 一覧からそのエントリが消えている(Clear Menu 以外は表示されないケースも含め確認)
6. Recent Repositories の Clear Menu → 一覧が空になる
7. 非 git ファイルだけを開いても Recent Repositories に何も追加されない

Expected: 上記すべてが設計どおりに動作する。ズレがあれば該当 Task に戻って修正する。

- [ ] **Step 5: コミット**

```bash
cd BefoldApp
git add befold/App/AppDelegate.swift
git commit -m "feat: AppDelegate に Recent Repositories を配線する"
```

---

## Self-Review 済みの確認事項

- **spec カバレッジ**: task-190 の AC #1(自動記憶)→ Task 6、#2(タブ復元/フォールバック)→ Task 7、#3(本体/worktree 区別)→ Task 1・3、#4(重複排除・上限・順序)→ Task 2、#5(非 git は記録しない)→ Task 6、#6(再起動をまたぐ永続化)→ Task 2(UserDefaults JSON)、#7(close 毎の更新)→ Task 6、#8(一部/全部消失時の縮退)→ Task 7 で、それぞれ対応済み。
- **プレースホルダー**: 各タスクのテスト・実装コードは全て具体的な内容を記載済み(TBD/TODO 無し)。
- **型・シグネチャの一貫性**: `RecentRepositoryEntry`(rootPath/label/lastTabGroup/root)、`RecentRepositoriesStore`(record/updateLastTabGroup/entries/pruneMissing/clear)、`RecentRepositoriesMenuController`(pruneMissing/entries/openHandler/clearHandler)、`SessionRestorer.openRepository(root:savedTabGroup:options:)`、`ViewerWindowController.repositoryRoot` の名称・型は全タスクで統一している。

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-30-recent-repositories-menu.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
