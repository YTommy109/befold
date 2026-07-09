# サイドバー折りたたみハンドル Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** サイドバーを閉じている間、左端に常時表示される細いグレーの縦バーを追加し、クリックでサイドバーを再表示できるようにする。

**Architecture:** 新規の `NSView` サブクラス `CollapsedSidebarHandleView` を作り、`ViewerSplitViewController` の view にオーバーレイとして常時追加する。専用の状態は持たず、`sidebarItem.isCollapsed` を都度読んで `isHidden` を同期するだけのシンプルな仕組みにする。

**Tech Stack:** Swift 6 / AppKit（`NSSplitViewController`, `NSTrackingArea`, `NSBezierPath`）、既存のローカライズ基盤（`String(localized:bundle: .l10n)` + `Localizable.xcstrings`）

## Global Constraints

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）に準拠する
- テスト関数名は英語 camelCase、日本語の説明は `@Test("...")` の表示名で付ける
- AppKit の描画・マウスインタラクション層は自動テスト対象外（リリース前手動チェック）— 本機能はこの層に該当するため、各タスクの確認は `swift build` によるコンパイル成功確認と、既存テストスイートの回帰確認で代替する
- コミットは Conventional Commits + 日本語で行う

---

### Task 1: CollapsedSidebarHandleView と tooltip 文言の追加

**Files:**
- Create: `BefoldApp/befold/App/CollapsedSidebarHandleView.swift`
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: `final class CollapsedSidebarHandleView: NSView`
  - `var onActivate: (() -> Void)?` — クリック時に呼ばれるコールバック（Task 2 で `ViewerSplitViewController` から設定される）
  - 通常の `NSView` イニシャライザ（`init(frame:)`）で生成可能

- [ ] **Step 1: ローカライズ文字列を追加する**

`BefoldApp/befold/Resources/Localizable.xcstrings` の `"menu.view.toggleSidebar"` エントリーの直後に、新しいキーを追加する。

```
    "menu.view.toggleSidebar" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Toggle Sidebar" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "サイドバーを表示/非表示" } }
      }
    },
    "sidebar.collapsedHandle.tooltip" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Show Sidebar (⌘B)" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "サイドバーを表示 (⌘B)" } }
      }
    },
    "menu.view.toggleSource" : {
```

- [ ] **Step 2: 既存の LocalizationTests が新キーを拾うことを確認する**

Run: `cd BefoldApp && swift test --filter LocalizationTests`
Expected: PASS（`allKeysHaveBothLanguages` が新キー `sidebar.collapsedHandle.tooltip` の en/ja 両方の訳を検証し、既存キーと合わせて成功する）

- [ ] **Step 3: CollapsedSidebarHandleView を作成する**

```swift
import AppKit

/// サイドバーが折りたたまれている間、左端に常時表示する薄いハンドル。
/// クリックでサイドバーを再表示するきっかけを与える。
final class CollapsedSidebarHandleView: NSView {
    var onActivate: (() -> Void)?

    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = String(localized: "sidebar.collapsedHandle.tooltip", bundle: .l10n)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = isHovering ? .secondaryLabelColor : .separatorColor
        color.setFill()
        NSBezierPath.fill(bounds)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
```

- [ ] **Step 4: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功（エラー・警告なし）

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/CollapsedSidebarHandleView.swift BefoldApp/befold/Resources/Localizable.xcstrings
git commit -m "feat: サイドバー折りたたみハンドルのビューを追加する"
```

---

### Task 2: ViewerSplitViewController への組み込み

**Files:**
- Modify: `BefoldApp/befold/App/ViewerSplitViewController.swift`

**Interfaces:**
- Consumes: `CollapsedSidebarHandleView`（Task 1）— `onActivate: (() -> Void)?`, `NSView` として `addSubview` 可能
- Produces: なし（末端コンポーネントへの配線のみ）

現在の `ViewerSplitViewController.swift` は以下の内容（抜粋、行番号は現状のもの）:

```swift
final class ViewerSplitViewController<Sidebar: View, Content: View>: NSSplitViewController {
    private let sidebarItem: NSSplitViewItem
    private var didForceInitialCollapse = false
    private let forceSidebarVisible: Bool

    init(sidebar: Sidebar, content: Content, forceSidebarVisible: Bool = false) {
        self.forceSidebarVisible = forceSidebarVisible
        sidebarItem = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: sidebar))
        super.init(nibName: nil, bundle: nil)

        sidebarItem.minimumThickness = 150
        sidebarItem.maximumThickness = 300
        sidebarItem.canCollapse = true

        let contentItem = NSSplitViewItem(viewController: NSHostingController(rootView: content))

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)

        splitView.autosaveName = "ViewerSplitView"
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        guard !didForceInitialCollapse else { return }
        didForceInitialCollapse = true
        sidebarItem.isCollapsed = !forceSidebarVisible
    }

    override func toggleSidebar(_ sender: Any?) {
        let wasCollapsed = sidebarItem.isCollapsed
        super.toggleSidebar(sender)
        if wasCollapsed, !sidebarItem.isCollapsed {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let window = view.window
                else { return }
                window.makeFirstResponder(
                    sidebarItem.viewController.view
                )
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}
```

- [ ] **Step 1: ハンドルビューのプロパティと配置を追加する**

`private let forceSidebarVisible: Bool` の直後に以下を追加:

```swift
    private let collapsedHandleView = CollapsedSidebarHandleView()
```

`init` の末尾（`splitView.autosaveName = "ViewerSplitView"` の直後）に以下を追加:

```swift

        collapsedHandleView.translatesAutoresizingMaskIntoConstraints = false
        collapsedHandleView.onActivate = { [weak self] in
            self?.toggleSidebar(nil)
        }
        view.addSubview(collapsedHandleView)
        NSLayoutConstraint.activate([
            collapsedHandleView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collapsedHandleView.topAnchor.constraint(equalTo: view.topAnchor),
            collapsedHandleView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collapsedHandleView.widthAnchor.constraint(equalToConstant: 5),
        ])
```

- [ ] **Step 2: 可視性同期メソッドを追加する**

`toggleSidebar(_:)` の直前に以下を追加:

```swift
    private func syncCollapsedHandleVisibility() {
        collapsedHandleView.isHidden = !sidebarItem.isCollapsed
    }
```

- [ ] **Step 3: 3箇所の同期呼び出しを配線する**

`viewWillAppear()` を以下のように変更（末尾に同期呼び出しを追加):

```swift
    override func viewWillAppear() {
        super.viewWillAppear()
        guard !didForceInitialCollapse else {
            syncCollapsedHandleVisibility()
            return
        }
        didForceInitialCollapse = true
        sidebarItem.isCollapsed = !forceSidebarVisible
        syncCollapsedHandleVisibility()
    }
```

`toggleSidebar(_:)` を以下のように変更（`super.toggleSidebar(sender)` の直後に同期呼び出しを追加）:

```swift
    override func toggleSidebar(_ sender: Any?) {
        let wasCollapsed = sidebarItem.isCollapsed
        super.toggleSidebar(sender)
        syncCollapsedHandleVisibility()
        if wasCollapsed, !sidebarItem.isCollapsed {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let window = view.window
                else { return }
                window.makeFirstResponder(
                    sidebarItem.viewController.view
                )
            }
        }
    }
```

ディバイダーをドラッグして閉じた場合をカバーするため、`NSSplitViewDelegate` の `splitViewDidResizeSubviews(_:)` をオーバーライドする（クラス末尾、`required init?(coder:)` の直前に追加）:

```swift
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        syncCollapsedHandleVisibility()
    }
```

- [ ] **Step 4: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功（エラー・警告なし）

- [ ] **Step 5: 既存テストスイートに回帰がないことを確認する**

Run: `cd BefoldApp && swift test`
Expected: 全テスト PASS（`ViewerSplitViewController` は AppKit の GUI 層のため専用の自動テストはないが、既存のウィンドウ・セッション関連テストに回帰がないことを確認する）

- [ ] **Step 6: コミット**

```bash
git add BefoldApp/befold/App/ViewerSplitViewController.swift
git commit -m "feat: サイドバー折りたたみ中に左端ハンドルを表示する"
```

---

### Task 3: 手動動作確認

**Files:** なし（コード変更なし、動作確認のみ）

**Interfaces:**
- Consumes: Task 1, Task 2 で実装した機能一式

- [ ] **Step 1: アプリを起動する**

Run: `cd BefoldApp && swift build && open .build/debug/befold.app` （または `/run` スキルでビルド・起動）

- [ ] **Step 2: サイドバーを閉じた状態でハンドルが見えることを確認する**

`⌘B` でサイドバーを閉じ、ウィンドウ左端に控えめなグレーの縦バーが常時表示されていることを目視確認する。

- [ ] **Step 3: ホバーで色とカーソルが変わることを確認する**

マウスをハンドルに重ね、バーの色が少し濃くなり、カーソルが指差し（pointing hand）に変わることを確認する。

- [ ] **Step 4: ツールチップが表示されることを確認する**

ハンドルにマウスを乗せたまましばらく待ち、「サイドバーを表示 (⌘B)」というツールチップが表示されることを確認する。

- [ ] **Step 5: クリックでサイドバーが開くことを確認する**

ハンドルをクリックし、サイドバーがアニメーション付きで開き、ハンドルが非表示になることを確認する。

- [ ] **Step 6: ディバイダードラッグでもハンドルが表示されることを確認する**

サイドバーを開いた状態で、ディバイダーを左端までドラッグして閉じ、⌘Bを使わなくてもハンドルが表示されることを確認する。

- [ ] **Step 7: 複数ウィンドウでの独立動作を確認する**

新しいウィンドウ（新しいファイル/フォルダーを開く）を作成し、片方のウィンドウでサイドバーを閉じても、もう片方のウィンドウの表示状態に影響しないことを確認する。
