# cmd+click によるファイル参照ジャンプ 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Markdown リンクとコードブロック内のファイルパスを cmd+click で開けるようにする

**Architecture:** JS 側でクリックを検出し `webkit.messageHandlers.referenceActivated` でブリッジへ通知。Swift 側で `ReferenceResolver` がパスを解決し、`ViewerWindowController` が既存の `switchFile(to:)` / `AppDelegate.openViewer(for:)` へディスパッチする。WKWebView の既定ナビゲーションは `decidePolicyFor` で全てキャンセルする。

**Tech Stack:** Swift 6 / WKWebView / Swift Testing

## Global Constraints

- macOS 14+, Swift 6 strict concurrency
- テスト関数名は英語 camelCase、日本語説明は `@Test("...")` の表示名で付ける
- Conventional Commits + 日本語
- `ViewerBridge` の文字列変更時は `viewer.html` 側の定義とあわせて変更すること

---

### Task 1: ReferenceResolver — パス解決の純粋ロジックとテスト

**Files:**
- Create: `BefoldApp/befold/Viewer/ReferenceResolver.swift`
- Test: `BefoldApp/befoldTests/ReferenceResolverTests.swift`

**Interfaces:**
- Consumes: なし（新規の独立ユニット）
- Produces:
  - `enum ReferenceTarget` — `.external(URL)` / `.localFile(URL)` / `.unsupported`
  - `enum ReferenceResolver` — `static func resolve(href: String, baseURL: URL) -> ReferenceTarget`
  - Task 4 が `ReferenceResolver.resolve(href:baseURL:)` を使ってディスパッチする

- [ ] **Step 1: テストファイルを作成し、最初の失敗テストを書く**

```swift
// BefoldApp/befoldTests/ReferenceResolverTests.swift
import Foundation
import Testing

@testable import befold

@Suite
struct ReferenceResolverTests {
    private let base = URL(fileURLWithPath: "/Users/test/docs/readme.md")

    @Test("https URL を external として解決する")
    func resolvesHttpsAsExternal() {
        let result = ReferenceResolver.resolve(
            href: "https://example.com", baseURL: base)
        guard case .external(let url) = result else {
            Issue.record("expected .external, got \(result)")
            return
        }
        #expect(url.absoluteString == "https://example.com")
    }

    @Test("http URL を external として解決する")
    func resolvesHttpAsExternal() {
        let result = ReferenceResolver.resolve(
            href: "http://example.com/path", baseURL: base)
        guard case .external(let url) = result else {
            Issue.record("expected .external, got \(result)")
            return
        }
        #expect(url.absoluteString == "http://example.com/path")
    }

    @Test("相対パスを baseURL の親ディレクトリ基準で解決する")
    func resolvesRelativePathAgainstBaseDirectory() {
        let result = ReferenceResolver.resolve(
            href: "./sub/file.swift", baseURL: base)
        guard case .localFile(let url) = result else {
            Issue.record("expected .localFile, got \(result)")
            return
        }
        #expect(url.path == "/Users/test/docs/sub/file.swift")
    }

    @Test("親ディレクトリ参照を含む相対パスを正しく解決する")
    func resolvesParentDirectoryReference() {
        let result = ReferenceResolver.resolve(
            href: "../other/file.md", baseURL: base)
        guard case .localFile(let url) = result else {
            Issue.record("expected .localFile, got \(result)")
            return
        }
        #expect(url.path == "/Users/test/other/file.md")
    }

    @Test("行番号サフィックスを除去してパスを解決する")
    func stripsLineNumberSuffix() {
        let result = ReferenceResolver.resolve(
            href: "./file.swift:42", baseURL: base)
        guard case .localFile(let url) = result else {
            Issue.record("expected .localFile, got \(result)")
            return
        }
        #expect(url.path == "/Users/test/docs/file.swift")
    }

    @Test("絶対パスをそのまま localFile として解決する")
    func resolvesAbsolutePath() {
        let result = ReferenceResolver.resolve(
            href: "/tmp/absolute.md", baseURL: base)
        guard case .localFile(let url) = result else {
            Issue.record("expected .localFile, got \(result)")
            return
        }
        #expect(url.path == "/tmp/absolute.md")
    }

    @Test("mailto リンクを unsupported として返す")
    func mailtoIsUnsupported() {
        let result = ReferenceResolver.resolve(
            href: "mailto:user@example.com", baseURL: base)
        guard case .unsupported = result else {
            Issue.record("expected .unsupported, got \(result)")
            return
        }
    }

    @Test("空文字列を unsupported として返す")
    func emptyHrefIsUnsupported() {
        let result = ReferenceResolver.resolve(href: "", baseURL: base)
        guard case .unsupported = result else {
            Issue.record("expected .unsupported, got \(result)")
            return
        }
    }

    @Test("# で始まるアンカーリンクを unsupported として返す")
    func anchorLinkIsUnsupported() {
        let result = ReferenceResolver.resolve(
            href: "#section", baseURL: base)
        guard case .unsupported = result else {
            Issue.record("expected .unsupported, got \(result)")
            return
        }
    }
}
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `cd BefoldApp && swift test --filter ReferenceResolverTests 2>&1 | tail -20`
Expected: コンパイルエラー（`ReferenceResolver` が存在しない）

- [ ] **Step 3: 最小限の実装を書く**

```swift
// BefoldApp/befold/Viewer/ReferenceResolver.swift
import Foundation

enum ReferenceTarget: Equatable {
    case external(URL)
    case localFile(URL)
    case unsupported
}

enum ReferenceResolver {
    static func resolve(href: String, baseURL: URL) -> ReferenceTarget {
        guard !href.isEmpty, !href.hasPrefix("#") else { return .unsupported }

        if let url = URL(string: href), let scheme = url.scheme {
            switch scheme {
            case "http", "https":
                return .external(url)
            default:
                return .unsupported
            }
        }

        // ローカルパス: 行番号サフィックス (:数字) を除去
        let pathString: String
        if let colonRange = href.range(
            of: #":\d+$"#, options: .regularExpression)
        {
            pathString = String(href[..<colonRange.lowerBound])
        } else {
            pathString = href
        }

        let baseDir = baseURL.deletingLastPathComponent()
        let resolved = baseDir.appendingPathComponent(pathString).standardized
        return .localFile(resolved)
    }
}
```

- [ ] **Step 4: テストを実行してパスすることを確認する**

Run: `cd BefoldApp && swift test --filter ReferenceResolverTests 2>&1 | tail -20`
Expected: 全テスト PASS

- [ ] **Step 5: コミットする**

```bash
cd BefoldApp
git add befold/Viewer/ReferenceResolver.swift befoldTests/ReferenceResolverTests.swift
git commit -m "feat: ファイル参照のパス解決ロジック ReferenceResolver を追加する"
```

---

### Task 2: ViewerBridge — メッセージ名の追加と整合性テスト

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerBridge.swift`
- Modify: `BefoldApp/befold/Resources/viewer.html` (JS 側に `referenceActivated` ハンドラ名を追加 — Task 5 で本体実装するが、ここではブリッジ整合性テストが通るよう名前だけ定義する)
- Test: 既存の `BefoldApp/befoldTests/ViewerBridgeTests.swift` が `viewer.html` との整合性を検証する想定

**Interfaces:**
- Consumes: なし
- Produces: `ViewerBridge.referenceActivatedMessageName` — Task 3 がハンドラ登録に使用

- [ ] **Step 1: ViewerBridge にメッセージ名定数を追加する**

`ViewerBridge.swift` の `zoomChangedMessageName` の直後に追加:

```swift
/// cmd+click でリンクやパス参照がアクティベートされたときに postMessage されるメッセージハンドラ名。
/// payload: { href: String, isExternal: Bool, newWindow: Bool }
static let referenceActivatedMessageName = "referenceActivated"
```

- [ ] **Step 2: viewer.html の JS に `referenceActivated` ハンドラ名を参照する最小コードを追加する**

`viewer.html` のインラインスクリプト冒頭（グローバル変数宣言付近）にコメント付きで名前を定義する。実際のクリック検出ロジックは Task 5 で実装するが、ViewerBridgeTests の整合性チェックが通るようここで名前を出しておく:

```js
// Swift ブリッジメッセージ名（ViewerBridge.swift と同期）
const _MSG_REFERENCE_ACTIVATED = 'referenceActivated';
```

- [ ] **Step 3: ビルドして整合性テストがパスすることを確認する**

Run: `cd BefoldApp && swift test --filter ViewerBridgeTests 2>&1 | tail -20`
Expected: PASS（ViewerBridgeTests が `referenceActivated` を viewer.html 内に見つける）

> **Note:** ViewerBridgeTests が存在しない、または `referenceActivated` の整合性チェックが含まれていない場合は、テストの追加は不要（既存のテストパターンがなければこのステップはビルド確認のみ）。

- [ ] **Step 4: コミットする**

```bash
cd BefoldApp
git add befold/Viewer/ViewerBridge.swift befold/Resources/viewer.html
git commit -m "feat: referenceActivated ブリッジメッセージ名を追加する"
```

---

### Task 3: ViewerWebView — メッセージハンドラ登録・コールバック・ナビゲーションキャンセル

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerWebView.swift`

**Interfaces:**
- Consumes: `ViewerBridge.referenceActivatedMessageName` (Task 2)
- Produces:
  - `ViewerWebView.onOpenReference: @MainActor (String, Bool, Bool) -> Void` — href, isExternal, newWindow
  - Task 4 が `ViewerContentView` 経由でこのコールバックを受け取る

- [ ] **Step 1: ViewerWebView に `onOpenReference` コールバックプロパティを追加する**

`ViewerWebView` の既存プロパティ `onZoomChanged` の直後に追加:

```swift
/// cmd+click でリンクやパス参照がアクティベートされたときに呼ばれる。
/// パラメータ: href, isExternal, newWindow
let onOpenReference: @MainActor (_ href: String, _ isExternal: Bool, _ newWindow: Bool) -> Void
```

- [ ] **Step 2: makeNSView でメッセージハンドラを登録する**

`makeNSView` 内、既存の `zoomChanged` ハンドラ登録の直後に追加:

```swift
config.userContentController.add(
    WeakScriptMessageHandler(delegate: context.coordinator),
    name: ViewerBridge.referenceActivatedMessageName
)
context.coordinator.onOpenReference = onOpenReference
```

- [ ] **Step 3: updateNSView でコールバックを更新する**

`updateNSView` 内、`context.coordinator.onZoomChanged = onZoomChanged` の直後に追加:

```swift
context.coordinator.onOpenReference = onOpenReference
```

- [ ] **Step 4: dismantleNSView でハンドラを解除する**

`dismantleNSView` 内、既存の `removeScriptMessageHandler` の直後に追加:

```swift
nsView.configuration.userContentController
    .removeScriptMessageHandler(forName: ViewerBridge.referenceActivatedMessageName)
```

- [ ] **Step 5: Coordinator にコールバックプロパティと分岐を追加する**

Coordinator に追加:

```swift
var onOpenReference: (@MainActor (_ href: String, _ isExternal: Bool, _ newWindow: Bool) -> Void)?
```

`userContentController(_:didReceive:)` を拡張する。既存の `guard` を `if-else` に変更:

```swift
@MainActor
func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
) {
    if message.name == ViewerBridge.zoomChangedMessageName,
       let zoom = (message.body as? NSNumber)?.doubleValue
    {
        onZoomChanged?(zoom)
    } else if message.name == ViewerBridge.referenceActivatedMessageName,
              let body = message.body as? [String: Any],
              let href = body["href"] as? String,
              let isExternal = body["isExternal"] as? Bool,
              let newWindow = body["newWindow"] as? Bool
    {
        onOpenReference?(href, isExternal, newWindow)
    }
}
```

- [ ] **Step 6: Coordinator に decidePolicyFor を追加して既定ナビゲーションをキャンセルする**

Coordinator に `WKNavigationDelegate` メソッドを追加:

```swift
func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction
) async -> WKNavigationActionPolicy {
    // 初回の HTML ロード（loadFileURL）のみ許可し、それ以外のナビゲーションは全てキャンセルする。
    // リンククリックやフォーム送信による意図しないページ遷移を防ぐ。
    switch navigationAction.navigationType {
    case .other:
        return .allow
    default:
        return .cancel
    }
}
```

- [ ] **Step 7: ビルドしてコンパイルエラーがないことを確認する**

Run: `cd BefoldApp && swift build 2>&1 | tail -20`
Expected: ビルド成功（ViewerContentView のコンパイルエラーは Task 4 で対処。ここでは一時的にダミーのクロージャを渡してビルドを通す必要がある場合は、`ViewerContentView` 側で `onOpenReference` を追加してから戻る）

> **Note:** `ViewerContentView` が `onOpenReference` を持たないためコンパイルエラーになる。Task 3 と Task 4 は連続して実施すること。

- [ ] **Step 8: コミットする**

```bash
cd BefoldApp
git add befold/Viewer/ViewerWebView.swift
git commit -m "feat: referenceActivated メッセージハンドラを ViewerWebView に登録する"
```

---

### Task 4: コールバックの配線とディスパッチ — ViewerContentView → ViewerWindowController

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerContentView.swift`
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`
- Test: `BefoldApp/befoldTests/ReferenceResolverTests.swift` (ディスパッチ判定テスト追加)

**Interfaces:**
- Consumes:
  - `ViewerWebView.onOpenReference` (Task 3)
  - `ReferenceResolver.resolve(href:baseURL:)` (Task 1)
  - `ViewerWindowController.switchFile(to:)` (既存)
  - `AppDelegate.openViewer(for:)` (既存)
- Produces: 完成した cmd+click → ファイルオープンの Swift 側パイプライン

- [ ] **Step 1: ViewerContentView に onOpenReference を追加する**

`ViewerContentView` にプロパティを追加:

```swift
let onOpenReference: @MainActor (_ href: String, _ isExternal: Bool, _ newWindow: Bool) -> Void
```

`body` 内の `ViewerWebView(...)` 呼び出しに引数を追加:

```swift
ViewerWebView(
    content: store.content,
    fileType: store.fileType,
    isDeleted: store.isDeleted,
    initialZoom: initialZoom,
    onZoomChanged: onZoomChanged,
    onOpenReference: onOpenReference,
    webViewProxy: webViewProxy
)
```

- [ ] **Step 2: ViewerWindowController の makeSplitViewController でコールバックを配線する**

`makeSplitViewController()` 内の `ViewerContentView(...)` にクロージャを追加:

```swift
let contentView = ViewerContentView(
    store: store,
    initialZoom: zoomStore.zoom(for: fileURL),
    onZoomChanged: { [weak self] zoom in
        guard let self else { return }
        zoomStore.setZoom(zoom, for: fileURL)
    },
    onOpenReference: { [weak self] href, isExternal, newWindow in
        self?.handleOpenReference(href: href, isExternal: isExternal, newWindow: newWindow)
    },
    webViewProxy: webViewProxy
)
```

- [ ] **Step 3: ViewerWindowController にディスパッチメソッドを追加する**

`ViewerWindowController` に追加:

```swift
/// cmd+click によるリンク/パス参照のアクティベーションを処理する。
private func handleOpenReference(href: String, isExternal: Bool, newWindow: Bool) {
    let target = ReferenceResolver.resolve(href: href, baseURL: fileURL)
    switch target {
    case .external(let url):
        NSWorkspace.shared.open(url)
    case .localFile(let url):
        guard FileManager.default.fileExists(atPath: url.path) else {
            showFileNotFoundAlert(path: url.path)
            return
        }
        if newWindow {
            AppDelegate.shared?.openViewer(for: url)
        } else {
            switchFile(to: url)
        }
    case .unsupported:
        break
    }
}

private func showFileNotFoundAlert(path: String) {
    guard let window else { return }
    let alert = NSAlert()
    alert.messageText = String(
        localized: "alert.fileNotFound.message",
        defaultValue: "File Not Found",
        bundle: .l10n
    )
    alert.informativeText = path
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.beginSheetModal(for: window)
}
```

- [ ] **Step 4: ビルドして全体がコンパイルできることを確認する**

Run: `cd BefoldApp && swift build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: 既存テストが壊れていないことを確認する**

Run: `cd BefoldApp && swift test 2>&1 | tail -20`
Expected: 全テスト PASS

- [ ] **Step 6: コミットする**

```bash
cd BefoldApp
git add befold/Viewer/ViewerContentView.swift befold/App/ViewerWindowController.swift
git commit -m "feat: referenceActivated コールバックを ViewerWindowController まで配線する"
```

---

### Task 5: viewer.html — クリック検出・パス検出・視覚フィードバック

**Files:**
- Modify: `BefoldApp/befold/Resources/viewer.html` (インライン JS)
- Modify: `BefoldApp/befold/Resources/style.css` (cmd キー押下中の視覚フィードバック)

**Interfaces:**
- Consumes: `webkit.messageHandlers.referenceActivated` (Task 2–3 で登録済み)
- Produces: ユーザーが cmd+click したときに `referenceActivated` メッセージが Swift 側に送信される

- [ ] **Step 1: style.css に cmd キー押下中の視覚フィードバック CSS を追加する**

`style.css` の末尾に追加:

```css
/* cmd+click ファイル参照ジャンプ */
.cmd-held a,
.cmd-held .befold-path-ref {
    text-decoration: underline;
    cursor: pointer;
}
.befold-path-ref {
    cursor: default;
}
```

- [ ] **Step 2: viewer.html に cmd キー押下検出を追加する**

インラインスクリプト内の既存 `keydown` リスナー（ズーム用）と同じブロックに、`cmd-held` クラスの付け外しを追加する。既存の `keydown` リスナーの **中** に meta キー判定を追加:

```js
// 既存の keydown リスナーの先頭に追加
document.body.classList.toggle('cmd-held', e.metaKey);
```

新規の `keyup` リスナーを追加:

```js
document.addEventListener('keyup', function(e) {
    if (!e.metaKey) document.body.classList.remove('cmd-held');
});
// ウィンドウがフォーカスを失ったときも解除する
window.addEventListener('blur', function() {
    document.body.classList.remove('cmd-held');
});
```

- [ ] **Step 3: viewer.html にリンク・パス参照のクリック委譲リスナーを追加する**

`render()` 関数の **外側**（グローバルスコープ）に委譲リスナーを1つ登録する:

```js
document.getElementById('diagram-wrap').addEventListener('click', function(e) {
    // <a> タグまたは .befold-path-ref をクリック対象として検出
    var anchor = e.target.closest('a');
    var pathRef = e.target.closest('.befold-path-ref');
    var target = anchor || pathRef;
    if (!target) return;

    var href = anchor ? anchor.getAttribute('href') : pathRef.dataset.path;
    if (!href) return;

    // # で始まるアンカーリンクは既定のスクロール動作に任せる
    if (href.charAt(0) === '#') return;

    // アンカー以外は全て preventDefault
    e.preventDefault();

    // cmd が押されていなければ no-op
    if (!e.metaKey) return;

    var isExternal = /^https?:\/\//.test(href);
    window.webkit.messageHandlers[_MSG_REFERENCE_ACTIVATED].postMessage({
        href: href,
        isExternal: isExternal,
        newWindow: e.shiftKey
    });
});
```

- [ ] **Step 4: viewer.html にコードブロック内パス検出ロジックを追加する**

`render()` 関数の末尾（`_mmdApplyZoom()` 呼び出しの直前）にパス検出を追加:

```js
_annotatePathRefs();
```

グローバルスコープに検出関数を定義:

```js
var _PATH_RE = /(?:\.\.?\/[\w./-]+|[\w.-]+\/[\w./-]+)(?:\.(?:swift|md|mmd|ts|tsx|js|jsx|py|rb|go|rs|java|kt|c|cpp|h|hpp|json|yaml|yml|toml|txt|html|css|sh))(?::\d+)?/g;

function _annotatePathRefs() {
    var blocks = document.querySelectorAll('#diagram-wrap pre code');
    for (var i = 0; i < blocks.length; i++) {
        _walkTextNodes(blocks[i]);
    }
}

// 既知の制約: シンタックスハイライトによってトークンが複数の <span> に分割されている場合、
// その境界をまたぐパスは検出されない（シンプルなヒューリスティックとして許容する）。
function _walkTextNodes(node) {
    if (node.nodeType === 3) { // TEXT_NODE
        var text = node.textContent;
        _PATH_RE.lastIndex = 0;
        var match = _PATH_RE.exec(text);
        if (!match) return;
        var frag = document.createDocumentFragment();
        var lastIndex = 0;
        do {
            if (match.index > lastIndex) {
                frag.appendChild(document.createTextNode(text.slice(lastIndex, match.index)));
            }
            var span = document.createElement('span');
            span.className = 'befold-path-ref';
            span.dataset.path = match[0];
            span.textContent = match[0];
            frag.appendChild(span);
            lastIndex = _PATH_RE.lastIndex;
        } while ((match = _PATH_RE.exec(text)) !== null);
        if (lastIndex < text.length) {
            frag.appendChild(document.createTextNode(text.slice(lastIndex)));
        }
        node.parentNode.replaceChild(frag, node);
    } else if (node.nodeType === 1 && !node.classList.contains('befold-path-ref')) {
        // ELEMENT_NODE: 子を逆順に走査（replaceChild で兄弟が変わるため）
        var children = Array.prototype.slice.call(node.childNodes);
        for (var j = 0; j < children.length; j++) {
            _walkTextNodes(children[j]);
        }
    }
}
```

- [ ] **Step 5: ビルドしてコンパイルエラーがないことを確認する**

Run: `cd BefoldApp && swift build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: 手動テスト — webview-smoke で動作確認**

以下を確認する:
1. Markdown リンクに cmd を押しながらホバーすると下線とポインターカーソルが表示される
2. cmd+click で外部 URL がブラウザで開く
3. cmd+click で相対パスのローカルファイルが現在ウィンドウで開く
4. shift+cmd+click でローカルファイルが新しいウィンドウで開く
5. 無修飾クリックは何も起きない（no-op）
6. `#` アンカーリンクは通常のスクロール動作
7. コードブロック内のファイルパスが検出され、cmd+click で開ける
8. 存在しないパスを cmd+click するとエラーダイアログが表示される

- [ ] **Step 7: コミットする**

```bash
cd BefoldApp
git add befold/Resources/viewer.html befold/Resources/style.css
git commit -m "feat: cmd+click によるファイル参照ジャンプの JS 側を実装する"
```
