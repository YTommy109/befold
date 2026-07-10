# サイドバートグルのツールバーボタン化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** サイドバーが閉じている間の再表示手段を、左端の常時表示ハンドル(`CollapsedSidebarHandleView`)から、macOS 標準のツールバーサイドバーボタン(`NSToolbarItem.Identifier.toggleSidebar`)に置き換える。

**Architecture:** `ViewerWindowController` の `NSToolbarDelegate` 実装に `.toggleSidebar` を追加するだけで、アイコン表示・開閉状態同期・アクション配線は AppKit が自動で行う。これに伴い `ViewerSplitViewController` からハンドル関連コードを削除し、`CollapsedSidebarHandleView.swift` を削除する。

**Tech Stack:** Swift 6, AppKit (`NSSplitViewController`, `NSToolbar`), XcodeGen/SPM (`BefoldApp/`)

## Global Constraints

- Swift 6 strict concurrency(`SWIFT_STRICT_CONCURRENCY: complete`)を維持する
- コミットメッセージは Conventional Commits + 日本語(例: `fix: ...` `chore: ...`)
- テスト関数名は英語 camelCase、日本語の説明が必要なら `@Test("日本語")` の表示名を使う
- WebView/GUI 層(ツールバー・分割ビュー)は自動テスト対象外。手動チェックで確認する
- ビルド確認は `cd BefoldApp && swift build`(Xcode 不要な範囲)

---

### Task 1: ツールバーにシステム標準サイドバーボタンを追加する

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift:548-554`(`NSToolbarDelegate` 拡張)

**Interfaces:**
- Consumes: 既存の `Self.sourceToggleItemIdentifier`(`ViewerWindowController.swift:11`)
- Produces: なし(ツールバー構成の変更のみ。後続タスクはこのツールバー構成に依存しない)

- [ ] **Step 1: `toolbarDefaultItemIdentifiers` と `toolbarAllowedItemIdentifiers` に `.toggleSidebar` を追加する**

`BefoldApp/befold/App/ViewerWindowController.swift:548-554` を以下に置き換える:

```swift
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .flexibleSpace, Self.sourceToggleItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, Self.sourceToggleItemIdentifier, .flexibleSpace, .space]
    }
```

`.toggleSidebar` はシステム標準識別子(`NSToolbarItem.Identifier.toggleSidebar`)のため、`toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)` 側に分岐を追加する必要はない(AppKit が該当識別子を認識してアイテムを自動生成する)。

- [ ] **Step 2: ビルドして通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功(エラー・警告なし)

- [ ] **Step 3: 手動確認(アプリを起動してツールバーを見る)**

Run: `cd BefoldApp && swift run` (または `/run` スキルでアプリを起動)
確認項目:
1. ツールバー左端(タイトルの左)にサイドバーアイコンボタンが表示される
2. クリックでサイドバーが開閉する
3. サイドバーが開いている/閉じているそれぞれの状態でアイコンの見た目が変わる

- [ ] **Step 4: コミット**

```bash
cd BefoldApp && git add befold/App/ViewerWindowController.swift
git commit -m "feat: ツールバーに標準サイドバートグルボタンを追加する"
```

---

### Task 2: 左端ハンドルとその同期ロジックを削除する

**Files:**
- Delete: `BefoldApp/befold/App/CollapsedSidebarHandleView.swift`
- Modify: `BefoldApp/befold/App/ViewerSplitViewController.swift`
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings:193-200`(`sidebar.collapsedHandle.tooltip` キー削除)

**Interfaces:**
- Consumes: Task 1 で追加したツールバーボタンが再表示手段として機能していること(手動確認済み)
- Produces: なし

- [ ] **Step 1: `CollapsedSidebarHandleView.swift` を削除する**

```bash
cd BefoldApp && git rm befold/App/CollapsedSidebarHandleView.swift
```

- [ ] **Step 2: `ViewerSplitViewController.swift` からハンドル関連コードを削除する**

現在の全文(`BefoldApp/befold/App/ViewerSplitViewController.swift`)を以下に置き換える:

```swift
import AppKit
import SwiftUI

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

        // ディバイダー位置(サイドバー幅)を起動をまたいで永続化する。
        // この autosave は開閉状態も復元するため、開閉だけは
        // viewWillAppear で明示的に決める(forceSidebarVisible があれば開く)
        splitView.autosaveName = "ViewerSplitView"
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // autosave の復元が開閉状態も引き継ぐため、初回表示の直前に必ず確定させる。
        // (新規ウィンドウ・タブは通常サイドバーが閉じた状態で開く仕様。
        //  forceSidebarVisible が true の場合のみ開いた状態にする。CLI 経由で
        //  フォルダーを開いたときに、フォルダーを閲覧していることを一目で
        //  分かるようにするため)
        // タブ切替や最小化復帰でも viewWillAppear は呼ばれるため、初回に限定する
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

削除した内容: `collapsedHandleView` プロパティとその生成・レイアウト制約、`syncCollapsedHandleVisibility()`、`splitViewDidResizeSubviews` オーバーライド(ハンドル同期専用だったため丸ごと不要)。

- [ ] **Step 3: `Localizable.xcstrings` から `sidebar.collapsedHandle.tooltip` キーを削除する**

`BefoldApp/befold/Resources/Localizable.xcstrings` の該当ブロック(193〜200行目付近)を削除する:

```json
    "sidebar.collapsedHandle.tooltip" : {
      "comment" : "⌘S は MainMenuBuilder.swift の menu.view.toggleSidebar のキーボードショートカットと一致させること",
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Show Sidebar (⌘S)" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "サイドバーを表示 (⌘S)" } }
      }
    },
```
前後のキー(`menu.view.toggleSidebar` と `menu.view.toggleSource`)の間の JSON カンマ区切りが崩れないよう、削除後に JSON として妥当であることを確認する。

- [ ] **Step 4: ビルドして通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功。`CollapsedSidebarHandleView` への参照が残っていればコンパイルエラーになるため、ここで検出できる。

- [ ] **Step 5: 既存テストを実行する**

Run: `cd BefoldApp && swift test` (Xcode.app が必要)
Expected: 全テスト PASS(`CollapsedSidebarHandleView` や `ViewerSplitViewController` を直接対象にした自動テストは元々存在しないため、既存テスト群に影響がないことだけを確認する)

- [ ] **Step 6: 手動確認**

Run: `cd BefoldApp && swift run` (または `/run` スキル)
確認項目:
1. 左端に薄いグレーのハンドルが一切表示されない(サイドバーを閉じた状態で確認)
2. ツールバーのサイドバーボタン・View メニュー「サイドバーを表示/非表示」・⌘S のいずれからも開閉できる
3. サイドバーを閉じたまま新規ウィンドウ/タブを開いても、ツールバーボタンから再表示できる

- [ ] **Step 7: コミット**

```bash
cd BefoldApp && git add -A befold/App/ViewerSplitViewController.swift befold/Resources/Localizable.xcstrings
git commit -m "fix: サイドバー再表示手段を左端ハンドルからツールバーボタンに統一する"
```

---

### Task 3: 設計ドキュメントの整合確認と最終チェック

**Files:**
- Read only: `docs/superpowers/specs/2026-07-10-sidebar-toolbar-toggle-design.md`

**Interfaces:**
- Consumes: Task 1・Task 2 で変更した全ファイル
- Produces: なし(最終確認タスク)

- [ ] **Step 1: `/check` スキルで規約準拠・品質チェックを実行する**

`/check` を実行し、SwiftLint やフォーマットの指摘がないことを確認する。指摘があれば修正してから次に進む。

- [ ] **Step 2: 設計ドキュメントの期待される挙動を再確認する**

設計ドキュメント「期待される挙動」節の4項目(ツールバーボタン表示・開閉・三経路同期・初期表示)を Task 1・2 の手動確認で満たしていることを確認する。満たしていなければ該当タスクに戻って修正する。

- [ ] **Step 3: 最終コミット(差分が残っていれば)**

```bash
cd BefoldApp && git status
```
差分がなければ何もしない。`/check` の修正で差分が生じていれば:
```bash
git add -A
git commit --amend --no-edit
```
(直前のコミットと同じ作業範囲のため amend する。CLAUDE.md のコミット粒度ルールに従う)
