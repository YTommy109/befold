# サイドバーのスライドモード Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** プレゼン中にフォーカスをサイドバーへ残したままカーソルキーでファイルを送れるよう、サイドバーをアイコン幅に固定する「スライドモード」を追加する。

**Architecture:** 真値は `FileListModel.isSlideMode`（窓ごと・永続化しない）1 つ。`ViewerSplitViewController` は真偽値を持たず幅と autosave の制御だけを担う。メニューは窓ごとの状態なので `ViewerWindowController` + `ViewerMenuValidator` の系統に載せ、`AppDelegate.sidebarChange(for:)`（永続化される系統）には載せない。

**Tech Stack:** Swift 6 / AppKit（NSSplitViewController）+ SwiftUI / Swift Testing / XcodeGen

**Spec:** `docs/superpowers/specs/2026-09-04-sidebar-slide-mode-design.md`

## Global Constraints

- `minimumThickness` は 200 のまま変更しない。`maximumThickness` のみ 360 → 480。
- スライドモードの状態は永続化しない。`UserDefaults` へ書かない。
- サイドバーの開閉を自動で行わない（`SidebarStateStore.recordToggle` の汚染を避けるため）。
- 解除手段は「表示メニューのトグル」と「ヘッダーのアイコンを押す」の 2 つだけ。esc とキーボードショートカットは付けない。
- 新規ファイルを追加したら `cd BefoldApp && xcodegen generate` を必ず実行する。
- テスト関数名は英語 camelCase（SwiftLint の `identifier_name`）。説明は `@Test("...")` の表示名で日本語を付ける。
- `Localizable.xcstrings` にキーを足すとき、既存の並びを sort し直さない。同じ prefix のキーの直後に挿入する。
- コミットは Conventional Commits + 日本語。

---

## File Structure

| ファイル | 責務 |
| --- | --- |
| `BefoldApp/befold/Viewer/SidebarSlideMetrics.swift`（新規） | スライドモード時のサイドバー幅の幾何。純粋な定数と関数だけ |
| `BefoldApp/befold/Viewer/FileListModel.swift`（変更） | `isSlideMode` の保持と `closeFilter()` の移設 |
| `BefoldApp/befold/Viewer/SidebarHeaderView.swift`（変更） | スライドモード時にアイコン 1 つへ差し替える |
| `BefoldApp/befold/App/ViewerSplitViewController.swift`（変更） | `maximumThickness` 480、幅の固定と復元、autosave の停止と再開 |
| `BefoldApp/befold/App/ViewerMenuValidator.swift`（変更） | スライドモード項目のチェック状態と有効判定 |
| `BefoldApp/befold/App/ViewerWindowController+MenuActions.swift`（変更） | `toggleSlideMode(_:)` の実体 |
| `BefoldApp/befold/App/MainMenuBuilder+ViewMenu.swift`（変更） | 表示メニューへの項目追加 |
| `BefoldApp/befold/App/ViewerWindowAssembler.swift`（変更） | 畳んだときにスライドモードを解除する配線 |
| `BefoldApp/BefoldKit/Resources/Localizable.xcstrings`（変更） | `menu.view.slideMode` / `sidebar.slideMode.exit` |

---

### Task 1: スライドモードの幅（`SidebarSlideMetrics`）と上限 480

**Files:**
- Create: `BefoldApp/befold/Viewer/SidebarSlideMetrics.swift`
- Create: `BefoldApp/befoldTests/SidebarSlideMetricsTests.swift`
- Modify: `BefoldApp/befold/App/ViewerSplitViewController.swift`（`maximumThickness` のみ）

**Interfaces:**
- Consumes: `SidebarRowIndent.rowHorizontalPadding`（8）、`SidebarRowIndent.disclosureWidth`（12）
- Produces:
  - `enum SidebarSlideMetrics`
  - `static let rowContentSpacing: CGFloat`
  - `static let iconWidth: CGFloat`
  - `static let measuredListInset: CGFloat`
  - `static func width(listInset: CGFloat) -> CGFloat`
  - `static var width: CGFloat`（= `width(listInset: measuredListInset)`）

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/SidebarSlideMetricsTests.swift`:

```swift
import CoreGraphics
@testable import befold
import Testing

/// スライドモードのサイドバー幅の幾何。GUI 層は自動テスト対象外なので、
/// 「アイコンは見えてファイル名は隠れる」を測れるのはこの純粋関数だけ。
@Suite
struct SidebarSlideMetricsTests {
    @Test("幅は行の左端からアイコン右端までの合計に List のインセットを足したもの")
    func widthSumsRowGeometryAndListInset() {
        let expected = SidebarRowIndent.rowHorizontalPadding * 2
            + SidebarRowIndent.disclosureWidth
            + SidebarSlideMetrics.rowContentSpacing
            + SidebarSlideMetrics.iconWidth
            + 7

        #expect(SidebarSlideMetrics.width(listInset: 7) == expected)
    }

    @Test("既定の幅は実測した List のインセットを使う")
    func defaultWidthUsesMeasuredInset() {
        #expect(
            SidebarSlideMetrics.width
                == SidebarSlideMetrics.width(listInset: SidebarSlideMetrics.measuredListInset)
        )
    }

    @Test("ファイル名が始まる位置より広く、既定のサイドバー幅より狭い")
    func widthSitsBetweenIconColumnAndDefaultSidebarWidth() {
        // アイコンの右端(= 名前が始まる位置)は超えている。超えていないとアイコンが切れる。
        let iconRightEdge = SidebarRowIndent.rowHorizontalPadding
            + SidebarRowIndent.disclosureWidth
            + SidebarSlideMetrics.rowContentSpacing
            + SidebarSlideMetrics.iconWidth
        #expect(SidebarSlideMetrics.width > iconRightEdge)
        // 通常の下限(200)を明確に下回っていないと、モードとして意味がない。
        #expect(SidebarSlideMetrics.width < 200)
    }
}
```

- [ ] **Step 2: テストが落ちることを確認する**

Run: `cd BefoldApp && swift test --filter SidebarSlideMetricsTests 2>&1 | tail -20`
Expected: FAIL（`cannot find 'SidebarSlideMetrics' in scope`）

- [ ] **Step 3: 実装を書く**

`BefoldApp/befold/Viewer/SidebarSlideMetrics.swift`:

```swift
import CoreGraphics

/// スライドモード中のサイドバー幅の幾何(TASK-585)。
///
/// `SidebarRowIndent` と同じ理由でここに純粋な値として置く。GUI 層は自動テスト対象外
/// なので、「左端のアイコンは見えてファイル名は隠れる」という条件を測れるのは
/// この関数のユニットテストだけになる。
enum SidebarSlideMetrics {
    /// 行の `HStack` が三角とアイコンの間に入れる間隔(`FileListEntryRow` の spacing)。
    static let rowContentSpacing: CGFloat = 2

    /// 行アイコンの一辺(`FileListEntryRow.nameLabel` の frame)。
    static let iconWidth: CGFloat = 16

    /// `List`(NSTableView 裏打ち)が行の外側に持つ左右のインセットの実測値。
    ///
    /// **机上では出せない値**なので、実機で幅を詰めて測った結果をここに焼く。
    /// 測り方と測定値の根拠は TASK-585 の Implementation Notes に残してある。
    static let measuredListInset: CGFloat = 0

    /// 与えられた `List` のインセットに対するスライドモードの幅。
    ///
    /// 左右のパディング + 開閉三角 + 間隔 + アイコン。名前の分は足さない
    /// (名前が隠れることがこのモードの狙いのため)。
    static func width(listInset: CGFloat) -> CGFloat {
        SidebarRowIndent.rowHorizontalPadding * 2
            + SidebarRowIndent.disclosureWidth
            + rowContentSpacing
            + iconWidth
            + listInset
    }

    /// 実際に使う幅。
    static var width: CGFloat { width(listInset: measuredListInset) }
}
```

- [ ] **Step 4: `xcodegen` を回してテストを通す**

Run: `cd BefoldApp && xcodegen generate && swift test --filter SidebarSlideMetricsTests 2>&1 | tail -20`
Expected: PASS（`measuredListInset` は暫定 0。Task 7 の実測で確定させる）

- [ ] **Step 5: `maximumThickness` を 480 にする**

`BefoldApp/befold/App/ViewerSplitViewController.swift` の `init` 内:

```swift
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 480
```

- [ ] **Step 6: ビルドを通す**

Run: `cd BefoldApp && swift build 2>&1 | tail -5`
Expected: エラーなし

- [ ] **Step 7: コミット**

```bash
cd /Users/tokutomi/.warp/worktrees/behold/dry-lightning-viga
git add BefoldApp/befold/Viewer/SidebarSlideMetrics.swift \
  BefoldApp/befoldTests/SidebarSlideMetricsTests.swift \
  BefoldApp/befold/App/ViewerSplitViewController.swift \
  BefoldApp/befold.xcodeproj
git commit -m "feat: スライドモードの幅を定義しサイドバー幅の上限を 480 へ広げる"
```

---

### Task 2: `FileListModel.isSlideMode` と `closeFilter()` の移設

**Files:**
- Modify: `BefoldApp/befold/Viewer/FileListModel.swift`
- Modify: `BefoldApp/befold/Viewer/SidebarHeaderView.swift`（private な `closeFilter` を削除して model のものを呼ぶ）
- Create: `BefoldApp/befoldTests/FileListModelSlideModeTests.swift`

**Interfaces:**
- Consumes: `FileListModel.filterText`、`FileListModel.isFilterActive`
- Produces:
  - `FileListModel.isSlideMode: Bool`（観測対象、既定 false）
  - `FileListModel.setSlideMode(_ on: Bool)`
  - `FileListModel.closeFilter()`

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/FileListModelSlideModeTests.swift`:

```swift
@testable import befold
import Testing

/// スライドモードの窓ごと状態。永続化しないので UserDefaults は触らない。
@MainActor
@Suite
struct FileListModelSlideModeTests {
    @Test("既定ではスライドモードではない")
    func defaultsToOff() {
        #expect(!FileListModelTestSupport.makeModel().isSlideMode)
    }

    @Test("スライドモードに入るとフィルターが閉じ、絞り込み文字列も消える")
    func enteringClosesFilter() {
        let model = FileListModelTestSupport.makeModel()
        model.isFilterActive = true
        model.filterText = "readme"

        model.setSlideMode(true)

        #expect(model.isSlideMode)
        #expect(!model.isFilterActive)
        #expect(model.filterText.isEmpty)
    }

    @Test("スライドモードを抜けてもフィルターは開き直さない")
    func leavingDoesNotReopenFilter() {
        let model = FileListModelTestSupport.makeModel()
        model.isFilterActive = true
        model.filterText = "readme"
        model.setSlideMode(true)

        model.setSlideMode(false)

        #expect(!model.isSlideMode)
        #expect(!model.isFilterActive)
        #expect(model.filterText.isEmpty)
    }
}
```

`FileListModelTestSupport.makeModel()` が既存に無い場合は、同ファイル内に private なヘルパーとして `FileListModel` の生成を書く。既存テスト（`BefoldApp/befoldTests/FileListModelTreeFilterTests.swift`）が `FileListModel` をどう生成しているかを読み、**同じ生成方法をコピーして使う**こと。新しいイニシャライザを足さない。

- [ ] **Step 2: テストが落ちることを確認する**

Run: `cd BefoldApp && swift test --filter FileListModelSlideModeTests 2>&1 | tail -20`
Expected: FAIL（`value of type 'FileListModel' has no member 'isSlideMode'`）

- [ ] **Step 3: 実装を書く**

`BefoldApp/befold/Viewer/FileListModel.swift` の `isFilterActive` の宣言の直後に足す:

```swift
    /// プレゼン用のスライドモード(TASK-585)。**窓ごとで、永続化しない**
    /// (`filterText` / `isFilterActive` と同じ立場)。
    ///
    /// **この値がスライドモードの唯一の真値。** `ViewerSplitViewController` は
    /// 幅だけを持ち、真偽値を二重に持たない。二重に持つと幅と表示が食い違う形が作れる。
    /// 変更は `setSlideMode(_:)` を通すこと(直接代入するとフィルターが閉じない)。
    private(set) var isSlideMode = false

    /// スライドモードの出入り。**進入時にフィルターを閉じる。**
    /// ヘッダーが入力欄ごとアイコン 1 つへ置き換わるため、絞り込みだけが残ると
    /// 細い一覧が「なぜこれだけなのか」分からなくなる。
    func setSlideMode(_ on: Bool) {
        guard isSlideMode != on else { return }
        isSlideMode = on
        if on { closeFilter() }
    }

    /// フィルター欄を閉じ、絞り込み文字列も解除する。
    /// アイコン再押下・esc・スライドモード進入のどれからも同じ挙動にするための共通口。
    func closeFilter() {
        isFilterActive = false
        filterText = ""
    }
```

`BefoldApp/befold/Viewer/SidebarHeaderView.swift` から private な `closeFilter()` を削除し、呼び出し 2 箇所（`.onKeyPress(.escape)` の中と `toggleFilter()` の中）を `model.closeFilter()` に置き換える。

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter FileListModelSlideModeTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: 既存テストが壊れていないことを確認する**

Run: `cd BefoldApp && swift test 2>&1 | tail -20`
Expected: 失敗ゼロ。失敗したら要約行だけで判断せず、出力をファイルへ落として**失敗したテスト名まで特定**してから対処する。

- [ ] **Step 6: コミット**

```bash
cd /Users/tokutomi/.warp/worktrees/behold/dry-lightning-viga
git add BefoldApp/befold/Viewer/FileListModel.swift \
  BefoldApp/befold/Viewer/SidebarHeaderView.swift \
  BefoldApp/befoldTests/FileListModelSlideModeTests.swift \
  BefoldApp/befold.xcodeproj
git commit -m "feat: スライドモードの窓ごと状態を FileListModel に持たせる"
```

---

### Task 3: サイドバー幅の固定・復元と autosave の停止

**Files:**
- Modify: `BefoldApp/befold/App/ViewerSplitViewController.swift`

**Interfaces:**
- Consumes: `SidebarSlideMetrics.width`
- Produces:
  - `SidebarCollapsible.setSlideMode(_ on: Bool)`（プロトコルに追加）
  - `ViewerSplitViewController.setSlideMode(_ on: Bool)`（実装）

このタスクに自動テストは付けない。`NSSplitView` の autosave の書き出しは AppKit 任せで、ユニットテストから誘発できないため（Task 7 の手動確認で担保する）。**代わりに、破れない構造を用意する**: `autosaveName` を触る箇所を private メソッド 1 つに閉じる。

- [ ] **Step 1: プロトコルに口を足す**

`BefoldApp/befold/App/ViewerSplitViewController.swift` の `SidebarCollapsible`:

```swift
/// 既存ウィンドウのサイドバー開閉と幅を、ジェネリック型パラメータを消して操作するための
/// プロトコル。CLI の `--sidebar`/`--no-sidebar` をパス無し起動で既存ウィンドウへ適用する
/// 際と、スライドモードの幅固定(TASK-585)に使う。
@MainActor
protocol SidebarCollapsible: AnyObject {
    func setSidebarCollapsed(_ collapsed: Bool)
    /// サイドバーが畳まれているか。⌘← の有効判定に使う(畳んでいるなら移り先が無い)。
    var isSidebarCollapsed: Bool { get }
    /// スライドモードの幅を適用/解除する。**真偽値はここでは保持しない**
    /// (真値は `FileListModel.isSlideMode`)。
    func setSlideMode(_ on: Bool)
}
```

- [ ] **Step 2: 実装を書く**

`ViewerSplitViewController` の stored property に足す:

```swift
    /// スライドモードへ入る直前のサイドバー幅。抜けるときにここへ戻す。
    /// スライドモード中だけ値を持つ。
    private var thicknessBeforeSlideMode: CGFloat?
```

`toggleSidebar` の下に足す:

```swift
    /// スライドモードの幅を適用/解除する(TASK-585)。真偽値は保持しない。
    ///
    /// **autosave を止めてから幅を変える。** `autosaveName` が生きていると AppKit が
    /// 任意のタイミングでスライドモードの細幅を
    /// `NSSplitView Subview Frames ViewerSplitView` へ書き出し、`viewWillAppear` の
    /// 「記憶があれば上書きしない」規則がそれを固定化して、次に開く窓のサイドバーが
    /// 細いままになる。この形なら、スライドモードのまま終了しても細幅は焼かれない。
    ///
    /// **min/max を先に変えてから `setPosition` する。** 逆順だと `setPosition` の値が
    /// 現在の min/max で clamp されて効かない。
    func setSlideMode(_ on: Bool) {
        if on {
            guard thicknessBeforeSlideMode == nil else { return }
            thicknessBeforeSlideMode = sidebarItem.viewController.view.frame.width
            setAutosaveEnabled(false)
            sidebarItem.minimumThickness = SidebarSlideMetrics.width
            sidebarItem.maximumThickness = SidebarSlideMetrics.width
            splitView.setPosition(SidebarSlideMetrics.width, ofDividerAt: 0)
        } else {
            guard let restored = thicknessBeforeSlideMode else { return }
            thicknessBeforeSlideMode = nil
            sidebarItem.minimumThickness = Self.minimumSidebarWidth
            sidebarItem.maximumThickness = Self.maximumSidebarWidth
            splitView.setPosition(restored, ofDividerAt: 0)
            setAutosaveEnabled(true)
        }
    }

    /// `autosaveName` を触る**唯一の場所**。外から設定できないよう private にする。
    /// ここが 1 箇所であることが、スライドモード中に幅が焼き込まれない担保になる。
    private func setAutosaveEnabled(_ enabled: Bool) {
        splitView.autosaveName = enabled ? Self.autosaveName : nil
    }
```

型プロパティを足し、`init` の直書きを置き換える:

```swift
    static var minimumSidebarWidth: CGFloat { 200 }
    static var maximumSidebarWidth: CGFloat { 480 }

    private static var autosaveName: String {
        "ViewerSplitView"
    }
```

`init` 内を次に置き換える:

```swift
        sidebarItem.minimumThickness = Self.minimumSidebarWidth
        sidebarItem.maximumThickness = Self.maximumSidebarWidth
        sidebarItem.canCollapse = true
```

`init` 末尾の `splitView.autosaveName = "ViewerSplitView"` を `setAutosaveEnabled(true)` に置き換える。

- [ ] **Step 3: ビルドを通す**

Run: `cd BefoldApp && swift build 2>&1 | tail -20`
Expected: エラーなし

- [ ] **Step 4: 既存テストが壊れていないことを確認する**

Run: `cd BefoldApp && swift test 2>&1 | tail -20`
Expected: 失敗ゼロ

- [ ] **Step 5: コミット**

```bash
cd /Users/tokutomi/.warp/worktrees/behold/dry-lightning-viga
git add BefoldApp/befold/App/ViewerSplitViewController.swift
git commit -m "feat: スライドモード中はサイドバー幅を固定し autosave を止める"
```

---

### Task 4: 表示メニューの項目と有効判定

**Files:**
- Modify: `BefoldApp/befold/App/ViewerMenuValidator.swift`
- Modify: `BefoldApp/befold/App/ViewerWindowController+MenuActions.swift`
- Modify: `BefoldApp/befold/App/MainMenuBuilder+ViewMenu.swift`
- Modify: `BefoldApp/BefoldKit/Resources/Localizable.xcstrings`
- Modify: `BefoldApp/befoldTests/ViewerMenuValidatorTests.swift`
- Modify: `BefoldApp/befoldTests/MainMenuBuilderTests.swift`

**Interfaces:**
- Consumes: `FileListModel.isSlideMode` / `setSlideMode(_:)`、`SidebarCollapsible.setSlideMode(_:)`、`SidebarTableFocuser.focus()`
- Produces:
  - `ViewerMenuValidationSource.isSlideMode: Bool`（プロトコルに追加）
  - `ViewerWindowController.toggleSlideMode(_ sender: Any?)`（@objc）
  - `ViewerWindowController.isSlideMode: Bool`（読み取り。`fileListModel.isSlideMode` の写し）

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/ViewerMenuValidatorTests.swift` の `StubSource` に 1 行足す:

```swift
        var isSlideMode = false
```

同ファイルにテストを追加する:

```swift
    @Test("スライドモードはサイドバーを畳んでいる間は選べない")
    func slideModeRequiresVisibleSidebar() {
        let source = StubSource()
        source.isSidebarCollapsed = true

        let item = makeItem(#selector(ViewerWindowController.toggleSlideMode(_:)))

        #expect(!ViewerMenuValidator.validate(item, source: source))
    }

    @Test("スライドモードのチェックは窓の状態をそのまま映す")
    func slideModeReflectsWindowState() {
        let source = StubSource()
        let item = makeItem(#selector(ViewerWindowController.toggleSlideMode(_:)))

        #expect(ViewerMenuValidator.validate(item, source: source))
        #expect(item.state == .off)

        source.isSlideMode = true
        #expect(ViewerMenuValidator.validate(item, source: source))
        #expect(item.state == .on)
    }
```

`BefoldApp/befoldTests/MainMenuBuilderTests.swift` に追加する:

```swift
    @Test("表示メニューにスライドモードの項目がある")
    func viewMenuHasSlideModeItem() throws {
        let view = try #require(fixture.submenu(titledKey: "menu.view.title"))

        let item = try #require(
            view.items.first { $0.action == #selector(ViewerWindowController.toggleSlideMode(_:)) }
        )
        // ショートカットは割り当てない(TASK-585)。プレゼン中の誤爆を避けるため。
        #expect(item.keyEquivalent.isEmpty)
    }
```

- [ ] **Step 2: テストが落ちることを確認する**

Run: `cd BefoldApp && swift test --filter 'ViewerMenuValidatorTests|MainMenuBuilderTests' 2>&1 | tail -20`
Expected: FAIL（`toggleSlideMode` が存在しない）

- [ ] **Step 3: プロトコルへ状態を足す**

`BefoldApp/befold/App/ViewerMenuValidator.swift` の `ViewerMenuValidationSource` に足す:

```swift
    /// スライドモード中か。表示メニューのチェック状態に使う。
    var isSlideMode: Bool { get }
```

`validateFocusTraversalItem` に分岐を足す（サイドバーの可視性を条件にする点で ⌘← と同じ系統のため、ここに置く）:

```swift
        if menuItem.action == #selector(ViewerWindowController.toggleSlideMode(_:)) {
            menuItem.state = source.isSlideMode ? .on : .off
            // 畳んでいる間は入れない。自動で開くと、ユーザーが操作していない開閉が
            // SidebarStateStore へ「最後にユーザーが操作した開閉状態」として保存され、
            // 以後の新規ウィンドウの初期値を汚す(TASK-585)。
            return !source.isSidebarCollapsed
        }
```

- [ ] **Step 4: アクションの実体を書く**

`BefoldApp/befold/App/ViewerWindowController+MenuActions.swift` の `focusSidebar(_:)` の下に足す:

```swift
    /// スライドモード中か。`ViewerMenuValidationSource` の要求。真値は `fileListModel`。
    var isSlideMode: Bool {
        fileListModel.isSlideMode
    }

    /// View > スライドモード。畳んでいるときは項目が無効(`ViewerMenuValidator`)。
    ///
    /// 状態(`fileListModel`)と幅(`sidebarCollapsible`)を**必ずこの順で**更新する。
    /// 幅を先に変えるとヘッダーが 1 フレーム広いまま描かれる。
    @objc func toggleSlideMode(_ sender: Any?) {
        let next = !fileListModel.isSlideMode
        fileListModel.setSlideMode(next)
        sidebarCollapsible?.setSlideMode(next)
        if next {
            // これがこのモードの目的そのもの。カーソルキーでファイルを送れるようにする。
            fileListModel.tableFocuser.focus()
        }
    }
```

- [ ] **Step 5: メニュー項目を足す**

`BefoldApp/befold/App/MainMenuBuilder+ViewMenu.swift` の `addSidebarItems(to:)` の末尾に足す:

```swift
        // ショートカットは割り当てない。プレゼン中に誤って入る/抜けるのを避けるため
        // メニューからの明示操作だけにする(TASK-585)。
        menu.addLocalizedItem(
            "menu.view.slideMode",
            action: #selector(ViewerWindowController.toggleSlideMode(_:)),
            keyEquivalent: ""
        )
```

`addLocalizedItem` の引数ラベルと既定値は `MainMenuBuilder.swift` の定義を読んで合わせること（`keyEquivalent` が省略可能なら省略してよい）。

- [ ] **Step 6: ローカライズのキーを足す**

`BefoldApp/BefoldKit/Resources/Localizable.xcstrings` に `menu.view.slideMode` を追加する。値は英語 `"Slide Mode"`、日本語 `"スライドモード"`。既存の `menu.view.showHiddenFiles` など同じ prefix のキーの近くに挿入し、**ファイル全体を sort し直さない**。

- [ ] **Step 7: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter 'ViewerMenuValidatorTests|MainMenuBuilderTests' 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 8: 修正を戻すと落ちることを確かめる**

`validateFocusTraversalItem` の `return !source.isSidebarCollapsed` を一時的に `return true` に変えて `swift test --filter ViewerMenuValidatorTests` を回し、`slideModeRequiresVisibleSidebar` が落ちることを確認してから元に戻す。通っただけでは何も検証していない。

- [ ] **Step 9: コミット**

```bash
cd /Users/tokutomi/.warp/worktrees/behold/dry-lightning-viga
git add BefoldApp/befold/App/ViewerMenuValidator.swift \
  BefoldApp/befold/App/ViewerWindowController+MenuActions.swift \
  BefoldApp/befold/App/MainMenuBuilder+ViewMenu.swift \
  BefoldApp/BefoldKit/Resources/Localizable.xcstrings \
  BefoldApp/befoldTests/ViewerMenuValidatorTests.swift \
  BefoldApp/befoldTests/MainMenuBuilderTests.swift
git commit -m "feat: 表示メニューにスライドモードの切り替えを追加する"
```

---

### Task 5: スライドモード中のヘッダー

**Files:**
- Modify: `BefoldApp/befold/Viewer/SidebarHeaderView.swift`
- Modify: `BefoldApp/BefoldKit/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `FileListModel.isSlideMode`
- Produces: なし（ビューの内部）

このタスクに自動テストは付けない（SwiftUI の見た目は自動テスト対象外）。Task 7 の手動確認で担保する。

- [ ] **Step 1: 実装を書く**

`BefoldApp/befold/Viewer/SidebarHeaderView.swift` の `body` を次に置き換える:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.isSlideMode {
                slideModeIndicator
            } else {
                baseDirectoryIndicator
                navigationHeader
                if model.isFilterActive {
                    filterField
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// スライドモード中のヘッダー。**状態表示と解除操作を兼ねる**。
    /// 幅がアイコン 1 つ分しかないので、他の操作は一切出さない
    /// (メニュー側からも解除できる)。
    private var slideModeIndicator: some View {
        Button {
            onToggleSlideMode()
        } label: {
            Image(systemName: "play.rectangle")
                .foregroundStyle(.tint)
        }
        .buttonStyle(.borderless)
        .help(String(localized: "sidebar.slideMode.exit", bundle: .l10n))
    }
```

`SidebarHeaderView` のプロパティに足す（既定値を持たせない。渡し忘れを静かに「押しても何も起きないボタン」へ倒れさせないため）:

```swift
    /// スライドモードの解除。ウィンドウ側の `toggleSlideMode(_:)` と同じ経路を通す
    /// (状態と幅の更新順序を 1 箇所に保つため、ここで直接 model を書き換えない)。
    let onToggleSlideMode: () -> Void
```

- [ ] **Step 2: 呼び出し側を直す**

`BefoldApp/befold/Viewer/FileListView.swift` の `SidebarHeaderView(...)` の呼び出しに `onToggleSlideMode:` を足す。`FileListView` が既に受け取っている他のトグル用クロージャ（`onToggleSidebarTreeLayout` など）と同じ形で、`FileListView` のプロパティとして受け取り、そこへ渡す。`FileListView` を組み立てている側（`ViewerWindowAssembler` または `ViewerWindowController+SidebarHost`）まで遡って、`ViewerWindowController.toggleSlideMode(nil)` を呼ぶクロージャを渡す。

- [ ] **Step 3: ローカライズのキーを足す**

`sidebar.slideMode.exit` を追加する。英語 `"Exit Slide Mode"`、日本語 `"スライドモードを終了"`。既存の `sidebar.*` キーの近くに挿入する。

- [ ] **Step 4: ビルドとテスト**

Run: `cd BefoldApp && swift build 2>&1 | tail -20 && swift test 2>&1 | tail -20`
Expected: ビルドエラーなし、テスト失敗ゼロ

- [ ] **Step 5: コミット**

```bash
cd /Users/tokutomi/.warp/worktrees/behold/dry-lightning-viga
git add BefoldApp/befold/Viewer/SidebarHeaderView.swift \
  BefoldApp/befold/Viewer/FileListView.swift \
  BefoldApp/befold/App/ViewerWindowAssembler.swift \
  BefoldApp/BefoldKit/Resources/Localizable.xcstrings
git commit -m "feat: スライドモード中のサイドバーヘッダーをアイコン 1 つにする"
```

---

### Task 6: 畳んだらスライドモードを解除する

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowAssembler.swift`
- Create: `BefoldApp/befoldTests/SlideModeCollapseExitTests.swift`

**Interfaces:**
- Consumes: `ViewerSplitViewController` の `onSidebarDidHide`、`ViewerWindowController.toggleSlideMode(_:)`
- Produces: なし

サイドバーを畳んだときスライドモードが残ると、次に開いたときアイコン幅のまま戻る。既存の `onSidebarDidHide`（畳んだときに呼ばれる口）へ相乗りし、新しいクロージャを増やさない。

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/SlideModeCollapseExitTests.swift`:

```swift
@testable import befold
import Testing

/// サイドバーを畳んだらスライドモードが残らないこと。
/// 残ると、次に開いたときアイコン幅のまま戻り、ヘッダーの解除ボタンにしか
/// 出口が無くなる。
@MainActor
@Suite
struct SlideModeCollapseExitTests {
    @Test("サイドバーを畳むとスライドモードが解除される")
    func collapsingLeavesSlideMode() {
        let model = FileListModelTestSupport.makeModel()
        model.setSlideMode(true)

        // ViewerWindowAssembler が onSidebarDidHide に配線する処理と同じもの。
        SlideModeExitOnHide.apply(to: model)

        #expect(!model.isSlideMode)
    }
}
```

配線先の実体が `ViewerWindowAssembler` のクロージャ内にしか無いとテストから呼べないので、**呼べる形へ切り出してから配線する**。切り出し先は `BefoldApp/befold/App/SlideModeExitOnHide.swift`（新規、`enum` + `static func apply(to:)`）。既存の `onSidebarDidHide` のクロージャからこれを呼ぶ。幅の復元は `setSlideMode(false)` を `sidebarCollapsible` へ伝える形で `ViewerWindowAssembler` 側に残す。

- [ ] **Step 2: テストが落ちることを確認する**

Run: `cd BefoldApp && swift test --filter SlideModeCollapseExitTests 2>&1 | tail -20`
Expected: FAIL（`cannot find 'SlideModeExitOnHide' in scope`）

- [ ] **Step 3: 実装と配線**

`BefoldApp/befold/App/SlideModeExitOnHide.swift`:

```swift
/// サイドバーを畳んだときにスライドモードを解除する処理(TASK-585)。
///
/// `ViewerWindowAssembler` のクロージャに直接書かず切り出しているのは、
/// クロージャの中身がユニットテストから呼べないため。**新しいクロージャは増やさない**
/// (`onSidebarDidHide` は既にある「畳んだ」の口)。
@MainActor
enum SlideModeExitOnHide {
    static func apply(to model: FileListModel) {
        model.setSlideMode(false)
    }
}
```

`ViewerWindowAssembler` の `onSidebarDidHide` のクロージャに、既存処理を残したまま次を足す:

```swift
                SlideModeExitOnHide.apply(to: fileListModel)
                splitViewController.setSlideMode(false)
```

クロージャ内で参照できる名前は実際のコードに合わせること（`fileListModel` / `splitViewController` の綴りは `ViewerWindowAssembler` を読んで確認する）。強参照の循環を作らないよう、既存クロージャと同じ `[weak ...]` の作法に揃える。

- [ ] **Step 4: `xcodegen` を回してテストを通す**

Run: `cd BefoldApp && xcodegen generate && swift test --filter SlideModeCollapseExitTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: 修正を戻すと落ちることを確かめる**

`SlideModeExitOnHide.apply` の中身を空にして同じテストを回し、落ちることを確認してから戻す。

- [ ] **Step 6: 全テストとコミット**

```bash
cd BefoldApp && swift test 2>&1 | tail -20
cd /Users/tokutomi/.warp/worktrees/behold/dry-lightning-viga
git add BefoldApp/befold/App/SlideModeExitOnHide.swift \
  BefoldApp/befold/App/ViewerWindowAssembler.swift \
  BefoldApp/befoldTests/SlideModeCollapseExitTests.swift \
  BefoldApp/befold.xcodeproj
git commit -m "feat: サイドバーを畳んだらスライドモードを解除する"
```

---

### Task 7: 実機での実測と仕上げ

**Files:**
- Modify: `BefoldApp/befold/Viewer/SidebarSlideMetrics.swift`（`measuredListInset` の確定）
- Modify: `docs/dev/native-app-design.md`
- Modify: `backlog/tasks/task-585 *.md`（`backlog` CLI 経由）

- [ ] **Step 1: アプリを起動して幅を測る**

Run: `/run`（スキル）でビルドして起動する。サイドバーを持つ窓を開き、スライドモードに入る。

測り方: `FileListView` の行の左端から名前が始まるまでの距離が、`SidebarSlideMetrics.width(listInset: 0)` = 54pt と一致するかを見る。アイコンが右端で切れていれば `measuredListInset` を増やし、名前の先頭が見えていれば減らす。**「アイコンは全部見えて、名前は 1 文字も見えない」**が合格条件。

- [ ] **Step 2: `measuredListInset` を確定して再ビルド**

確定した値を `SidebarSlideMetrics.measuredListInset` に書く。`SidebarSlideMetricsTests` が引き続き通ることを確認する（`width < 200` のアサートに引っかかる値なら、そもそも設計が破れているので立ち止まる）。

- [ ] **Step 3: autosave が汚れないことを手動で確認する**

```bash
defaults read com.degino.befold "NSSplitView Subview Frames ViewerSplitView"
```

3 回測って記録する。

1. サイドバー幅を 300pt くらいにして、通常モードのまま値を読む
2. スライドモードに入って値を読む → **1 と同じであること**（細幅が書かれていない）
3. スライドモードのままアプリを終了して値を読む → **1 と同じであること**

さらに、スライドモードを抜けたときにサイドバー幅が 300pt へ戻ることを目視で確認する。

未確認だった「`autosaveName` を再設定したとき AppKit が保存済みフレームを読み直して適用するか」も、ここで挙動を観察して結果を記録する。

- [ ] **Step 4: 一連の操作を手で通す**

- サイドバーを畳んだ状態で表示メニューを開き、スライドモードが**無効**になっていること
- サイドバーを開いてスライドモードに入ると、幅がアイコン幅になり、ヘッダーがアイコン 1 つになること
- そのままカーソルキー（↑↓）でファイルを送れること（**これが目的**）
- ヘッダーのアイコンを押すと抜けて、幅が戻ること
- 表示メニューからも抜けられ、チェックが状態に追随すること
- フィルターを開いた状態でスライドモードに入ると、フィルターが閉じること
- スライドモード中にサイドバーを畳むと、スライドモードが解除されること

- [ ] **Step 5: lint とフォーマット**

```bash
cd /Users/tokutomi/.warp/worktrees/behold/dry-lightning-viga/BefoldApp
swift package plugin --allow-writing-to-package-directory swiftformat
```

そのあと `/swiftlint-baseline` を回し、main とのベースライン差分がゼロであることを確認する。

- [ ] **Step 6: 現在仕様の文書を追随させる**

`docs/dev/native-app-design.md` にスライドモードを追記する。書くのは「窓ごと・永続化しない」「畳んでいる間は入れない」「幅は `SidebarSlideMetrics`」の 3 点。コードを指すときは**行番号を書かない**（`scripts/check-doc-citations.sh` が pre-commit で落とす）。

- [ ] **Step 7: Implementation Notes を残す**

```bash
cd /Users/tokutomi/.warp/worktrees/behold/dry-lightning-viga
backlog task edit TASK-585 --append-notes "..."
```

残す内容:
- `measuredListInset` の実測値と、どう測ったか
- `defaults read` の 3 回の測定値
- `autosaveName` 再設定時の AppKit の挙動（読み直すか否か）

- [ ] **Step 8: 完了処理**

`/finish-task TASK-585` を回す。

---

## Self-Review

**1. Spec coverage**

| spec の要求 | 実装するタスク |
| --- | --- |
| `maximumThickness` 480 / `minimumThickness` 200 据え置き | Task 1 |
| 状態は `FileListModel`、窓ごと・永続化しない、真値は 1 つ | Task 2 |
| autosave の汚染を止める、min/max → setPosition の順序 | Task 3 |
| 幅の値と `SidebarSlideMetrics` | Task 1、実測は Task 7 |
| 畳んでいる間は無効 / 畳んだら解除 | Task 4（無効）、Task 6（解除） |
| ヘッダーをアイコン 1 つに、進入時に `closeFilter` | Task 5（ヘッダー）、Task 2（closeFilter） |
| 進入直後に `tableFocuser.focus()` | Task 4 |
| esc とショートカットを付けない | Task 4 Step 5 のコメントとテストで固定 |

**2. Placeholder scan**

`measuredListInset = 0` は暫定値だが、Task 7 Step 2 で確定させる手順と合格条件を明記してあるので放置されない。それ以外に TBD は無い。

**3. Type consistency**

`setSlideMode(_:)` の名前を `FileListModel`・`SidebarCollapsible`・`ViewerSplitViewController` の 3 箇所で統一した。`SidebarSlideMetrics.width` は Task 1 で定義し Task 3 で消費する。`isSlideMode` は `FileListModel`（真値）・`ViewerMenuValidationSource`（読み取り）・`ViewerWindowController`（写し）で同名。
