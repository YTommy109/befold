# ファイル毎のウィンドウ状態・表示倍率の復元 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ウィンドウのサイズ・位置・表示倍率をファイル毎に保存し、再起動時に復元する。

**Architecture:** ウィンドウフレームは既存の NSWindow autosave（ファイルパス毎）を活かし、復元を上書きしていた `center()` を初回のみに限定する。表示倍率は新規 `ZoomStore`（UserDefaults、`SessionStore` と同パターン）にファイルパス毎で保存し、JS→Swift は `WKScriptMessageHandler`、Swift→JS は `WKUserScript` による初期値注入で橋渡しする。

**Tech Stack:** Swift 6 / AppKit + SwiftUI / WKWebView / Swift Testing / Jest

**Spec:** `docs/superpowers/specs/2026-07-03-per-file-window-state-design.md`

## Global Constraints

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）、macOS 14+
- テスト関数名は英語 camelCase（日本語説明は `@Test("...")` の表示名で付ける）
- コミットは Conventional Commits + 日本語（例: `feat: ...を追加する`）
- 倍率の仕様値: 最小 0.5 / 最大 2.0 / デフォルト 1.0（`viewer.js` の `ZOOM_MIN`/`ZOOM_MAX`/`ZOOM_DEFAULT` と同値）
- UserDefaults キー: 倍率は `ViewerZoomLevels`（`[正規化パス: Double]` の辞書）
- パス正規化は `url.resolvingSymlinksInPath().path`（`SessionStore` と同一）
- Swift のビルド・テストは `MmdviewApp/` ディレクトリで実行（`swift build` / `swift test`、要 Xcode.app）
- JS テストは `MmdviewApp/` ディレクトリで `npm test`（Jest）

---

### Task 1: ZoomStore（ファイル毎の倍率永続化）

**Files:**
- Create: `MmdviewApp/mmdview/App/ZoomStore.swift`
- Test: `MmdviewApp/mmdviewTests/ZoomStoreTests.swift`

**Interfaces:**
- Consumes: なし（Foundation のみ）
- Produces: `@MainActor final class ZoomStore`
  - `init(defaults: UserDefaults = .standard)`
  - `func zoom(for url: URL) -> Double` — 保存がなければ `1.0`、範囲外は 0.5〜2.0 に clamp
  - `func setZoom(_ zoom: Double, for url: URL)`
  - `static let defaultZoom = 1.0`

- [ ] **Step 1: 失敗するテストを書く**

`MmdviewApp/mmdviewTests/ZoomStoreTests.swift` を新規作成:

```swift
import Foundation
import Testing
@testable import mmdview

@Suite
@MainActor
struct ZoomStoreTests {
    /// テストごとに独立した UserDefaults スイートを用意する。
    private func makeDefaults() -> UserDefaults {
        let suiteName = "ZoomStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test
    func zoomIsDefaultWhenUnsaved() {
        let store = ZoomStore(defaults: makeDefaults())

        #expect(store.zoom(for: URL(fileURLWithPath: "/tmp/diagram.mmd")) == 1.0)
    }

    @Test
    func setZoomPersistsPerFileAcrossInstances() {
        let defaults = makeDefaults()
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")

        ZoomStore(defaults: defaults).setZoom(1.5, for: url)

        #expect(ZoomStore(defaults: defaults).zoom(for: url) == 1.5)
    }

    @Test
    func zoomsAreIndependentPerFile() {
        let defaults = makeDefaults()
        let first = URL(fileURLWithPath: "/tmp/first.mmd")
        let second = URL(fileURLWithPath: "/tmp/second.md")
        let store = ZoomStore(defaults: defaults)

        store.setZoom(0.75, for: first)
        store.setZoom(2.0, for: second)

        #expect(store.zoom(for: first) == 0.75)
        #expect(store.zoom(for: second) == 2.0)
    }

    @Test("範囲外の保存値は読み取り時に 0.5〜2.0 に丸められる")
    func outOfRangeZoomIsClampedOnRead() {
        let defaults = makeDefaults()
        let tooBig = URL(fileURLWithPath: "/tmp/big.mmd")
        let tooSmall = URL(fileURLWithPath: "/tmp/small.mmd")
        let store = ZoomStore(defaults: defaults)

        store.setZoom(5.0, for: tooBig)
        store.setZoom(0.1, for: tooSmall)

        #expect(store.zoom(for: tooBig) == 2.0)
        #expect(store.zoom(for: tooSmall) == 0.5)
    }

    @Test("シンボリックリンク経由でも同一ファイルとして扱う")
    func symlinkResolvesToSamePath() throws {
        let defaults = makeDefaults()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZoomStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real.mmd")
        try Data().write(to: real)
        let link = dir.appendingPathComponent("link.mmd")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let store = ZoomStore(defaults: defaults)

        store.setZoom(1.25, for: link)

        #expect(store.zoom(for: real) == 1.25)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter ZoomStoreTests`
Expected: コンパイルエラー（`cannot find 'ZoomStore' in scope`）で FAIL

- [ ] **Step 3: 最小実装を書く**

`MmdviewApp/mmdview/App/ZoomStore.swift` を新規作成:

```swift
import Foundation

/// ファイル毎の表示倍率を UserDefaults に永続化し、再起動後の復元に使う。
/// パスはシンボリックリンク解決後の絶対パスで正規化して保持する。
@MainActor
final class ZoomStore {
    static let defaultZoom = 1.0
    /// viewer.js の ZOOM_MIN / ZOOM_MAX と同値。
    static let minZoom = 0.5
    static let maxZoom = 2.0
    private static let defaultsKey = "ViewerZoomLevels"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 指定ファイルの保存済み倍率を返す。保存がなければデフォルト、範囲外は clamp する。
    func zoom(for url: URL) -> Double {
        guard let zoom = savedZooms()[Self.normalize(url)] else { return Self.defaultZoom }
        return min(Self.maxZoom, max(Self.minZoom, zoom))
    }

    /// 指定ファイルの倍率を保存する。
    func setZoom(_ zoom: Double, for url: URL) {
        var zooms = savedZooms()
        zooms[Self.normalize(url)] = zoom
        defaults.set(zooms, forKey: Self.defaultsKey)
    }

    private func savedZooms() -> [String: Double] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
    }

    private static func normalize(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter ZoomStoreTests`
Expected: 5 件すべて PASS

- [ ] **Step 5: コミット**

```bash
git add MmdviewApp/mmdview/App/ZoomStore.swift MmdviewApp/mmdviewTests/ZoomStoreTests.swift
git commit -m "feat: ファイル毎の表示倍率を保存する ZoomStore を追加する"
```

---

### Task 2: viewer.html を初期値注入 + zoomChanged 通知方式に変更する

**Files:**
- Modify: `MmdviewApp/mmdview/Resources/viewer.html:30-42`
- Test: `MmdviewApp/mmdview/Resources/__tests__/viewer.test.js`

**Interfaces:**
- Consumes: `window._mmdInitialZoom`（Task 3 の WKUserScript が数値をセットする。未定義なら 1.0 扱い）
- Produces: `webkit.messageHandlers.zoomChanged.postMessage(<数値>)` — 倍率が適用されるたびに送信（Task 3 の Swift 側が受信する）

注意: このタスク完了時点では Swift 側の注入・受信（Task 3）が未実装のため、倍率の永続化は一時的に無効になる（アプリはデフォルト 100% で動作）。ブランチ内で Task 3 が続くため許容する。

- [ ] **Step 1: 失敗するテストを書く**

`viewer.test.js` の `describe('parseStoredZoom', ...)` ブロック内に追加
（注入値は localStorage の文字列ではなく数値で渡るため、その回帰を防ぐ）:

```js
  test('parses injected numeric value', () => {
    expect(parseStoredZoom(1.25)).toBe(1.25);
    expect(parseStoredZoom(1)).toBe(1);
  });
```

- [ ] **Step 2: テストを実行する**

Run: `cd MmdviewApp && npm test`
Expected: PASS（`parseFloat` は数値も受け付けるため既存実装で通る。通ることを確認して次へ。
もし FAIL する場合のみ `viewer.js` の `parseStoredZoom` を修正する）

- [ ] **Step 3: viewer.html を書き換える**

`viewer.html` の `_mmdInitZoom` を localStorage 読み取りから注入値読み取りに変更:

```js
  function _mmdInitZoom() {
    _mmdZoom = parseStoredZoom(window._mmdInitialZoom);
    _mmdApplyZoom();
  }
```

`_mmdApplyZoom` の `localStorage.setItem('mmdview.viewer.zoom', _mmdZoom);` 行を
ネイティブ通知に置き換える（webkit が無い環境でも動くようガードする）:

```js
  function _mmdApplyZoom() {
    _mmdZoom = clampZoom(_mmdZoom);
    document.getElementById('diagram-wrap').style.zoom = effectiveZoom(_mmdZoom);
    document.getElementById('zoom-label').textContent = zoomLabel(_mmdZoom);
    document.getElementById('zoom-in').disabled = _mmdZoom >= ZOOM_MAX;
    document.getElementById('zoom-out').disabled = _mmdZoom <= ZOOM_MIN;
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.zoomChanged) {
      window.webkit.messageHandlers.zoomChanged.postMessage(_mmdZoom);
    }
  }
```

これで `mmdview.viewer.zoom`（localStorage）への参照は viewer.html から消える。

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && npm test`
Expected: 全件 PASS

- [ ] **Step 5: コミット**

```bash
git add MmdviewApp/mmdview/Resources/viewer.html MmdviewApp/mmdview/Resources/__tests__/viewer.test.js
git commit -m "feat: 表示倍率の保存を localStorage からネイティブ通知に変更する"
```

---

### Task 3: Swift ブリッジ配線（初期倍率の注入と変更の受信）

**Files:**
- Modify: `MmdviewApp/mmdview/Viewer/ViewerWebView.swift`
- Modify: `MmdviewApp/mmdview/Viewer/ViewerContentView.swift`
- Modify: `MmdviewApp/mmdview/App/ViewerWindowController.swift:13-36`
- Modify: `MmdviewApp/mmdview/App/AppDelegate.swift:9, 98`

**Interfaces:**
- Consumes: Task 1 の `ZoomStore.zoom(for:)` / `ZoomStore.setZoom(_:for:)`、Task 2 の `window._mmdInitialZoom` / `zoomChanged` メッセージ
- Produces: `ViewerWindowController.init(fileURL: URL, zoomStore: ZoomStore)`（AppDelegate が使用）

このタスクは GUI 層（WebView ブリッジ）のためユニットテスト対象外（プロジェクト規約）。ビルド成功と Task 5 の手動確認で検証する。

- [ ] **Step 1: ViewerWebView に initialZoom / onZoomChanged を追加する**

`ViewerWebView.swift` — プロパティ追加と `makeNSView` の変更:

```swift
struct ViewerWebView: NSViewRepresentable {
    let content: String
    let fileType: FileType
    let isDeleted: Bool
    /// ロード時に JS へ注入するファイル毎の初期倍率。
    let initialZoom: Double
    /// JS 側で倍率が変わったときに呼ばれる。
    let onZoomChanged: @MainActor (Double) -> Void

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let zoomScript = WKUserScript(
            source: "window._mmdInitialZoom = \(initialZoom);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(zoomScript)
        config.userContentController.add(context.coordinator, name: "zoomChanged")
        context.coordinator.onZoomChanged = onZoomChanged

        let webView = WKWebView(frame: .zero, configuration: config)
        // ... 以降は既存のまま（navigationDelegate / drawsBackground / loadFileURL）
```

`updateNSView` / `makeCoordinator` は変更なし。`makeCoordinator` の下に
message handler の解除を追加（userContentController → Coordinator の強参照を断つ）:

```swift
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "zoomChanged")
    }
```

- [ ] **Step 2: Coordinator に WKScriptMessageHandler を実装する**

`Coordinator` の宣言と実装に追加:

```swift
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        var onZoomChanged: (@MainActor (Double) -> Void)?
        // ... 既存プロパティはそのまま

        // MARK: - WKScriptMessageHandler

        @MainActor
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "zoomChanged",
                  let zoom = (message.body as? NSNumber)?.doubleValue else { return }
            onZoomChanged?(zoom)
        }
    }
```

補足: SDK の `WKScriptMessageHandler` 要件が nonisolated でコンパイルエラーになる場合は、
メソッドの `@MainActor` を外し、本文を
`MainActor.assumeIsolated { onZoomChanged?(zoom) }` に変える（WebKit はメインスレッドで呼ぶ）。
その場合 `onZoomChanged` プロパティへのアクセスも同ブロック内に含めること。

- [ ] **Step 3: ViewerContentView にプロパティを引き回す**

`ViewerContentView.swift` 全体:

```swift
import SwiftUI

struct ViewerContentView: View {
    var store: ViewerStore
    let initialZoom: Double
    let onZoomChanged: @MainActor (Double) -> Void

    var body: some View {
        ViewerWebView(
            content: store.content,
            fileType: store.fileType,
            isDeleted: store.isDeleted,
            initialZoom: initialZoom,
            onZoomChanged: onZoomChanged
        )
    }
}
```

- [ ] **Step 4: ViewerWindowController が ZoomStore を受け取り接続する**

`ViewerWindowController.swift` の init シグネチャと contentView 生成を変更:

```swift
    init(fileURL: URL, zoomStore: ZoomStore) {
```

```swift
        let contentView = ViewerContentView(
            store: store,
            initialZoom: zoomStore.zoom(for: fileURL),
            onZoomChanged: { zoom in zoomStore.setZoom(zoom, for: fileURL) }
        )
        window.contentView = NSHostingView(rootView: contentView)
```

- [ ] **Step 5: AppDelegate に ZoomStore を持たせて注入する**

`AppDelegate.swift:9` 付近にプロパティ追加:

```swift
    private let zoomStore = ZoomStore()
```

`openViewer(for:)` 内（現 98 行目）の生成を変更:

```swift
        let controller = ViewerWindowController(fileURL: url, zoomStore: zoomStore)
```

- [ ] **Step 6: ビルドと既存テストの確認**

Run: `cd MmdviewApp && swift build && swift test`
Expected: ビルド成功、全テスト PASS

- [ ] **Step 7: コミット**

```bash
git add MmdviewApp/mmdview/Viewer/ViewerWebView.swift MmdviewApp/mmdview/Viewer/ViewerContentView.swift MmdviewApp/mmdview/App/ViewerWindowController.swift MmdviewApp/mmdview/App/AppDelegate.swift
git commit -m "feat: 表示倍率をファイル毎に保存・復元する"
```

---

### Task 4: ウィンドウ位置・サイズの復元を有効にする

**Files:**
- Modify: `MmdviewApp/mmdview/App/ViewerWindowController.swift:24-33`

**Interfaces:**
- Consumes: 既存の NSWindow フレーム autosave（`"Viewer-<パス>"`）
- Produces: なし（挙動修正のみ）

現状は `setFrameAutosaveName` が復元したフレームを直後の `window.center()` が
毎回上書きしている。保存済みフレームがある場合は `center()` を呼ばないようにする。

- [ ] **Step 1: init の初期化順序を修正する**

`ViewerWindowController.swift` の autosave 設定（現 24-25 行目）を変更:

```swift
        let safeName = fileURL.path.replacingOccurrences(of: "/", with: "_")
        let autosaveName = "Viewer-\(safeName)"
        // 保存済みフレームがあれば復元し、なければ後段で中央配置する
        let hasSavedFrame = window.setFrameUsingName(autosaveName)
        window.setFrameAutosaveName(autosaveName)
```

`window.center()`（現 33 行目）を条件付きに変更:

```swift
        if !hasSavedFrame {
            window.center()
        }
```

- [ ] **Step 2: ビルド確認**

Run: `cd MmdviewApp && swift build`
Expected: ビルド成功

- [ ] **Step 3: コミット**

```bash
git add MmdviewApp/mmdview/App/ViewerWindowController.swift
git commit -m "fix: ウィンドウの位置とサイズがファイル毎に復元されない問題を修正する"
```

---

### Task 5: 全体検証（自動テスト + 手動チェック)

**Files:**
- なし（検証のみ。問題が見つかれば該当タスクのファイルを修正）

- [ ] **Step 1: 全自動テストを実行する**

Run: `cd MmdviewApp && swift test && npm test`
Expected: Swift（SessionStoreTests / ZoomStoreTests ほか）・Jest とも全件 PASS

- [ ] **Step 2: アプリをビルドして起動する**

/run スキル（利用可能な場合）またはプロジェクトの起動手順でアプリを起動し、
`.mmd` ファイルを 2 つ開く。

- [ ] **Step 3: 手動チェックリスト**

1. ファイル A のウィンドウを移動・リサイズし、倍率を 150% にする
2. ファイル B のウィンドウは別の位置・サイズ、倍率 75% にする
3. ファイル B だけを一度閉じて開き直す → 位置・サイズ・75% が戻ること
4. アプリを終了（Cmd+Q）して再起動する
5. A・B 両方のウィンドウが開き、それぞれの位置・サイズ・倍率（150% / 75%）が復元されること
6. 新規ファイル C を開く → 中央配置・100% で開くこと
7. ファイル A で倍率ラベルをクリック → 100% にリセットされ、再起動後も 100% であること

Expected: すべて設計通りに動作する

- [ ] **Step 4: 動作しない項目があれば該当タスクに戻って修正し、修正コミットを積む**

問題なければ完了。ブランチの統合（PR 作成など）は superpowers:finishing-a-development-branch に従う。
