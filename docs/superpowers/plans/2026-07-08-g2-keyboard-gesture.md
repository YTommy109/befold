# G2: キーボード/ジェスチャー操作の改善 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

<!-- derived-from ../specs/2026-07-08-g2-keyboard-gesture-design.md -->

**Goal:** ビューア(WKWebView)にスペース/矢印/vim jk のスクロールショートカットを
追加し、トラックパッドのピンチによるズームを direct HTML モードでも有効にし、
二本指スワイプで戻る/進む履歴ナビゲーションができるようにする。

**Architecture:** JS側の変更（`viewer.html`）、WKWebView設定の変更
（`ViewerWebView.swift`）、Swift側の新規純粋関数＋ウィンドウ単位の
NSEvent監視（`ViewerWindowController.swift`）の3系統。JS/GUI変更は
自動テスト対象外（プロジェクトの既存方針）とし、Swift側の純粋ロジック
（スワイプ方向→履歴offset変換）のみユニットテストする。

**Tech Stack:** Swift 6, AppKit, WebKit (WKWebView), Swift Testing

## Global Constraints

- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- テストは Swift Testing フレームワーク（`@Test` / `#expect`）を使う
- WebView/GUI 層（実際のキー入力・トラックパッド操作）は自動テスト対象外。
  手動確認手順をタスク内に明記する
- JS を実行するテストランナー（Node.js等）は本プロジェクトに存在せず、
  新規導入しない
- コミットメッセージは Conventional Commits + 日本語（例: `feat: ...する`）

---

### Task 1: スペースキー/矢印/vim jk でビューアをスクロールする

**Files:**
- Modify: `BefoldApp/befold/Resources/viewer.html:99-109`

**Interfaces:**
- Consumes: なし
- Produces: なし（JSのイベントハンドラ拡張のみ、Swift側から参照されない）

- [ ] **Step 1: 現状の keydown リスナーを確認する**

```html
document.addEventListener('keydown', function(e) {
  document.body.classList.toggle('cmd-held', e.metaKey);
  if (e.metaKey) {
    if (e.key === '-') { e.preventDefault(); _mmdZoomOut(); }
    else if (e.key === '=' || e.key === '+') { e.preventDefault(); _mmdZoomIn(); }
  }
});
```

- [ ] **Step 2: スクロールショートカットを追加する**

`BefoldApp/befold/Resources/viewer.html:99-105` を以下に置き換える:

```html
document.addEventListener('keydown', function(e) {
  document.body.classList.toggle('cmd-held', e.metaKey);
  if (e.metaKey) {
    if (e.key === '-') { e.preventDefault(); _mmdZoomOut(); }
    else if (e.key === '=' || e.key === '+') { e.preventDefault(); _mmdZoomIn(); }
    return;
  }
  var scrollKeys = [' ', 'ArrowDown', 'ArrowUp', 'j', 'k'];
  if (scrollKeys.indexOf(e.key) === -1) { return; }
  var viewerEl = document.querySelector('.viewer');
  if (!viewerEl) { return; }
  e.preventDefault();
  var step = e.shiftKey ? SCROLL_STEP_LARGE : SCROLL_STEP;
  var down = e.key === ' ' ? !e.shiftKey : (e.key === 'ArrowDown' || e.key === 'j');
  viewerEl.scrollBy({ top: down ? step : -step, behavior: 'auto' });
});
```

- [ ] **Step 3: スクロール量の定数を追加する**

`BefoldApp/befold/Resources/viewer.js` の先頭付近（`var ZOOM_MIN = 0.5;` の
前）に以下を追加する:

```js
var SCROLL_STEP = 80;
var SCROLL_STEP_LARGE = 400;
```

- [ ] **Step 4: viewer.html が viewer.js の定数を参照できることを確認する**

`viewer.html:27` で `<script src="viewer.js"></script>` が
`</body>` 直前のインラインスクリプトより前に読み込まれているため、
`SCROLL_STEP` / `SCROLL_STEP_LARGE` は既に読み込み順序上参照可能。
`swift build` を実行し、リソースファイルの変更がビルドを壊さないことを
確認する。

Run: `cd BefoldApp && swift build`
Expected: ビルド成功

- [ ] **Step 5: 手動で動作確認する（自動テスト対象外）**

1. befold で十分な長さのMarkdownファイルを開く
2. WebView にフォーカスがある状態で以下を確認する:
   - スペースキー: 下にスクロールする
   - shift+スペース: 上にスクロールする
   - 下矢印 / `j`: 下にスクロールする
   - 上矢印 / `k`: 上にスクロールする
   - shift併用時、通常よりも大きくスクロールする
3. コード表示モード（ソーストグル）でも同様に動作することを確認する

- [ ] **Step 6: コミット**

```bash
git add BefoldApp/befold/Resources/viewer.html BefoldApp/befold/Resources/viewer.js
git commit -m "feat: ビューアにスペース/矢印/vim jk のスクロールショートカットを追加する"
```

---

### Task 2: トラックパッドのピンチズームを direct HTML モードでも有効にする

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerWebView.swift:62`

**Interfaces:**
- Consumes: なし
- Produces: なし（`WKWebView` のプロパティ設定のみ）

- [ ] **Step 1: 現状のWKWebView生成箇所を確認する**

```swift
let webView = WKWebView(frame: .zero, configuration: config)
webView.navigationDelegate = context.coordinator
// WKWebView の背景を透明にする（公開 API がないため KVC を使用）
webView.setValue(false, forKey: "drawsBackground")
```

- [ ] **Step 2: allowsMagnification を有効にする**

`BefoldApp/befold/Viewer/ViewerWebView.swift:62-65` を以下に置き換える:

```swift
let webView = WKWebView(frame: .zero, configuration: config)
webView.navigationDelegate = context.coordinator
// WKWebView の背景を透明にする（公開 API がないため KVC を使用）
webView.setValue(false, forKey: "drawsBackground")
// トラックパッドのピンチジェスチャーでズームできるようにする。
// viewer.html 経由のコンテンツは既存の ctrl+wheel ハンドラ(viewer.html)で
// 対応済みだが、.html ファイル直接ロード時はこの経路を通らないため必要。
webView.allowsMagnification = true
```

- [ ] **Step 3: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功

- [ ] **Step 4: 手動で動作確認する（自動テスト対象外）**

1. Markdown/Mermaidファイルを開き、トラックパッドでピンチしてズームできる
   ことを確認する（既存の ctrl+wheel 経由のJS実装が機能しているはずの
   確認も兼ねる）
2. `.html` ファイルを開き（ソース表示トグルをオフの状態、direct HTML
   モード）、トラックパッドでピンチしてズームできることを確認する
3. ズーム後、⌘+/⌘-/⌘0（メニューのズーム操作）が引き続き正しく動作する
   ことを確認する（`allowsMagnification` が既存の `pageZoom` ベースの
   ズーム操作と衝突しないこと）

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/Viewer/ViewerWebView.swift
git commit -m "feat: direct HTMLモードでトラックパッドのピンチズームを有効にする"
```

---

### Task 3: スワイプ方向から履歴ナビゲーションのoffsetを決める純粋ロジックを追加する

**Files:**
- Create: `BefoldApp/befold/App/SwipeHistoryNavigation.swift`
- Test: `BefoldApp/befoldTests/SwipeHistoryNavigationTests.swift`

**Interfaces:**
- Produces: `SwipeHistoryNavigation.offset(forHorizontalDelta: CGFloat, threshold: CGFloat) -> Int?`
  （Task 4 がこの関数を呼び出す）

- [ ] **Step 1: 失敗するテストを書く**

```swift
// BefoldApp/befoldTests/SwipeHistoryNavigationTests.swift
@testable import befold
import Foundation
import Testing

@Suite
struct SwipeHistoryNavigationTests {
    @Test("しきい値未満のデルタはナビゲーションしない")
    func belowThresholdReturnsNil() {
        let result = SwipeHistoryNavigation.offset(forHorizontalDelta: 2, threshold: 10)

        #expect(result == nil)
    }

    @Test("正のデルタ(右スワイプ)は戻る(-1)を返す")
    func positiveDeltaReturnsBack() {
        let result = SwipeHistoryNavigation.offset(forHorizontalDelta: 15, threshold: 10)

        #expect(result == -1)
    }

    @Test("負のデルタ(左スワイプ)は進む(+1)を返す")
    func negativeDeltaReturnsForward() {
        let result = SwipeHistoryNavigation.offset(forHorizontalDelta: -15, threshold: 10)

        #expect(result == 1)
    }

    @Test("しきい値ちょうどはナビゲーションする(境界値)")
    func exactlyAtThresholdNavigates() {
        let result = SwipeHistoryNavigation.offset(forHorizontalDelta: 10, threshold: 10)

        #expect(result == -1)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter SwipeHistoryNavigationTests`
Expected: FAIL（`SwipeHistoryNavigation` が存在しないためビルドエラー）

- [ ] **Step 3: 最小実装を書く**

```swift
// BefoldApp/befold/App/SwipeHistoryNavigation.swift
import Foundation

/// トラックパッドの水平スワイプから履歴ナビゲーション(戻る/進む)の
/// offset を決める純粋ロジック。
enum SwipeHistoryNavigation {
    /// `deltaX` の絶対値が `threshold` 未満なら nil(ナビゲーションしない)。
    /// 正の deltaX(右向きスワイプ)は戻る(-1)、負(左向き)は進む(+1)を返す。
    static func offset(forHorizontalDelta deltaX: CGFloat, threshold: CGFloat) -> Int? {
        guard abs(deltaX) >= threshold else { return nil }
        return deltaX > 0 ? -1 : 1
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter SwipeHistoryNavigationTests`
Expected: PASS（4 tests passed）

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/SwipeHistoryNavigation.swift BefoldApp/befoldTests/SwipeHistoryNavigationTests.swift
git commit -m "feat: スワイプ方向から履歴ナビゲーションoffsetを決めるロジックを追加する"
```

---

### Task 4: 二本指スワイプでウィンドウの履歴を遡れるようにする

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`

**Interfaces:**
- Consumes: `SwipeHistoryNavigation.offset(forHorizontalDelta:threshold:)`（Task 3）、
  既存の `navigateHistory(by offset: Int)`（`ViewerWindowController.swift:254-256`）
- Produces: なし

- [ ] **Step 1: WKWebView標準のページ履歴スワイプを無効化する**

`BefoldApp/befold/Viewer/ViewerWebView.swift` の Task 2 で追加した
`webView.allowsMagnification = true` の直後に以下を追加する:

```swift
webView.allowsMagnification = true
// WebKit標準の「2本指スワイプでページ履歴を戻る/進む」は本アプリの
// ページ内履歴(loadFileURLのみ)とは無関係なため無効化し、
// ViewerWindowController が二本指スワイプでファイル履歴を扱えるようにする。
webView.allowsBackForwardNavigationGestures = false
```

- [ ] **Step 2: ViewerWindowController にスワイプ検知プロパティを追加する**

`BefoldApp/befold/App/ViewerWindowController.swift:16` 付近
（`private let forceSidebarVisible: Bool` の下）に追加:

```swift
    private let forceSidebarVisible: Bool
    /// 二本指スワイプ検知用のローカルイベントモニタ。ウィンドウが閉じたら解除する。
    private var scrollEventMonitor: Any?
    /// スワイプしきい値(pt)。この値未満の水平デルタはナビゲーションしない。
    private static let swipeThreshold: CGFloat = 40
```

- [ ] **Step 3: init 内でイベントモニタを登録する**

`BefoldApp/befold/App/ViewerWindowController.swift` の `init` 内、
`sidebar.attach(to: self)` の直前（`window.delegate = self` より後、
`sidebar.attach` より前）に以下を追加する:

```swift
        window.delegate = self

        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollWheelForHistorySwipe(event)
            return event
        }

        sidebar.attach(to: self)
```

- [ ] **Step 4: スワイプ判定ハンドラを追加する**

`ViewerWindowController` の `NSWindowDelegate` extension
（`BefoldApp/befold/App/ViewerWindowController.swift:319`付近、
`saveWindowFrame()` の直前）に以下のメソッドを追加する:

```swift
    /// 二本指スワイプ(トラックパッド)によるファイル履歴の戻る/進むを検知する。
    /// スワイプ完了時(momentumPhase が始まる直前の .ended)にのみ発火させ、
    /// 慣性スクロール中の連続発火を防ぐ。
    private func handleScrollWheelForHistorySwipe(_ event: NSEvent) {
        guard event.phase == .ended else { return }
        guard let offset = SwipeHistoryNavigation.offset(
            forHorizontalDelta: event.scrollingDeltaX,
            threshold: Self.swipeThreshold
        ) else { return }
        navigateHistory(by: offset)
    }
```

- [ ] **Step 5: windowWillClose でモニタを解除する**

`BefoldApp/befold/App/ViewerWindowController.swift` の `windowWillClose`
メソッド（`saveWindowFrame(); store.close(); onClose?()`）を以下に置き換える:

```swift
    func windowWillClose(_ notification: Notification) {
        if let scrollEventMonitor {
            NSEvent.removeMonitor(scrollEventMonitor)
            self.scrollEventMonitor = nil
        }
        saveWindowFrame()
        store.close()
        onClose?()
    }
```

- [ ] **Step 6: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功

- [ ] **Step 7: 全テストを実行する**

Run: `cd BefoldApp && swift test`
Expected: 全テスト PASS（Task 3 の4件を含む）

- [ ] **Step 8: 手動で動作確認する（自動テスト対象外）**

1. befold であるファイルを開き、サイドバーで別のファイル・フォルダに
   何度か移動する（履歴を積む）
2. WebView上でトラックパッドを二本指で左右にスワイプし、戻る/進むが
   機能することを確認する
3. スワイプが `HistoryNavigationButton`（サイドバーの戻る/進むボタン）と
   同じ履歴状態を共有していることを確認する（スワイプで戻った後、
   ボタンの「進む」が有効になっている等）
4. ウィンドウを閉じてもクラッシュ・リークが起きないことを確認する
   （複数ウィンドウを開閉して確認）

- [ ] **Step 9: コミット**

```bash
git add BefoldApp/befold/App/ViewerWindowController.swift BefoldApp/befold/Viewer/ViewerWebView.swift
git commit -m "feat: 二本指スワイプでファイル履歴の戻る/進むを操作できるようにする"
```
