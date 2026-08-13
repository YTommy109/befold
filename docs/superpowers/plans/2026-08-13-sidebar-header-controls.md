# サイドバーヘッダーのコントロール整理 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** サイドバーヘッダーの操作を「左＝一覧の形（表示形式）／右＝絞り込み（変更のみ・名前フィルター）＋ ⋯ オーバーフロー（ソート順・不可視ファイル）」へ再構成し、⌃⌘T の表示形式切替にボタンを与える。

**Architecture:** 「どのボタンをどこに、どの見た目で出すか」の判定を SwiftUI ビューから純粋な値型 `SidebarHeaderControlsModel` へ切り出し、ビューはその配列を描くだけにする。表示形式ボタンは新しい切替経路を作らず、⌃⌘T と同じ `GlobalDisplayBroadcaster.toggleSidebarLayoutMode()` へ delegate 経由で合流させる。ゲート付きボタンは既存の「optional クロージャが nil なら出さない」形（`makeChangedFilesOnlyToggle`）に揃える。

**Tech Stack:** Swift 6 / SwiftUI + AppKit / Swift Testing / XcodeGen

## Global Constraints

設計の出典は `docs/superpowers/specs/2026-08-13-sidebar-header-controls-design.md`。以下は全タスクに適用される。

- 作業ツリーは現在の worktree（`git rev-parse --show-toplevel`）の内側のみ。外のパスへは一切アクセスしない。
- コミット規約は Conventional Commits + 日本語。**FeatureGate 配下の変更を含むコミットには `(gate)` スコープを付ける**（例: `feat(gate): ...`）。表示形式ボタンは `FeatureGate.isSidebarTreeEnabled` 配下なので該当する。
- `befold` ターゲット配下で `FeatureGate.` を直接参照してよいのは `.swiftlint.yml` の `excluded` に列挙された配線点だけ。**本計画では新しい参照ファイルを増やさない**（既存の `ViewerWindowAssembler.swift` の中だけでゲート値を読む）。allowlist と `FeatureGate.swift` の doc を触る必要はない。
- ソート順の永続化は**スコープ外**。`FileListModel.sortOrder` 直書き・非永続のまま変えない（Task 4 でフォローアップを起票する）。
- 新規ファイルを追加したら `cd BefoldApp && xcodegen generate` を実行する（`swift build` は通っても `xcodebuild` が落ちる）。
- テスト関数名は英語 camelCase、日本語の説明は `@Test("...")` の表示名で付ける。
- `Localizable.xcstrings` に文字列を追加するときはキー順にソートし直さない。既存の並びを保ち、近縁キーの直後に挿入する。
- swiftformat / swiftlint が衝突したら手で往復しない。`cd BefoldApp && swift package plugin --allow-writing-to-package-directory swiftformat` を回して機械に決めさせる。

---

### Task 1: SidebarHeaderControlsModel（表示判定の値型）

「どのボタンを、どの順で、どのアイコン・どの help・アクセントの有無で出すか」を決める純粋な値型を作る。SwiftUI ビューは自動テスト対象外という規約があるため、判定はここに閉じ込めてユニットテストで固定する。

**Files:**

- Create: `BefoldApp/befold/Viewer/SidebarHeaderControlsModel.swift`
- Test: `BefoldApp/befoldTests/SidebarHeaderControlsModelTests.swift`

**Interfaces:**

- Consumes: `SidebarLayoutMode`（`BefoldApp/befold/App/SidebarLayoutMode.swift:8`、`.drillDown` / `.tree`）、`SortOrder`（`BefoldKit`、`.foldersFirst` / `.alphabetical`）
- Produces:
  - `struct SidebarHeaderControl: Equatable` — `kind: SidebarHeaderControl.Kind`, `systemImage: String`, `helpKey: String`, `isAccented: Bool`
  - `enum SidebarHeaderControl.Kind: Hashable` — `layoutMode` / `changedFilesOnly` / `filter` / `overflow`
  - `struct SidebarOverflowItem: Equatable` — `kind: SidebarOverflowItem.Kind`, `titleKey: String`, `isChecked: Bool`
  - `enum SidebarOverflowItem.Kind: Hashable` — `sortFoldersFirst` / `sortAlphabetical` / `hiddenFiles`
  - `struct SidebarHeaderControlsModel: Equatable` — `leading: [SidebarHeaderControl]`, `trailing: [SidebarHeaderControl]`, `overflowItems: [SidebarOverflowItem]`、および下記のイニシャライザ

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/SidebarHeaderControlsModelTests.swift` を新規作成する。

```swift
@testable import befold
import BefoldKit
import Testing

/// サイドバーヘッダーの操作行の構成（左右の群・並び・アクセント）を固定する。
/// SwiftUI ビューは自動テスト対象外のため、判定はこの値型に閉じ込めて検証する
/// (TASK-410、設計は docs/superpowers/specs/2026-08-13-sidebar-header-controls-design.md)。
@Suite
struct SidebarHeaderControlsModelTests {
    private func makeModel(
        layoutMode: SidebarLayoutMode = .drillDown,
        sortOrder: SortOrder = .foldersFirst,
        showHiddenFiles: Bool = false,
        showChangedFilesOnly: Bool = false,
        isFilterActive: Bool = false,
        isFilterTextEmpty: Bool = true,
        isTreeLayoutAvailable: Bool = true,
        isChangedFilesOnlyAvailable: Bool = true
    ) -> SidebarHeaderControlsModel {
        SidebarHeaderControlsModel(
            layoutMode: layoutMode,
            sortOrder: sortOrder,
            showHiddenFiles: showHiddenFiles,
            showChangedFilesOnly: showChangedFilesOnly,
            isFilterActive: isFilterActive,
            isFilterTextEmpty: isFilterTextEmpty,
            isTreeLayoutAvailable: isTreeLayoutAvailable,
            isChangedFilesOnlyAvailable: isChangedFilesOnlyAvailable
        )
    }

    /// 左右分割そのものを固定する。doc コメントだけでは次のボタン追加で崩れるため、
    /// 並びを配列比較で押さえる（設計「テスト」節の 4 番）。
    @Test("ゲート ON では左が表示形式、右が変更のみ・フィルター・⋯ の順になる")
    func groupsSplitFormFromFiltering() {
        let model = makeModel()

        #expect(model.leading.map(\.kind) == [.layoutMode])
        #expect(model.trailing.map(\.kind) == [.changedFilesOnly, .filter, .overflow])
    }

    /// 実ビルドではゲートが片側に固定されるため、両方向を注入点で見る。
    @Test("表示形式ボタンの有無はゲートと一致する", arguments: [true, false])
    func layoutModeControlFollowsGate(isTreeLayoutAvailable: Bool) {
        let model = makeModel(isTreeLayoutAvailable: isTreeLayoutAvailable)

        #expect(model.leading.isEmpty == !isTreeLayoutAvailable)
    }

    @Test("変更のみボタンの有無はゲートと一致する", arguments: [true, false])
    func changedFilesOnlyControlFollowsGate(isChangedFilesOnlyAvailable: Bool) {
        let model = makeModel(isChangedFilesOnlyAvailable: isChangedFilesOnlyAvailable)

        let hasChangedFilesOnly = model.trailing.contains { $0.kind == .changedFilesOnly }
        #expect(hasChangedFilesOnly == isChangedFilesOnlyAvailable)
        // ゲート OFF でもフィルターと ⋯ は残る（stable でヘッダーが空にならない）。
        #expect(model.trailing.map(\.kind).suffix(2) == [.filter, .overflow])
    }

    @Test("表示形式のアイコンは現在のモードを表す", arguments: [
        (SidebarLayoutMode.tree, "list.bullet.indent"),
        (SidebarLayoutMode.drillDown, "list.bullet"),
    ])
    func layoutModeIconReflectsMode(mode: SidebarLayoutMode, expected: String) {
        let model = makeModel(layoutMode: mode)

        #expect(model.leading.first?.systemImage == expected)
    }

    /// 畳んだ絞り込み（不可視ファイル）が効いていることは ⋯ のアクセントだけが伝える。
    /// これが破れると、一覧にドットファイルが並ぶ理由がヘッダーから消える。
    @Test("⋯ は不可視ファイル ON のとき、かつそのときだけアクセントになる", arguments: [true, false])
    func overflowIsAccentedOnlyWhenHiddenFilesShown(showHiddenFiles: Bool) {
        let model = makeModel(showHiddenFiles: showHiddenFiles)

        let overflow = model.trailing.first { $0.kind == .overflow }
        #expect(overflow?.isAccented == showHiddenFiles)
    }

    /// ソート順は「常にどちらか」なのでアクセント対象にしない（設計「状態の見え方」節）。
    @Test("ソート順を変えても ⋯ のアクセントは変わらない")
    func sortOrderDoesNotAccentOverflow() {
        let alphabetical = makeModel(sortOrder: .alphabetical)

        let overflow = alphabetical.trailing.first { $0.kind == .overflow }
        #expect(overflow?.isAccented == false)
    }

    @Test("⋯ の中身はソート順 2 択と不可視ファイルの順に並ぶ")
    func overflowItemsAreSortThenHiddenFiles() {
        let model = makeModel()

        #expect(model.overflowItems.map(\.kind) == [.sortFoldersFirst, .sortAlphabetical, .hiddenFiles])
    }

    @Test("⋯ のチェックは現在のソート順の側に付く", arguments: [
        (SortOrder.foldersFirst, [true, false]),
        (SortOrder.alphabetical, [false, true]),
    ])
    func overflowChecksFollowSortOrder(sortOrder: SortOrder, expected: [Bool]) {
        let model = makeModel(sortOrder: sortOrder)

        let sortItems = model.overflowItems.filter { $0.kind != .hiddenFiles }
        #expect(sortItems.map(\.isChecked) == expected)
    }

    @Test("⋯ の不可視ファイル項目のチェックは現在値と一致する", arguments: [true, false])
    func hiddenFilesItemIsCheckedWhenShown(showHiddenFiles: Bool) {
        let model = makeModel(showHiddenFiles: showHiddenFiles)

        let item = model.overflowItems.first { $0.kind == .hiddenFiles }
        #expect(item?.isChecked == showHiddenFiles)
    }

    /// フィルターは「入力があるか」でアクセント、「開いているか」で help が変わる。
    /// 既存の SidebarHeaderView の振る舞いを保つ（アイコンも .fill へ切り替わる）。
    @Test("フィルターは入力があるときアクセントになる", arguments: [true, false])
    func filterIsAccentedWhenTextPresent(isFilterTextEmpty: Bool) {
        let model = makeModel(isFilterActive: true, isFilterTextEmpty: isFilterTextEmpty)

        let filter = model.trailing.first { $0.kind == .filter }
        #expect(filter?.isAccented == !isFilterTextEmpty)
        #expect(filter?.systemImage == (isFilterTextEmpty
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"))
    }

    @Test("フィルターの help は開閉状態で入れ替わる", arguments: [true, false])
    func filterHelpFollowsOpenState(isFilterActive: Bool) {
        let model = makeModel(isFilterActive: isFilterActive)

        let filter = model.trailing.first { $0.kind == .filter }
        #expect(filter?.helpKey == (isFilterActive ? "sidebar.filter.hide" : "sidebar.filter.show"))
    }

    @Test("変更のみは ON のときアクセントになる", arguments: [true, false])
    func changedFilesOnlyIsAccentedWhenOn(showChangedFilesOnly: Bool) {
        let model = makeModel(showChangedFilesOnly: showChangedFilesOnly)

        let control = model.trailing.first { $0.kind == .changedFilesOnly }
        #expect(control?.isAccented == showChangedFilesOnly)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter SidebarHeaderControlsModelTests`
Expected: コンパイルエラー（`cannot find 'SidebarHeaderControlsModel' in scope`）で失敗する。

- [ ] **Step 3: 値型を実装する**

`BefoldApp/befold/Viewer/SidebarHeaderControlsModel.swift` を新規作成する。

```swift
import BefoldKit
import Foundation

/// ヘッダー操作行に出すボタン 1 個分の記述。
struct SidebarHeaderControl: Equatable {
    /// ボタンの種類。ビューはこれを見て押したときの動作を選ぶ。
    /// ForEach の id に使うため Hashable にする。
    enum Kind: Hashable {
        /// 一覧の形（ツリー / ドリルダウン）。左群に単独で置く。
        case layoutMode
        case changedFilesOnly
        case filter
        /// ソート順・不可視ファイルを畳んだオーバーフローメニュー。
        case overflow
    }

    let kind: Kind
    let systemImage: String
    /// help(ツールチップ)のローカライズキー。
    let helpKey: String
    /// 絞り込みが効いていることをアクセント色で示すか。
    let isAccented: Bool
}

/// オーバーフローメニュー 1 項目分の記述。
struct SidebarOverflowItem: Equatable {
    /// ForEach の id に使うため Hashable にする。
    enum Kind: Hashable {
        case sortFoldersFirst
        case sortAlphabetical
        case hiddenFiles
    }

    let kind: Kind
    let titleKey: String
    let isChecked: Bool
}

/// サイドバーヘッダーの操作行の構成を決める値型。
///
/// **左群は「一覧の形」、右群は「絞り込み」**という分割が設計上の判断で、位置がその
/// 系統を表している(設計: docs/superpowers/specs/2026-08-13-sidebar-header-controls-design.md)。
/// 並び順は `SidebarHeaderControlsModelTests` が配列比較で固定しているので、ボタンを
/// 足すときはどちらの群に属するかを先に決めること。
///
/// **⋯ に入れてよいのは「サイドバーの一覧の見え方に効く設定で、常設に値しないもの」だけ。**
/// ファイル操作・ウィンドウ操作は入れない。何でも入る箱にすると、畳んだこと自体が
/// 新しい散らかりになる。
///
/// ゲート値はここでは読まず引数で受ける(`befold` ターゲットでの `FeatureGate.` 直接参照は
/// swiftlint の custom rule で禁じられており、配線点は ViewerWindowAssembler)。
struct SidebarHeaderControlsModel: Equatable {
    /// 左群(フォルダー名の左)。
    let leading: [SidebarHeaderControl]
    /// 右群(フォルダー名の右)。
    let trailing: [SidebarHeaderControl]
    /// ⋯ を開いたときの項目。
    let overflowItems: [SidebarOverflowItem]

    init(
        layoutMode: SidebarLayoutMode,
        sortOrder: SortOrder,
        showHiddenFiles: Bool,
        showChangedFilesOnly: Bool,
        isFilterActive: Bool,
        isFilterTextEmpty: Bool,
        isTreeLayoutAvailable: Bool,
        isChangedFilesOnlyAvailable: Bool
    ) {
        leading = Self.leadingControls(layoutMode: layoutMode, isTreeLayoutAvailable: isTreeLayoutAvailable)
        trailing = Self.trailingControls(
            showHiddenFiles: showHiddenFiles,
            showChangedFilesOnly: showChangedFilesOnly,
            isFilterActive: isFilterActive,
            isFilterTextEmpty: isFilterTextEmpty,
            isChangedFilesOnlyAvailable: isChangedFilesOnlyAvailable
        )
        overflowItems = Self.overflowItems(sortOrder: sortOrder, showHiddenFiles: showHiddenFiles)
    }

    private static func leadingControls(
        layoutMode: SidebarLayoutMode, isTreeLayoutAvailable: Bool
    ) -> [SidebarHeaderControl] {
        guard isTreeLayoutAvailable else { return [] }
        let isTree = layoutMode == .tree
        return [
            SidebarHeaderControl(
                kind: .layoutMode,
                // アイコン自体がモードを表すため、アクセントでは示さない。
                systemImage: isTree ? "list.bullet.indent" : "list.bullet",
                helpKey: isTree ? "sidebar.layout.drillDown" : "sidebar.layout.tree",
                isAccented: false
            ),
        ]
    }

    private static func trailingControls(
        showHiddenFiles: Bool,
        showChangedFilesOnly: Bool,
        isFilterActive: Bool,
        isFilterTextEmpty: Bool,
        isChangedFilesOnlyAvailable: Bool
    ) -> [SidebarHeaderControl] {
        var controls: [SidebarHeaderControl] = []
        if isChangedFilesOnlyAvailable {
            controls.append(SidebarHeaderControl(
                kind: .changedFilesOnly,
                systemImage: "arrow.triangle.branch",
                helpKey: showChangedFilesOnly
                    ? "sidebar.changedFilesOnly.hide"
                    : "sidebar.changedFilesOnly.show",
                isAccented: showChangedFilesOnly
            ))
        }
        controls.append(SidebarHeaderControl(
            kind: .filter,
            systemImage: isFilterTextEmpty
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill",
            helpKey: isFilterActive ? "sidebar.filter.hide" : "sidebar.filter.show",
            isAccented: !isFilterTextEmpty
        ))
        controls.append(SidebarHeaderControl(
            kind: .overflow,
            systemImage: "ellipsis.circle",
            helpKey: "sidebar.more",
            // 畳んだ絞り込みが効いていることを伝える唯一の手掛かり。
            isAccented: showHiddenFiles
        ))
        return controls
    }

    private static func overflowItems(
        sortOrder: SortOrder, showHiddenFiles: Bool
    ) -> [SidebarOverflowItem] {
        [
            SidebarOverflowItem(
                kind: .sortFoldersFirst,
                titleKey: "sidebar.sortOrder.foldersFirst",
                isChecked: sortOrder == .foldersFirst
            ),
            SidebarOverflowItem(
                kind: .sortAlphabetical,
                titleKey: "sidebar.sortOrder.alphabetical",
                isChecked: sortOrder == .alphabetical
            ),
            SidebarOverflowItem(
                kind: .hiddenFiles,
                titleKey: "menu.view.showHiddenFiles",
                isChecked: showHiddenFiles
            ),
        ]
    }
}
```

- [ ] **Step 4: プロジェクトを再生成してテストが通ることを確認する**

Run: `cd BefoldApp && xcodegen generate && swift test --filter SidebarHeaderControlsModelTests`
Expected: 全テスト PASS。

- [ ] **Step 5: コミットする**

```bash
cd BefoldApp && swift package plugin --allow-writing-to-package-directory swiftformat
cd .. && git add BefoldApp/befold/Viewer/SidebarHeaderControlsModel.swift \
  BefoldApp/befoldTests/SidebarHeaderControlsModelTests.swift BefoldApp/befold.xcodeproj
git commit -m "feat(gate): サイドバーヘッダーの操作行の構成を値型へ切り出す"
```

---

### Task 2: 表示形式トグルの配線

表示形式ボタンから ⌃⌘T と同じ経路へ合流させる。**新しい切替経路は作らない**（ボタン専用の経路を足すと、メニュー経由とボタン経由で確定タイミングがずれる型を再生産する）。ゲート付きの露出は `makeChangedFilesOnlyToggle` と同型にする。

**Files:**

- Modify: `BefoldApp/befold/App/ViewerWindowControllerDelegate.swift:24`（`viewerWindowDidToggleChangedFilesOnly` の直後に追加）
- Modify: `BefoldApp/befold/App/ViewerWindowManager+SessionSync.swift:81-83`（実装を追加）
- Modify: `BefoldApp/befold/App/ViewerWindowAssembler.swift:134-165`（`makeFileListView` に引数追加、`makeSidebarTreeLayoutToggle` を新設）
- Modify: `BefoldApp/befold/Viewer/FileListView.swift:14`（受け口を追加して `SidebarHeaderView` へ渡す）
- Modify: `BefoldApp/befold/Viewer/SidebarHeaderView.swift:20`（受け口を追加。この時点では未使用でよい）
- Modify: `BefoldApp/befoldTests/ViewerWindowControllerTestSupport.swift:50-52`（スタブに新メソッドを追加）
- Test: `BefoldApp/befoldTests/ViewerWindowAssemblerGateTests.swift:66`（末尾にテストを追加）

**Interfaces:**

- Consumes: `SidebarHeaderControlsModel`（Task 1。この Task では参照しない）
- Produces:
  - `ViewerWindowControllerDelegate.viewerWindowDidToggleSidebarTreeLayout(_ controller: ViewerWindowController)`
  - `static func ViewerWindowAssembler.makeSidebarTreeLayoutToggle(for: ViewerWindowController, isTreeLayoutAvailable: Bool = FeatureGate.isSidebarTreeEnabled) -> (() -> Void)?`
  - `FileListView.onToggleSidebarTreeLayout: (() -> Void)?` と `SidebarHeaderView.onToggleSidebarTreeLayout: (() -> Void)?`（Task 3 が使う）

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/ViewerWindowAssemblerGateTests.swift` の末尾（`:66` の閉じ括弧の直前）へ追加する。

```swift
    /// ゲート OFF ではサイドバーヘッダーの表示形式ボタンが出ない。
    /// 「変更されたファイルのみ表示」と同型の露出点にしている(TASK-410)。
    @Test("表示形式のトグルはゲートの両方向で正しい", arguments: [true, false])
    func sidebarTreeLayoutToggleFollowsGateInBothDirections(isTreeLayoutAvailable: Bool) {
        let controller = ViewerWindowControllerFixture(
            file: URL(fileURLWithPath: "/mock/a.mmd"),
            prefix: "ViewerWindowAssemblerGateTests"
        ).controller
        defer { controller.close() }

        let toggle = ViewerWindowAssembler.makeSidebarTreeLayoutToggle(
            for: controller, isTreeLayoutAvailable: isTreeLayoutAvailable
        )

        #expect((toggle != nil) == isTreeLayoutAvailable)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowAssemblerGateTests`
Expected: コンパイルエラー（`type 'ViewerWindowAssembler' has no member 'makeSidebarTreeLayoutToggle'`）で失敗する。

- [ ] **Step 3: delegate に通知口を足す**

`BefoldApp/befold/App/ViewerWindowControllerDelegate.swift` の `viewerWindowDidToggleChangedFilesOnly` の直後（`:24`）へ追加する。

```swift
    /// サイドバーの表示形式(ツリー / ドリルダウン)が切り替えられたことを伝える。
    /// メニューの ⌃⌘T と同じ経路へ合流させるための口で、ボタン専用の切替は持たない。
    func viewerWindowDidToggleSidebarTreeLayout(_ controller: ViewerWindowController)
```

`BefoldApp/befold/App/ViewerWindowManager+SessionSync.swift` の `viewerWindowDidToggleChangedFilesOnly`（`:81-83`）の直後へ実装を追加する。

```swift
    func viewerWindowDidToggleSidebarTreeLayout(_ controller: ViewerWindowController) {
        display.toggleSidebarLayoutMode()
    }
```

`BefoldApp/befoldTests/ViewerWindowControllerTestSupport.swift` の `viewerWindowDidToggleChangedFilesOnly`（`:50-52`）の直後へスタブを追加する。同じ型の既存プロパティ（`toggleChangedFilesOnlyCalled`）に倣い、プロパティ宣言も同じ場所へ足すこと。

```swift
    func viewerWindowDidToggleSidebarTreeLayout(_ controller: ViewerWindowController) {
        toggleSidebarTreeLayoutCalled = true
    }
```

- [ ] **Step 4: 露出点（ゲート）と配線を足す**

`BefoldApp/befold/App/ViewerWindowAssembler.swift` の `makeChangedFilesOnlyToggle`（`:157-165`）の直後へ追加する。

```swift
    /// サイドバーヘッダーの表示形式(ツリー / ドリルダウン)ボタンの動作を作る。
    ///
    /// 無効なら nil を返してボタン自体を出さない(FileListView 側が nil で非表示にする)。
    /// 切替の実体はメニューの ⌃⌘T と同じ `GlobalDisplayBroadcaster.toggleSidebarLayoutMode()`
    /// で、ここは delegate へ流すだけ。ボタン専用の経路を持たせない。
    /// - Parameter isTreeLayoutAvailable: ゲート値。テストから ON/OFF 両方向を
    ///   確かめられるよう引数で受ける(テストから呼ぶため internal)。
    static func makeSidebarTreeLayoutToggle(
        for controller: ViewerWindowController,
        isTreeLayoutAvailable: Bool = FeatureGate.isSidebarTreeEnabled
    ) -> (() -> Void)? {
        guard isTreeLayoutAvailable else { return nil }
        return { [weak controller] in
            guard let controller else { return }
            controller.delegate?.viewerWindowDidToggleSidebarTreeLayout(controller)
        }
    }
```

同ファイルの `makeFileListView`（`:134-148`）の `onToggleChangedFilesOnly:` の次の行へ引数を足す。

```swift
            onToggleSidebarTreeLayout: makeSidebarTreeLayoutToggle(for: controller)
```

`BefoldApp/befold/Viewer/FileListView.swift` の `onToggleChangedFilesOnly`（`:14`）の直後へ受け口を足す。

```swift
    /// nil のときはヘッダーに表示形式(ツリー / ドリルダウン)のボタンを出さない。
    /// 開発中機能の露出点(ViewerWindowAssembler が FeatureGate で決める)。
    var onToggleSidebarTreeLayout: (() -> Void)?
```

同ファイルの `SidebarHeaderView(...)` 呼び出し（`:18-23`）へ `onToggleSidebarTreeLayout: onToggleSidebarTreeLayout` を追加し、`BefoldApp/befold/Viewer/SidebarHeaderView.swift` の `onToggleChangedFilesOnly`（`:20`）の直後にも同名の受け口を足す（Task 3 で使う。この時点では未使用のままでよい）。

```swift
    /// nil のときは表示形式(ツリー / ドリルダウン)のボタンを出さない。
    /// 開発中機能の露出点(ViewerWindowAssembler が FeatureGate で決める)。
    var onToggleSidebarTreeLayout: (() -> Void)?
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowAssemblerGateTests`
Expected: 全テスト PASS（新しい `表示形式のトグルはゲートの両方向で正しい` を含む）。

- [ ] **Step 6: コミットする**

```bash
cd BefoldApp && swift package plugin --allow-writing-to-package-directory swiftformat
cd .. && git add BefoldApp/befold/App BefoldApp/befold/Viewer BefoldApp/befoldTests
git commit -m "feat(gate): サイドバーの表示形式トグルを ⌃⌘T と同じ経路へ配線する"
```

---

### Task 3: ヘッダーの描画を差し替える

判定（Task 1）と配線（Task 2）が揃ったので、ヘッダーの見た目を左右分割へ差し替える。ソート順と不可視ファイルのボタンは ⋯ メニューへ移す。

**Files:**

- Create: `BefoldApp/befold/Viewer/SidebarHeaderControls.swift`
- Modify: `BefoldApp/befold/Viewer/SidebarHeaderView.swift:65-139`（`navigationHeader` を置き換え、`sortOrderButton` / `hiddenFilesButton` / `changedFilesOnlyButton` / `filterButton` を削除）
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`

**Interfaces:**

- Consumes: `SidebarHeaderControlsModel` / `SidebarHeaderControl` / `SidebarOverflowItem`（Task 1）、`SidebarHeaderView.onToggleSidebarTreeLayout`（Task 2）
- Produces: `struct SidebarHeaderControls: View` — `model: FileListModel`, `controls: SidebarHeaderControlsModel`, `placement: SidebarHeaderControls.Placement`（`.leading` / `.trailing`）, および各アクションのクロージャ（オーバーフロー項目は `controls.overflowItems` から読むので別引数にしない）

- [ ] **Step 1: ローカライズ文字列を足す**

`BefoldApp/befold/Resources/Localizable.xcstrings` に 5 キーを追加する。**キー順にソートし直さない**。`sidebar.filter.*` / `sidebar.sort.*` の近くへ挿入する。

| キー | en | ja |
| --- | --- | --- |
| `sidebar.layout.tree` | `Show as Tree` | `ツリー表示にする` |
| `sidebar.layout.drillDown` | `Show One Level at a Time` | `1 階層ずつ表示する` |
| `sidebar.more` | `Display Options` | `表示オプション` |
| `sidebar.sortOrder.foldersFirst` | `Folders First` | `フォルダーを先に` |
| `sidebar.sortOrder.alphabetical` | `Alphabetical` | `名前順` |

各エントリは既存と同じ形にする（例）。

```json
    "sidebar.more" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Display Options"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "表示オプション"
          }
        }
      }
    },
```

- [ ] **Step 2: 操作行のビューを作る**

`BefoldApp/befold/Viewer/SidebarHeaderControls.swift` を新規作成する。

```swift
import BefoldKit
import SwiftUI

/// サイドバーヘッダーの操作行のボタン群。
///
/// 何をどこに出すかは `SidebarHeaderControlsModel` が決める。ここは受け取った記述を
/// 描いて、押されたら対応するクロージャを呼ぶだけにしてある(判定をビューに書くと
/// ユニットテストで固定できなくなる)。
struct SidebarHeaderControls: View {
    /// 左群と右群のどちらを描くか。
    enum Placement {
        case leading
        case trailing
    }

    let controls: SidebarHeaderControlsModel
    let placement: Placement
    let onToggleLayoutMode: (() -> Void)?
    let onToggleChangedFilesOnly: (() -> Void)?
    let onToggleFilter: () -> Void
    let onSelectOverflowItem: (SidebarOverflowItem.Kind) -> Void

    var body: some View {
        ForEach(items, id: \.kind) { control in
            switch control.kind {
            case .overflow:
                overflowMenu(control)
            default:
                button(control)
            }
        }
    }

    private var items: [SidebarHeaderControl] {
        placement == .leading ? controls.leading : controls.trailing
    }

    private func button(_ control: SidebarHeaderControl) -> some View {
        Button {
            action(for: control.kind)?()
        } label: {
            icon(control)
        }
        .buttonStyle(.borderless)
        .help(String(localized: String.LocalizationValue(control.helpKey), bundle: .l10n))
    }

    private func overflowMenu(_ control: SidebarHeaderControl) -> some View {
        Menu {
            ForEach(controls.overflowItems, id: \.kind) { item in
                Button {
                    onSelectOverflowItem(item.kind)
                } label: {
                    // チェックは Label ではなくテキスト側に持たせる(Menu 内の Toggle は
                    // 3 項目のうち 2 つが排他選択で意味がずれるため使わない)。
                    if item.isChecked {
                        Label(title(for: item), systemImage: "checkmark")
                    } else {
                        Text(title(for: item))
                    }
                }
            }
        } label: {
            icon(control)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: String.LocalizationValue(control.helpKey), bundle: .l10n))
    }

    private func icon(_ control: SidebarHeaderControl) -> some View {
        Image(systemName: control.systemImage)
            .foregroundStyle(control.isAccented ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }

    private func title(for item: SidebarOverflowItem) -> String {
        String(localized: String.LocalizationValue(item.titleKey), bundle: .l10n)
    }

    private func action(for kind: SidebarHeaderControl.Kind) -> (() -> Void)? {
        switch kind {
        case .layoutMode: onToggleLayoutMode
        case .changedFilesOnly: onToggleChangedFilesOnly
        case .filter: onToggleFilter
        case .overflow: nil
        }
    }
}
```

- [ ] **Step 3: ヘッダーを差し替える**

`BefoldApp/befold/Viewer/SidebarHeaderView.swift` の `navigationHeader`（`:65-77`）を置き換え、`sortOrderButton`（`:79-92`）・`hiddenFilesButton`（`:94-105`）・`changedFilesOnlyButton`（`:107-121`）・`filterButton`（`:123-139`）を削除する。`closeFilter()`（`:52-55`）はそのまま残す。

```swift
    private var controls: SidebarHeaderControlsModel {
        SidebarHeaderControlsModel(
            layoutMode: model.layoutMode,
            sortOrder: model.sortOrder,
            showHiddenFiles: model.showHiddenFiles,
            showChangedFilesOnly: model.showChangedFilesOnly,
            isFilterActive: model.isFilterActive,
            isFilterTextEmpty: model.filterText.isEmpty,
            isTreeLayoutAvailable: onToggleSidebarTreeLayout != nil,
            isChangedFilesOnlyAvailable: onToggleChangedFilesOnly != nil
        )
    }

    /// 左＝一覧の形、右＝絞り込み。位置がその系統を表しているので、ボタンを足すときは
    /// どちらの群かを先に決めること(並びは SidebarHeaderControlsModelTests が固定している)。
    private var navigationHeader: some View {
        HStack {
            headerControls(placement: .leading)
            Text(model.currentDirectory.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            headerControls(placement: .trailing)
        }
    }

    private func headerControls(placement: SidebarHeaderControls.Placement) -> some View {
        SidebarHeaderControls(
            controls: controls,
            placement: placement,
            onToggleLayoutMode: onToggleSidebarTreeLayout,
            onToggleChangedFilesOnly: onToggleChangedFilesOnly,
            onToggleFilter: toggleFilter,
            onSelectOverflowItem: selectOverflowItem
        )
    }

    private func toggleFilter() {
        if model.isFilterActive {
            closeFilter()
        } else {
            model.isFilterActive = true
        }
    }

    private func selectOverflowItem(_ kind: SidebarOverflowItem.Kind) {
        switch kind {
        case .sortFoldersFirst: onSortOrderChanged(.foldersFirst)
        case .sortAlphabetical: onSortOrderChanged(.alphabetical)
        case .hiddenFiles: onToggleHiddenFiles?()
        }
    }
```

- [ ] **Step 4: 使われなくなったローカライズキーを消す**

Run: `grep -rn "sidebar.sort.alphabetical\|sidebar.sort.foldersFirst\|sidebar.hiddenFiles.hide\|sidebar.hiddenFiles.show" BefoldApp/befold --include="*.swift"`
Expected: 0 件（`Localizable.xcstrings` 以外に参照が残らない）。0 件であることを確認してから、この 4 キーを `Localizable.xcstrings` から削除する。1 件でも残っていたら削除せず、参照元を先に直す。

- [ ] **Step 5: ビルドとテストを通す**

Run: `cd BefoldApp && xcodegen generate && swift test`
Expected: 全テスト PASS（1500 件超）。失敗したら要約行だけで判断せず、出力をファイルへ落として失敗したテスト名まで特定する。

- [ ] **Step 6: 実機で見た目を確認する**

Run: `cd BefoldApp && xcodebuild build -scheme befold -configuration Debug -derivedDataPath .build/xcode -quiet && open .build/xcode/Build/Products/Debug/befold.app`

確認する項目（dev ビルドなのでゲートは ON）:

1. ヘッダー左に表示形式アイコン、右に変更のみ・フィルター・⋯ が並ぶ
2. 表示形式ボタンで一覧がツリー / ドリルダウンに切り替わり、⌃⌘T と同じ結果になる
3. 複数ウィンドウを開いた状態で片方を切り替えると、もう片方も追従する
4. ⋯ を開くとソート順 2 択（現在値にチェック）と不可視ファイル（チェック）が出る
5. ⋯ 内で不可視ファイルを ON にすると ⋯ 自体がアクセント色になる
6. アプリを再起動しても表示形式とソート順の見え方が期待どおり（表示形式は復元される。**ソート順は非永続なので既定へ戻るのが正しい**）

- [ ] **Step 7: 翻訳漏れと lint を確認してコミットする**

```bash
cd BefoldApp && swift package plugin --allow-writing-to-package-directory swiftformat
./.build/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle/macos/swiftlint lint --quiet | grep -E "SidebarHeader"
cd .. && git add BefoldApp/befold BefoldApp/befold.xcodeproj
git commit -m "feat(gate): サイドバーヘッダーを左右分割し表示オプションを ⋯ へ畳む"
```

swiftlint の出力に `SidebarHeader*` が現れないこと（新規警告ゼロ）を確認してからコミットする。

---

### Task 4: 追従作業（ドキュメントとフォローアップ起票）

**Files:**

- Modify: `docs/dev/native-app-design.md`（サイドバー構成の記述がある場合のみ）
- Create: `backlog/tasks/task-<次の ID> - ....md`（`backlog` CLI 経由）

- [ ] **Step 1: 設計文書の記述を追従させる**

Run: `grep -rn "サイドバーヘッダー\|SidebarHeaderView" docs/dev/native-app-design.md`
ヒットした箇所があれば、左右分割と ⋯ の構成へ書き換える。ヒットしなければ何もしない（記述を新設しない — 詳細は spec 側が持つ）。

- [ ] **Step 2: ソート順の永続化をフォローアップとして起票する**

```bash
backlog task create "サイドバーのソート順を永続化する" \
  --desc "ソート順は現在 FileListModel.sortOrder 直書きでウィンドウごと・非永続。⋯ メニューへ移した(TASK-410)ことで設定らしい見た目になったが、再起動で既定へ戻る。UserDefaults へ永続化するなら、CLAUDE.md「UserDefaults キーの廃止・改名」の手順(移行経路を 1 本に畳む・defer での stale キー削除・3 ケースのテスト)に従うこと。" \
  --ac "サイドバーのソート順が再起動後も保たれる" \
  --ac "全ウィンドウで同じソート順になるか、窓ごとに独立かの判断が Implementation Notes に記録されている" \
  --priority low
```

- [ ] **Step 3: markdownlint を通してコミットする**

```bash
markdownlint-cli2
git add docs backlog
git commit -m "chore: サイドバーヘッダー整理の追従とソート順永続化を起票する"
```

---

## 完了の確認

すべてのタスク後に次を満たしていること。

- `cd BefoldApp && swift test` が全通過する
- `xcodebuild build -scheme befold -configuration Debug` が通る
- swiftlint の警告が main とのベースライン差分ゼロ（測り方は `/swiftlint-baseline`。`git stash` は使わない）
- Task 3 Step 6 の実機確認 6 項目が確認済み
