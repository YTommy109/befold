# リンククリックの修飾キー体系 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ビューア本文のリンク／パス参照を、クリック＝同一ウィンドウ、cmd+クリック＝別タブ（前面）、cmd+shift+クリック＝新規ウィンドウ、ctrl+クリック＝コンテキストメニュー、で開けるようにする。

**Architecture:** 修飾キー → 開き方の対応表を `OpenDisposition`（BefoldKit の純粋な enum）に集約し、JS ブリッジ経由のクリックと直接 HTML モードの `decidePolicyFor` の両方をそこへ合流させる。タブ結合は `ViewerWindowManager` の 1 メソッドへ寄せ、セッション復元経路も同じ実装を通す。コンテキストメニューは JS の `contextmenu` を新メッセージで Swift へ渡し、`NSMenu` を表示する。

**Tech Stack:** Swift 6（AppKit + SwiftUI）／Swift Testing／WKWebView + `viewer-main.js`／Jest（jsdom）

対応 Backlog タスク: TASK-239
設計: `docs/superpowers/specs/2026-07-31-link-click-modifiers-design.md`

## Global Constraints

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）。UI に触る型は `@MainActor`
- テストは Swift Testing。テスト関数名は英語 camelCase、説明は `@Test("日本語")` の表示名で付ける（SwiftLint の `identifier_name` が非 ASCII 開始の名前を弾く）
- JS のテストは Jest。`cd BefoldApp && npx jest` で実行する
- Swift のテストは `cd BefoldApp && swift test`。整形チェックは `cd BefoldApp && swift package plugin --allow-writing-to-package-directory swiftformat -- --lint`
- コミットは Conventional Commits + 日本語（例: `feat: リンクの cmd+クリックで別タブに開く`）
- JS → Swift の postMessage を追加・変更したら `ViewerBridge` のペイロードキー表を必ず更新する。`ViewerBridgeContractTests` が JS ソースを走査して突合するため、片方だけの変更はテストで落ちる
- ユーザー向け文言は `BefoldApp/befold/Resources/Localizable.xcstrings` に ja / en 両方を入れる

---

### Task 1: OpenDisposition — 修飾キーから開き方への対応表

**Files:**
- Create: `BefoldApp/BefoldKit/OpenDisposition.swift`
- Create: `BefoldApp/befoldTests/OpenDispositionTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `public enum OpenDisposition: Equatable, Sendable { case currentTab, newTab, newWindow }`、`public init(commandKey: Bool, shiftKey: Bool)`、`public init(modifiers: NSEvent.ModifierFlags)`

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/OpenDispositionTests.swift`:

```swift
import AppKit
import BefoldKit
import Testing

@Suite
struct OpenDispositionTests {
    @Test("無修飾クリックは今のウィンドウで開く")
    func plainClickOpensInCurrentTab() {
        #expect(OpenDisposition(commandKey: false, shiftKey: false) == .currentTab)
    }

    @Test("cmd+クリックは別タブで開く")
    func commandClickOpensInNewTab() {
        #expect(OpenDisposition(commandKey: true, shiftKey: false) == .newTab)
    }

    @Test("cmd+shift+クリックは新規ウィンドウで開く")
    func commandShiftClickOpensInNewWindow() {
        #expect(OpenDisposition(commandKey: true, shiftKey: true) == .newWindow)
    }

    @Test("shift 単独は無修飾と同じ扱いにする")
    func shiftAloneFallsBackToCurrentTab() {
        #expect(OpenDisposition(commandKey: false, shiftKey: true) == .currentTab)
    }

    @Test("NSEvent.ModifierFlags からも同じ対応表で解釈する")
    func modifierFlagsUseSameTable() {
        #expect(OpenDisposition(modifiers: []) == .currentTab)
        #expect(OpenDisposition(modifiers: [.command]) == .newTab)
        #expect(OpenDisposition(modifiers: [.command, .shift]) == .newWindow)
    }

    @Test("ctrl や option は開き方に影響しない")
    func otherModifiersAreIgnored() {
        #expect(OpenDisposition(modifiers: [.control, .command]) == .newTab)
        #expect(OpenDisposition(modifiers: [.option]) == .currentTab)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter OpenDispositionTests`
Expected: FAIL（`cannot find 'OpenDisposition' in scope`）

- [ ] **Step 3: 実装する**

`BefoldApp/BefoldKit/OpenDisposition.swift`:

```swift
import AppKit

/// リンクのアクティベーションに対する「開き方」。
/// 修飾キーからの解釈をここ 1 箇所に集約し、JS ブリッジ経由のクリックと
/// 直接 HTML モードの decidePolicyFor が同じ対応表を通るようにする。
public enum OpenDisposition: Equatable, Sendable {
    /// 今のウィンドウで表示を差し替える。
    case currentTab
    /// 同じウィンドウのタブグループへ追加し、そのタブを前面にする。
    case newTab
    case newWindow

    /// 修飾キーの押下状態からの解釈。cmd+shift > cmd > それ以外の順に判定する。
    /// ctrl はコンテキストメニュー扱いで呼び出し側が先に振り分けるため、ここでは無視する。
    public init(commandKey: Bool, shiftKey: Bool) {
        switch (commandKey, shiftKey) {
        case (true, true): self = .newWindow
        case (true, false): self = .newTab
        default: self = .currentTab
        }
    }

    /// AppKit のイベントからの解釈。JS 側は生の真偽値を送ってくるため入口が 2 つあるが、
    /// 判定規則そのものは commandKey/shiftKey の初期化子 1 つに閉じる。
    public init(modifiers: NSEvent.ModifierFlags) {
        self.init(commandKey: modifiers.contains(.command), shiftKey: modifiers.contains(.shift))
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter OpenDispositionTests`
Expected: PASS（6 tests）

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/BefoldKit/OpenDisposition.swift BefoldApp/befoldTests/OpenDispositionTests.swift
git commit -m "feat: 修飾キーから開き方への対応表 OpenDisposition を追加する"
```

---

### Task 2: タブとして開く経路を ViewerWindowManager に用意する

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowManager.swift`（`openViewer` に `disposition` / `relativeTo` を追加、タブ結合ヘルパーを新設）
- Modify: `BefoldApp/befold/App/SessionRestorer.swift:restoreTabGroup`（`addTabbedWindow` 直呼びをヘルパー経由へ）
- Test: `BefoldApp/befoldTests/ViewerWindowManagerTabTests.swift`（新規）

**Interfaces:**
- Consumes: `OpenDisposition`（Task 1）
- Produces:
  - `func openViewer(for url: URL, disposition: OpenDisposition = .currentTab, relativeTo sourceWindow: NSWindow? = nil, forceSidebarVisible: Bool = false, sidebarVisibleOverride: Bool? = nil, initialSortOrder: SortOrder = .foldersFirst, showLineNumbersOverride: Bool? = nil, sourceModeOverride: Bool? = nil)`
  - `func attachAsTab(_ window: NSWindow, to baseWindow: NSWindow?, select: Bool)`

`disposition` が `.currentTab` / `.newWindow` のときは従来どおり独立ウィンドウを作る（`.currentTab` の表示差し替えはコントローラ側の責務で、マネージャは「新しく開く」経路しか持たない）。`.newTab` のときだけ `sourceWindow` のタブグループへ結合する。

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/ViewerWindowManagerTabTests.swift`:

```swift
import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

/// タブ結合は実 NSWindow の tabGroup を使うため、MockedViewerWindowManager 経由で
/// 実ウィンドウを生成して検証する(store と directoryLister はモック済み)。
@Suite
@MainActor
struct ViewerWindowManagerTabTests {
    @Test("newTab で開くと起点ウィンドウのタブグループに入り選択タブになる")
    func newTabJoinsSourceTabGroup() {
        let first = URL(fileURLWithPath: "/mock/first.md")
        let second = URL(fileURLWithPath: "/mock/second.md")
        let fixture = MockedViewerWindowManager(files: [first, second], prefix: "ViewerWindowManagerTabTests")

        fixture.manager.openViewer(for: first)
        let firstWindow = fixture.manager.window(forPath: first.normalizedPathKey)
        fixture.manager.openViewer(for: second, disposition: .newTab, relativeTo: firstWindow)
        let secondWindow = fixture.manager.window(forPath: second.normalizedPathKey)

        #expect(secondWindow?.tabGroup != nil)
        #expect(secondWindow?.tabGroup === firstWindow?.tabGroup)
        #expect(secondWindow?.tabGroup?.selectedWindow === secondWindow)
        fixture.closeAll()
    }

    @Test("起点ウィンドウが無ければ独立したウィンドウとして開く")
    func newTabWithoutSourceFallsBackToWindow() {
        let file = URL(fileURLWithPath: "/mock/only.md")
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowManagerTabTests")

        fixture.manager.openViewer(for: file, disposition: .newTab, relativeTo: nil)

        #expect(fixture.manager.window(forPath: file.normalizedPathKey) != nil)
        fixture.closeAll()
    }

    @Test("newWindow は起点ウィンドウを渡してもタブ結合しない")
    func newWindowNeverJoinsTabGroup() {
        let first = URL(fileURLWithPath: "/mock/first.md")
        let second = URL(fileURLWithPath: "/mock/second.md")
        let fixture = MockedViewerWindowManager(files: [first, second], prefix: "ViewerWindowManagerTabTests")

        fixture.manager.openViewer(for: first)
        let firstWindow = fixture.manager.window(forPath: first.normalizedPathKey)
        fixture.manager.openViewer(for: second, disposition: .newWindow, relativeTo: firstWindow)
        let secondWindow = fixture.manager.window(forPath: second.normalizedPathKey)

        #expect(secondWindow?.tabGroup?.windows.contains(where: { $0 === firstWindow }) != true)
        fixture.closeAll()
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowManagerTabTests`
Expected: FAIL（`openViewer` に `disposition` 引数が無いというコンパイルエラー）

- [ ] **Step 3: 実装する**

`ViewerWindowManager.swift` の `openViewer` シグネチャへ引数を足し、コントローラ生成後・`showWindow` の前後で結合する。既存の `controller.showWindow(nil)` の直後に結合処理を置く（ウィンドウが生成済みでないと `addTabbedWindow` が効かないため）。

```swift
    func openViewer(
        for url: URL,
        disposition: OpenDisposition = .currentTab,
        relativeTo sourceWindow: NSWindow? = nil,
        forceSidebarVisible: Bool = false,
        sidebarVisibleOverride: Bool? = nil,
        initialSortOrder: SortOrder = .foldersFirst,
        showLineNumbersOverride: Bool? = nil,
        sourceModeOverride: Bool? = nil
    ) {
```

`controller.showWindow(nil)` の直後に追加:

```swift
        if disposition == .newTab, let window = controller.window {
            attachAsTab(window, to: sourceWindow, select: true)
        }
```

タブ結合の実装元をここに置く（`SessionRestorer` からも呼ぶ）:

```swift
    /// window を baseWindow のタブグループへ結合する。タブ結合の手続きはここが単一の実装元で、
    /// セッション復元(SessionRestorer.restoreTabGroup)も同じ経路を通る。
    /// baseWindow が nil のときは何もしない = 独立したウィンドウのままにする
    /// (「開けない」より「タブにならない」へ縮退させる)。
    /// - Parameter select: 結合したタブを選択状態にするか。復元時は元の選択タブを別途決めるため false。
    func attachAsTab(_ window: NSWindow, to baseWindow: NSWindow?, select: Bool) {
        guard let baseWindow, baseWindow !== window else { return }
        baseWindow.addTabbedWindow(window, ordered: .above)
        if select {
            window.tabGroup?.selectedWindow = window
        }
    }
```

`SessionRestorer.restoreTabGroup` の `previousWindow?.addTabbedWindow(window, ordered: .above)` を置き換える:

```swift
            windowManager.attachAsTab(window, to: previousWindow, select: false)
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter "ViewerWindowManagerTabTests|SessionRestorerTests"`
Expected: PASS（復元系のテストも従来どおり通ること）

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/ViewerWindowManager.swift BefoldApp/befold/App/SessionRestorer.swift BefoldApp/befoldTests/ViewerWindowManagerTabTests.swift
git commit -m "feat: ウィンドウをタブとして開く経路を ViewerWindowManager に追加する"
```

---

### Task 3: ブリッジのペイロードを修飾キーへ変え、開き方を配線する

**Files:**
- Modify: `BefoldApp/BefoldKit/ViewerBridge.swift`（`PayloadKey.ReferenceActivated` を `href` / `metaKey` / `shiftKey` へ）
- Modify: `BefoldApp/BefoldKit/Resources/viewer-main.js:246-253`（送るペイロード）
- Modify: `BefoldApp/BefoldRenderKit/ViewerRenderer.swift`（delegate 定義）、`ViewerRenderer+MessageHandling.swift:39-44`（受け取り）
- Modify: `BefoldApp/befold/App/ReferenceResolutionCoordinator.swift:59-80`、`BefoldApp/befold/App/ViewerWindowController.swift:309, 485, 507`
- Test: `BefoldApp/BefoldKit/Resources/__tests__/viewer-main.test.js:1093`（既存テストの期待値更新＋修飾キーのケース追加）、`BefoldApp/befoldTests/ViewerRendererMessageHandlingTests.swift:34`（同）

**Interfaces:**
- Consumes: `OpenDisposition`（Task 1）、`ViewerWindowManager.openViewer(for:disposition:relativeTo:)`（Task 2）
- Produces:
  - `ViewerRendererDelegate.renderer(_:didActivateReference href: String, disposition: OpenDisposition)`
  - `ReferenceResolutionCoordinator.handleOpenReference(href: String, disposition: OpenDisposition)`
  - `ReferenceResolutionHost.openReference(_ url: URL, disposition: OpenDisposition)`
  - `ViewerWindowController` の注入口 `openFileElsewhere: (URL, OpenDisposition, NSWindow?) -> Void`（旧 `openFileInNewWindow`）

- [ ] **Step 1: JS の失敗するテストを書く**

`viewer-main.test.js` の既存テスト（1093 行付近）の期待値を新ペイロードへ更新し、修飾キーのケースを足す。ヘルパー `click` は init を渡せるよう引数を追加する。

```javascript
  function click(loaded, selector, init) {
    dispatchTrustedClick(loaded.window, loaded.document.querySelector(selector), init);
  }

  test('解決済みのパス参照はクリックで referenceActivated を送る', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['resolveReferences', 'referenceActivated']);
    await loaded.main.render('src/a.swift\n', 'code', 'txt');
    loaded.main._mmdApplyResolvedReferences({ 'src/a.swift': '/repo/src/a.swift' });

    click(loaded, '#diagram-wrap .befold-path-ref');

    expect(received.filter((m) => m.name === 'referenceActivated').map((m) => m.payload))
      .toEqual([{ href: 'src/a.swift', metaKey: false, shiftKey: false }]);
  });

  test('修飾キーの押下状態をそのまま referenceActivated に載せる', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['resolveReferences', 'referenceActivated']);
    await loaded.main.render('src/a.swift\n', 'code', 'txt');
    loaded.main._mmdApplyResolvedReferences({ 'src/a.swift': '/repo/src/a.swift' });

    click(loaded, '#diagram-wrap .befold-path-ref', { metaKey: true });
    click(loaded, '#diagram-wrap .befold-path-ref', { metaKey: true, shiftKey: true });

    expect(received.filter((m) => m.name === 'referenceActivated').map((m) => m.payload))
      .toEqual([
        { href: 'src/a.swift', metaKey: true, shiftKey: false },
        { href: 'src/a.swift', metaKey: true, shiftKey: true },
      ]);
  });
```

同ファイル内の「外部 URL と # アンカー」テスト（1105 行付近）の期待値も
`{ href: 'https://example.com/a.md', metaKey: false, shiftKey: false }` へ更新する。

- [ ] **Step 2: JS テストが失敗することを確認する**

Run: `cd BefoldApp && npx jest viewer-main`
Expected: FAIL（`newWindow: false` を受け取り、`metaKey` が無い）

- [ ] **Step 3: JS 側を実装する**

`viewer-main.js` の該当箇所（246-253 行）:

```javascript
      // <a> / .befold-path-ref とも同じ挙動。修飾キーの解釈は Swift 側(OpenDisposition)に
      // 集約しているため、ここでは押下状態をそのまま送るだけにする。
      _mmdPostMessage(_MSG_REFERENCE_ACTIVATED, {
        href: href,
        metaKey: e.metaKey,
        shiftKey: e.shiftKey
      });
```

- [ ] **Step 4: JS テストが通ることを確認する**

Run: `cd BefoldApp && npx jest viewer-main`
Expected: PASS

- [ ] **Step 5: Swift の失敗するテストを書く**

`ViewerRendererMessageHandlingTests.swift` の `referenceActivatedDispatchesReference`（34 行付近）を新ペイロードへ更新し、cmd+shift のケースを足す。スタブ（`ViewerRendererMessageStubs.swift`）の `onOpenReference` が受け取る値も `OpenDisposition` に変える。

```swift
    @Test("referenceActivated が href と修飾キーから開き方を決めて渡す")
    func referenceActivatedDispatchesReference() {
        let (renderer, delegate) = makeRenderer()

        send(
            renderer, name: ViewerBridge.referenceActivatedMessageName,
            body: ["href": "docs/a.md", "metaKey": true, "shiftKey": false]
        )

        #expect(delegate.openedReferences.map(\.href) == ["docs/a.md"])
        #expect(delegate.openedReferences.map(\.disposition) == [.newTab])
    }
```

- [ ] **Step 6: Swift テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter ViewerRendererMessageHandlingTests`
Expected: FAIL（`disposition` が無いというコンパイルエラー）

- [ ] **Step 7: Swift 側を実装する**

`ViewerBridge.swift`（16-17 行のコメントと 287-291 行のキー）:

```swift
    /// リンクやパス参照がクリックされたときに postMessage されるメッセージハンドラ名。
    /// 修飾キーの解釈は Swift 側(OpenDisposition)が行うため、JS は押下状態のみ送る。
    /// payload: { href: String, metaKey: Bool, shiftKey: Bool }
    public static let referenceActivatedMessageName = "referenceActivated"
```

```swift
        /// referenceActivated のキー。
        public enum ReferenceActivated: String, CaseIterable, Sendable {
            case href
            case metaKey
            case shiftKey
        }
```

`ViewerRenderer.swift` の delegate 定義（17 行・29 行）:

```swift
    func renderer(_ renderer: ViewerRenderer, didActivateReference href: String, disposition: OpenDisposition)
```

```swift
    func renderer(_: ViewerRenderer, didActivateReference _: String, disposition _: OpenDisposition) {}
```

`ViewerRenderer+MessageHandling.swift`（39-44 行）:

```swift
        } else if message.name == ViewerBridge.referenceActivatedMessageName,
                  let body = message.body as? [String: Any],
                  let href = body[ReferenceKey.href.rawValue] as? String,
                  let metaKey = body[ReferenceKey.metaKey.rawValue] as? Bool,
                  let shiftKey = body[ReferenceKey.shiftKey.rawValue] as? Bool
        {
            delegate?.renderer(
                self, didActivateReference: href,
                disposition: OpenDisposition(commandKey: metaKey, shiftKey: shiftKey)
            )
        }
```

`ReferenceResolutionCoordinator.swift`（13 行のプロトコル・59 行・72 行）:

```swift
    func openReference(_ url: URL, disposition: OpenDisposition)
```

```swift
    func handleOpenReference(href: String, disposition: OpenDisposition) {
```

```swift
                host.openReference(url, disposition: disposition)
```

`ViewerWindowController.swift`:

```swift
    // 309 行付近
    func handleOpenReference(href: String, disposition: OpenDisposition) {
        referenceCoordinator.handleOpenReference(href: href, disposition: disposition)
    }

    // 485 行付近
    func renderer(_: ViewerRenderer, didActivateReference href: String, disposition: OpenDisposition) {
        handleOpenReference(href: href, disposition: disposition)
    }

    // 507 行付近
    func openReference(_ url: URL, disposition: OpenDisposition) {
        switch disposition {
        case .currentTab:
            switchFile(to: url)
        case .newTab, .newWindow:
            openFileElsewhere(url, disposition, window)
        }
    }
```

注入口の型を変える（47 行の保持プロパティ、128 行の init 引数、113 行のドキュメントコメント）:

```swift
    /// 別のタブ/ウィンドウでファイルを開く処理。タブ結合の基準にするため自分のウィンドウも渡す。
    /// 本番では ViewerWindowManager 経由で注入する。
    private let openFileElsewhere: (URL, OpenDisposition, NSWindow?) -> Void
```

```swift
        openFileElsewhere: @escaping (URL, OpenDisposition, NSWindow?) -> Void = { url, disposition, source in
            AppDelegate.shared?.openViewer(for: url, disposition: disposition, relativeTo: source)
        }
```

`ViewerWindowManager.swift`（219 行付近の注入）:

```swift
            openFileElsewhere: { [weak self] fileURL, disposition, sourceWindow in
                self?.openViewer(for: fileURL, disposition: disposition, relativeTo: sourceWindow)
            }
```

サイドバーの「新しいウィンドウで開く」（`FileListView` の `onOpenInNewWindow`、`ViewerWindowController.swift:281` 付近）は
`openFileElsewhere(url, .newWindow, window)` を呼ぶ形に直す（挙動は不変）。

`AppDelegate.openViewer` にも受け口を足す（既存の `openViewer(for:)` は `.currentTab` のまま）:

```swift
    func openViewer(for url: URL, disposition: OpenDisposition, relativeTo sourceWindow: NSWindow?) {
        Task {
            await openViewer(
                for: url, options: CLIOpenOptions(),
                disposition: disposition, relativeTo: sourceWindow
            )
        }
    }
```

`private func openViewer(for:options:)` に `disposition` / `relativeTo` を追加し、
`windowManager.openViewer` へそのまま渡す（既定値は `.currentTab` / `nil`）。

- [ ] **Step 8: Swift テストが通ることを確認する**

Run: `cd BefoldApp && swift test`
Expected: PASS（`ViewerBridgeContractTests` が JS とキー表の突合に成功すること）

- [ ] **Step 9: コミット**

```bash
git add -A
git commit -m "feat: リンククリックの修飾キーで別タブ・新規ウィンドウを開き分ける"
```

---

### Task 4: 直接 HTML モードのリンクも同じ対応表に載せる

**Files:**
- Modify: `BefoldApp/BefoldRenderKit/ViewerRenderer+DirectHTMLLinkPolicy.swift:39-40, 55, 63-87`
- Test: `BefoldApp/befoldTests/DirectHTMLLinkPolicyTests.swift`

**Interfaces:**
- Consumes: `OpenDisposition`（Task 1）、`didActivateReference(_:disposition:)`（Task 3）
- Produces: `DirectHTMLLinkAction.openLocalFile(url: URL, disposition: OpenDisposition)`

- [ ] **Step 1: 失敗するテストを書く**

`DirectHTMLLinkPolicyTests.swift` に追記（既存の `newWindow: Bool` を期待しているケースも新形へ更新する）:

```swift
    @Test("直接 HTML モードでも cmd+クリックは別タブ、cmd+shift+クリックは新規ウィンドウになる")
    func directHTMLLinkUsesSharedDispositionTable() {
        let target = URL(fileURLWithPath: "/repo/docs/a.html")

        #expect(
            ViewerRenderer.directHTMLLinkPolicy(url: target, currentURL: nil, modifierFlags: [.command])
                == .openLocalFile(url: target, disposition: .newTab)
        )
        #expect(
            ViewerRenderer.directHTMLLinkPolicy(url: target, currentURL: nil, modifierFlags: [.command, .shift])
                == .openLocalFile(url: target, disposition: .newWindow)
        )
        #expect(
            ViewerRenderer.directHTMLLinkPolicy(url: target, currentURL: nil, modifierFlags: [])
                == .openLocalFile(url: target, disposition: .currentTab)
        )
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter DirectHTMLLinkPolicyTests`
Expected: FAIL（`openLocalFile` に `disposition` ラベルが無いというコンパイルエラー）

- [ ] **Step 3: 実装する**

```swift
    enum DirectHTMLLinkAction: Equatable {
        case allowNativeNavigation
        case openLocalFile(url: URL, disposition: OpenDisposition)
        case openExternal(url: URL)
        case ignore
    }
```

```swift
        if url.isFileURL {
            let cleanURL = url.fragment != nil ? url.deletingFragment() : url
            return .openLocalFile(url: cleanURL, disposition: OpenDisposition(modifiers: modifierFlags))
        }
```

```swift
        case let .openLocalFile(fileURL, disposition):
            delegate?.renderer(self, didActivateReference: fileURL.path, disposition: disposition)
            return .cancel
```

62 行のドキュメントコメントの「cmd 修飾の有無に応じて同一/新規ウィンドウを判断する」を
「修飾キーの解釈は OpenDisposition に委ねる」へ直す。

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter DirectHTMLLinkPolicyTests`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/BefoldRenderKit/ViewerRenderer+DirectHTMLLinkPolicy.swift BefoldApp/befoldTests/DirectHTMLLinkPolicyTests.swift
git commit -m "feat: 直接 HTML モードのリンクも共通の開き方の対応表に載せる"
```

---

### Task 5: ctrl+クリックのコンテキストメニュー

**Files:**
- Create: `BefoldApp/befold/App/ReferenceContextMenu.swift`（メニュー項目の組み立て）
- Create: `BefoldApp/befoldTests/ReferenceContextMenuTests.swift`
- Modify: `BefoldApp/BefoldKit/ViewerBridge.swift`（`referenceContextMenuMessageName` とキー表）
- Modify: `BefoldApp/BefoldKit/Resources/viewer-main.js`（`contextmenu` ハンドラ）
- Modify: `BefoldApp/BefoldRenderKit/ViewerRenderer.swift`、`ViewerRenderer+MessageHandling.swift`（メッセージ登録と配送）
- Modify: `BefoldApp/befold/App/ReferenceResolutionCoordinator.swift`、`BefoldApp/befold/App/ViewerWindowController.swift`（メニュー表示）
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`（`sidebar.context.open` / `sidebar.context.openInNewTab` を追加）
- Test: `BefoldApp/BefoldKit/Resources/__tests__/viewer-main.test.js`

**Interfaces:**
- Consumes: `OpenDisposition`（Task 1）、`ReferenceResolutionCoordinator`（Task 3）
- Produces:
  - `ViewerBridge.referenceContextMenuMessageName = "referenceContextMenu"`、payload `{ href: String }`
  - `ViewerRendererDelegate.renderer(_:didRequestContextMenuFor href: String)`
  - `enum ReferenceContextMenu { static func items(isExternal: Bool) -> [Item] }`、
    `struct Item { let titleKey: String; let action: Action; let isEnabled: Bool }`、
    `enum Action { case open(OpenDisposition), revealInFinder, copyName, copyRelativePath }`

- [ ] **Step 1: メニュー項目の失敗するテストを書く**

`BefoldApp/befoldTests/ReferenceContextMenuTests.swift`:

```swift
@testable import befold
import BefoldKit
import Testing

@Suite
struct ReferenceContextMenuTests {
    @Test("ローカルファイルでは 6 項目すべてが有効になる")
    func localFileEnablesEveryItem() {
        let items = ReferenceContextMenu.items(isExternal: false)

        #expect(items.map(\.action) == [
            .open(.currentTab), .open(.newTab), .open(.newWindow),
            .revealInFinder, .copyName, .copyRelativePath,
        ])
        #expect(items.allSatisfy(\.isEnabled))
    }

    @Test("外部 URL では Finder で開くと相対パスのコピーを無効にする")
    func externalURLDisablesFileOnlyItems() {
        let items = ReferenceContextMenu.items(isExternal: true)

        let disabled = items.filter { !$0.isEnabled }.map(\.action)
        #expect(disabled == [.revealInFinder, .copyRelativePath])
    }

    @Test("項目の文言はサイドバーのコンテキストメニューと同じキーを使う")
    func titlesReuseSidebarKeys() {
        let keys = ReferenceContextMenu.items(isExternal: false).map(\.titleKey)

        #expect(keys == [
            "sidebar.context.open",
            "sidebar.context.openInNewTab",
            "sidebar.context.openInNewWindow",
            "sidebar.context.revealInFinder",
            "sidebar.context.copy",
            "sidebar.context.copyPath",
        ])
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter ReferenceContextMenuTests`
Expected: FAIL（`cannot find 'ReferenceContextMenu' in scope`）

- [ ] **Step 3: メニュー項目を実装する**

`BefoldApp/befold/App/ReferenceContextMenu.swift`:

```swift
import BefoldKit
import Foundation

/// ビューア本文のリンク/パス参照に対するコンテキストメニューの項目定義。
/// 並びと文言をサイドバーのコンテキストメニューへ揃えるため、項目の組み立てをここに集約する
/// (NSMenu への変換は ViewerWindowController が行う)。
enum ReferenceContextMenu {
    enum Action: Equatable {
        case open(OpenDisposition)
        case revealInFinder
        case copyName
        case copyRelativePath
    }

    struct Item: Equatable {
        let titleKey: String
        let action: Action
        let isEnabled: Bool
    }

    /// - Parameter isExternal: 対象が http/https の外部 URL か。
    ///   外部 URL にはローカルパスが無いため、Finder と相対パスのコピーを無効にする。
    static func items(isExternal: Bool) -> [Item] {
        [
            Item(titleKey: "sidebar.context.open", action: .open(.currentTab), isEnabled: true),
            Item(titleKey: "sidebar.context.openInNewTab", action: .open(.newTab), isEnabled: true),
            Item(titleKey: "sidebar.context.openInNewWindow", action: .open(.newWindow), isEnabled: true),
            Item(titleKey: "sidebar.context.revealInFinder", action: .revealInFinder, isEnabled: !isExternal),
            Item(titleKey: "sidebar.context.copy", action: .copyName, isEnabled: true),
            Item(titleKey: "sidebar.context.copyPath", action: .copyRelativePath, isEnabled: !isExternal),
        ]
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter ReferenceContextMenuTests`
Expected: PASS

- [ ] **Step 5: 文言を追加する**

`BefoldApp/befold/Resources/Localizable.xcstrings` に 2 キーを足す（既存キーと同じ構造で ja / en を入れる）:

- `sidebar.context.open` — ja「開く」/ en「Open」
- `sidebar.context.openInNewTab` — ja「別タブで開く」/ en「Open in New Tab」

- [ ] **Step 6: JS の失敗するテストを書く**

`viewer-main.test.js` の参照クリックの describe に追記する。ハーネスに
`dispatchTrustedContextMenu` を足す（`viewerMainHarness.js` の `dispatchTrustedClick` を
イベント種別で一般化し、両方を export する）。

```javascript
  test('リンク上の contextmenu は既定メニューを抑止して referenceContextMenu を送る', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['resolveReferences', 'referenceContextMenu']);
    await loaded.main.render('src/a.swift\n', 'code', 'txt');
    loaded.main._mmdApplyResolvedReferences({ 'src/a.swift': '/repo/src/a.swift' });

    const event = dispatchTrustedContextMenu(
      loaded.window, loaded.document.querySelector('#diagram-wrap .befold-path-ref')
    );

    expect(event.defaultPrevented).toBe(true);
    expect(received.filter((m) => m.name === 'referenceContextMenu').map((m) => m.payload))
      .toEqual([{ href: 'src/a.swift' }]);
  });

  test('リンク以外の contextmenu は既定メニューのまま何も送らない', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['referenceContextMenu']);
    await loaded.main.render('ただの本文\n', 'code', 'txt');

    const event = dispatchTrustedContextMenu(
      loaded.window, loaded.document.getElementById('diagram-wrap')
    );

    expect(event.defaultPrevented).toBe(false);
    expect(received).toEqual([]);
  });
```

- [ ] **Step 7: JS テストが失敗することを確認する**

Run: `cd BefoldApp && npx jest viewer-main`
Expected: FAIL（`referenceContextMenu` が送られない）

- [ ] **Step 8: JS 側を実装する**

`viewer-main.js` の先頭のメッセージ名定義に追加:

```javascript
  var _MSG_REFERENCE_CONTEXT_MENU = 'referenceContextMenu';
```

`_mmdInitReferenceClicks` の中に、クリックハンドラと同じ要素判定を共有する形で追加する。
判定部分（`.closest('a')` / `.closest('.befold-path-ref')` と pending/dead の除外）は
`_mmdReferenceTargetHref(e)` という関数に切り出し、click と contextmenu の両方から呼ぶ。

```javascript
    document.getElementById('diagram-wrap').addEventListener('contextmenu', function(e) {
      if (!e.isTrusted) return;
      if (!isHostFeatureEnabled(window._mmdHostFeatures, 'referenceActivation')) { return; }
      var href = _mmdReferenceTargetHref(e);
      // リンク/パス参照の上でなければ WKWebView 既定のメニューに任せる。
      if (!href || href.charAt(0) === '#') { return; }
      e.preventDefault();
      _mmdPostMessage(_MSG_REFERENCE_CONTEXT_MENU, { href: href });
    });
```

- [ ] **Step 9: JS テストが通ることを確認する**

Run: `cd BefoldApp && npx jest viewer-main`
Expected: PASS

- [ ] **Step 10: ブリッジと配送を実装する**

`ViewerBridge.swift`:

```swift
    /// リンクやパス参照の上で ctrl+クリック(右クリック)されたときに postMessage される
    /// メッセージハンドラ名。Swift 側が NSMenu を表示する。
    /// payload: { href: String }
    public static let referenceContextMenuMessageName = "referenceContextMenu"
```

`PayloadKey` に追加し、`payloadKeysByMessageName` にも登録する（登録漏れは契約テストで落ちる）:

```swift
        /// referenceContextMenu のキー。
        public enum ReferenceContextMenu: String, CaseIterable, Sendable {
            case href
        }
```

```swift
        referenceContextMenuMessageName: Set(PayloadKey.ReferenceContextMenu.allCases.map(\.rawValue)),
```

`ViewerRenderer.messageHandlerNames` の `allowsInteractiveBridging` ブロックへ
`names.append(ViewerBridge.referenceContextMenuMessageName)` を足し、
delegate に `func renderer(_ renderer: ViewerRenderer, didRequestContextMenuFor href: String)`
（既定実装は空）を追加、`ViewerRenderer+MessageHandling.swift` に分岐を足す。

- [ ] **Step 11: メニュー表示を実装する**

`ReferenceResolutionCoordinator` に、href を解決してホストへ渡す入口を足す:

```swift
    /// コンテキストメニュー要求を処理する。解決できない参照ではメニューを出さない
    /// (クリックが無反応なのと揃える)。
    func handleContextMenu(href: String) {
        guard let host else { return }
        let resolver = resolver
        let baseURL = host.referenceBaseURL
        Task {
            let reference = await Task.detached(priority: .userInitiated) {
                resolver.resolve(href: href, baseURL: baseURL)
            }.value
            guard let host = self.host else { return }
            switch reference {
            case let .external(url):
                host.presentReferenceContextMenu(for: url, isExternal: true)
            case let .resolved(url):
                host.presentReferenceContextMenu(for: url, isExternal: false)
            case .unresolved, .ignored:
                break
            }
        }
    }
```

`ReferenceResolutionHost` に `func presentReferenceContextMenu(for url: URL, isExternal: Bool)` を足し、
`ViewerWindowController` で実装する。表示位置は JS の座標を使わず、現在のマウス位置を使う
（WKWebView の CSS ピクセルと NSView 座標の変換、ページズームの影響を避けるため）:

```swift
    func presentReferenceContextMenu(for url: URL, isExternal: Bool) {
        guard let contentView = window?.contentView,
              let location = window?.mouseLocationOutsideOfEventStream
        else { return }
        let menu = NSMenu()
        for item in ReferenceContextMenu.items(isExternal: isExternal) {
            let menuItem = NSMenuItem(
                title: String(localized: String.LocalizationValue(item.titleKey), bundle: .l10n),
                action: #selector(performReferenceMenuAction(_:)), keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.isEnabled = item.isEnabled
            menuItem.representedObject = ReferenceMenuInvocation(url: url, action: item.action)
            menu.addItem(menuItem)
            if item.action == .open(.newWindow) || item.action == .revealInFinder {
                menu.addItem(.separator())
            }
        }
        menu.popUp(positioning: nil, at: contentView.convert(location, from: nil), in: contentView)
    }
```

`representedObject` に載せる値は `ReferenceContextMenu.swift` に定義する:

```swift
/// メニュー項目 1 つが実行時に必要とする情報。NSMenuItem.representedObject へ載せる。
final class ReferenceMenuInvocation: NSObject {
    let url: URL
    let action: ReferenceContextMenu.Action

    init(url: URL, action: ReferenceContextMenu.Action) {
        self.url = url
        self.action = action
    }
}
```

`ViewerWindowController` 側の受け口:

```swift
    @objc private func performReferenceMenuAction(_ sender: NSMenuItem) {
        guard let invocation = sender.representedObject as? ReferenceMenuInvocation else { return }
        switch invocation.action {
        case let .open(disposition):
            openReference(invocation.url, disposition: disposition)
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([invocation.url])
        case .copyName:
            writeToPasteboard(invocation.url.lastPathComponent)
        case .copyRelativePath:
            writeToPasteboard(PathRelativizer.relativePath(of: invocation.url, relativeTo: referenceBaseURL))
        }
    }
```

アクションの実行は既存の処理へ委譲する（`open` は `openReference(url, disposition:)`、
`revealInFinder` は `NSWorkspace.shared.activateFileViewerSelecting([url])`、
`copyName` / `copyRelativePath` は `FileListView` が使っているのと同じ
`NSPasteboard.general` への書き込みと `PathRelativizer.relativePath(of:relativeTo:)`）。

- [ ] **Step 12: 全テストと整形チェックを通す**

Run: `cd BefoldApp && swift test && npx jest && swift package plugin --allow-writing-to-package-directory swiftformat -- --lint`
Expected: すべて PASS / 0 files require formatting

- [ ] **Step 13: コミット**

```bash
git add -A
git commit -m "feat: リンクの ctrl+クリックで開き方を選べるコンテキストメニューを出す"
```

---

## 手動チェック（実装後）

自動テストで担保できない項目。dev ビルドで確認する。

- [ ] cmd+クリックで開いたタブが、元のウィンドウのタブバーに並び、前面になる
- [ ] cmd+shift+クリックが独立したウィンドウとして開く
- [ ] ctrl+クリック／右クリックでメニューがマウス位置に出る（WKWebView 既定メニューが出ない）
- [ ] 外部 URL 上のメニューで「Finder で開く」「相対パスをコピーする」がグレーアウトする
- [ ] 解決待ち・解決失敗のパス参照では、クリックもメニューも反応しない
- [ ] 直接 HTML モード（.html ファイルを開いた状態）のリンクでも同じ 3 通りが効く
