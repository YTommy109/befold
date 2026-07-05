# SVG / HTML 画像表示 & レンダリング/ソース切り替え 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SVG / HTML ファイルをレンダリング表示し、SVG / HTML / Markdown / Mermaid ファイルでレンダリング表示とソース表示をツールバーボタンで切り替えられるようにする。

**Architecture:** FileType enum に `.svg` / `.html` case を追加し、viewer.html の render() に SVG(`<img>` data URI) と HTML(`<iframe sandbox srcdoc>`) の描画分岐を追加する。新関数 `setViewMode(mode)` でレンダリング/ソース表示を切り替え、Swift 側は NSToolbar に `</>` トグルボタンを追加して JS を呼び出す。

**Tech Stack:** Swift 6 / AppKit (NSToolbar) / WKWebView / JavaScript

## Global Constraints

- macOS 14+, Swift 6 strict concurrency
- SVG は `<img src="data:image/svg+xml;base64,...">` 経由で表示（`<script>` 実行防止）
- HTML は `<iframe sandbox srcdoc="...">` で表示（スクリプト実行・外部通信防止）
- CSP に `frame-src blob:;` を追加（`srcdoc` iframe に必要）
- ソース表示は既存の `renderCodeHtml()` を再利用
- テスト: Swift Testing フレームワーク、テスト関数名は英語 camelCase

---

### Task 1: FileType に `.svg` / `.html` case を追加する

**Files:**
- Modify: `MmdviewApp/mmdview/Viewer/FileType.swift`
- Modify: `MmdviewApp/mmdviewTests/FileTypeTests.swift`

**Interfaces:**
- Produces: `FileType.svg`, `FileType.html`, `FileType.isRenderable: Bool`, `FileType.sourceLanguage: String?`

- [ ] **Step 1: FileTypeTests にテストを追加**

`FileTypeTests.swift` に以下のテストケースを追加する:

1. `knownExtensions` の引数リストに SVG / HTML を追加:
```swift
("svg", FileType.svg),
("SVG", FileType.svg),
("html", FileType.html),
("htm", FileType.html),
("HTML", FileType.html),
```

2. `codeExtensionsMapToLanguage` から SVG を除外するので、テスト引数に `("svg", "xml")` が含まれていないことを確認（現在含まれていないので変更不要）。

3. `unknownExtensionsFallbackToPlaintext` から `"html"` を除外:
```swift
@Test(arguments: ["txt", ""])
func unknownExtensionsFallbackToPlaintext(ext: String) {
```

4. `jsValueMapping` に SVG / HTML を追加:
```swift
(FileType.svg, "svg"),
(FileType.html, "html"),
```

5. `codeLanguageOnlyForCode` に SVG / HTML の nil チェックを追加:
```swift
#expect(FileType.svg.codeLanguage == nil)
#expect(FileType.html.codeLanguage == nil)
```

6. `isRenderable` の新テストを追加:
```swift
@Test
func isRenderable() {
    #expect(FileType.mmd.isRenderable == true)
    #expect(FileType.markdown.isRenderable == true)
    #expect(FileType.svg.isRenderable == true)
    #expect(FileType.html.isRenderable == true)
    #expect(FileType.code(language: "swift").isRenderable == false)
}
```

7. `sourceLanguage` の新テストを追加:
```swift
@Test
func sourceLanguage() {
    #expect(FileType.svg.sourceLanguage == "xml")
    #expect(FileType.html.sourceLanguage == "xml")
    #expect(FileType.markdown.sourceLanguage == "markdown")
    #expect(FileType.mmd.sourceLanguage == nil)
    #expect(FileType.code(language: "swift").sourceLanguage == nil)
}
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
cd MmdviewApp && swift test --filter FileTypeTests 2>&1 | tail -20
```
Expected: コンパイルエラー（`.svg`, `.html`, `.isRenderable`, `.sourceLanguage` が未定義）

- [ ] **Step 3: FileType.swift を実装**

`FileType.swift` を以下のように変更:

1. enum に case を追加:
```swift
enum FileType: Sendable, Equatable {
    case mmd
    case markdown
    case svg
    case html
    case code(language: String)
```

2. `codeExtensionLanguages` から `"svg": "xml"` を削除。

3. SVG / HTML 用の拡張子リストを追加:
```swift
static let svgExtensions = ["svg"]
static let htmlExtensions = ["html", "htm"]
```

4. `init(url:)` の判定順を変更（mermaid → svg → html → code → markdown → fallback）:
```swift
init(url: URL) {
    let ext = url.pathExtension.lowercased()
    if Self.mermaidExtensions.contains(ext) {
        self = .mmd
    } else if Self.svgExtensions.contains(ext) {
        self = .svg
    } else if Self.htmlExtensions.contains(ext) {
        self = .html
    } else if let language = Self.codeExtensionLanguages[ext] {
        self = .code(language: language)
    } else if Self.markdownExtensions.contains(ext) {
        self = .markdown
    } else {
        self = .code(language: "plaintext")
    }
}
```

5. `jsValue` に SVG / HTML を追加:
```swift
var jsValue: String {
    switch self {
    case .mmd: "mmd"
    case .markdown: "md"
    case .svg: "svg"
    case .html: "html"
    case .code: "code"
    }
}
```

6. `isRenderable` プロパティを追加:
```swift
var isRenderable: Bool {
    switch self {
    case .mmd, .markdown, .svg, .html: true
    case .code: false
    }
}
```

7. `sourceLanguage` プロパティを追加（ソース表示時の highlight.js 言語名）:
```swift
var sourceLanguage: String? {
    switch self {
    case .svg, .html: "xml"
    case .markdown: "markdown"
    case .mmd, .code: nil
    }
}
```

8. `extensionListsHaveNoDuplicates` テストが通るよう `codeExtensions` の集合に SVG / HTML 拡張子も含める:
```swift
// extensionListsHaveNoDuplicates テスト用。全拡張子を列挙するプロパティは
// 既存テストが mermaid + markdown + code の結合をチェックしているので、
// svg / html も加えてテストを更新する。
```

- [ ] **Step 4: テストが全て通ることを確認**

```bash
cd MmdviewApp && swift test --filter FileTypeTests 2>&1 | tail -20
```
Expected: All tests passed

- [ ] **Step 5: コミット**

```bash
git add MmdviewApp/mmdview/Viewer/FileType.swift MmdviewApp/mmdviewTests/FileTypeTests.swift
git commit -m "feat: FileType に .svg / .html case を追加する"
```

---

### Task 2: viewer.html に SVG / HTML レンダリングを追加する

**Files:**
- Modify: `MmdviewApp/mmdview/Resources/viewer.html:13,292-343`

**Interfaces:**
- Consumes: `render(content, type, lang)` に `type === 'svg'` / `type === 'html'` が渡される
- Produces: SVG は `<img>` data URI で表示、HTML は `<iframe sandbox srcdoc>` で表示

- [ ] **Step 1: CSP に `frame-src` を追加**

`viewer.html` L13 の CSP メタタグに `frame-src blob:;` を追加:

```html
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; frame-src blob:; connect-src 'none'; base-uri 'none'">
```

- [ ] **Step 2: render() に SVG 分岐を追加**

`viewer.html` の `render()` 関数内、`if (type === 'mmd')` ブロックの後に SVG 分岐を追加:

```javascript
} else if (type === 'svg') {
  diagramWrap.classList.remove('markdown-body');
  diagramWrap.classList.remove('code-body');
  var svgImg = document.createElement('img');
  svgImg.src = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(content)));
  svgImg.style.maxWidth = '100%';
  svgImg.alt = 'SVG';
  // mermaid ダイアグラムと同じズーム用ラッパーで包む
  var wrap = document.createElement('div');
  wrap.className = 'diagram-zoom-wrap';
  wrap.dataset.diagramIndex = '0';
  var scroll = document.createElement('div');
  scroll.className = 'diagram-zoom-scroll';
  var inner = document.createElement('div');
  inner.className = 'diagram-zoom-inner';
  inner.appendChild(svgImg);
  scroll.appendChild(inner);
  wrap.appendChild(scroll);
  wrap.appendChild(_mmdBuildDiagramControls(wrap));
  diagramWrap.innerHTML = '';
  diagramWrap.appendChild(wrap);
  svgImg.onload = function() {
    wrap.dataset.naturalHeight = inner.offsetHeight;
    _mmdApplyDiagramZoom(wrap);
  };
```

- [ ] **Step 3: render() に HTML 分岐を追加**

SVG 分岐の後に HTML 分岐を追加:

```javascript
} else if (type === 'html') {
  diagramWrap.classList.remove('markdown-body');
  diagramWrap.classList.remove('code-body');
  diagramWrap.classList.add('html-body');
  var iframe = document.createElement('iframe');
  iframe.sandbox = '';
  iframe.srcdoc = content;
  iframe.style.width = '100%';
  iframe.style.border = 'none';
  // iframe の高さをコンテンツに合わせる
  iframe.onload = function() {
    try {
      var h = iframe.contentDocument.documentElement.scrollHeight;
      iframe.style.height = h + 'px';
    } catch(e) {
      iframe.style.height = '80vh';
    }
  };
  iframe.style.height = '80vh';
  diagramWrap.innerHTML = '';
  diagramWrap.appendChild(iframe);
```

- [ ] **Step 4: ビルドして動作確認**

```bash
cd MmdviewApp && swift build 2>&1 | tail -5
```
Expected: Build succeeded

サンプル SVG / HTML ファイルを作成して手動で開き、レンダリングされることを確認する:

```bash
echo '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200"><circle cx="100" cy="100" r="80" fill="blue"/></svg>' > /tmp/test.svg
echo '<html><body><h1>Hello</h1><p>Test HTML rendering</p></body></html>' > /tmp/test.html
```

- [ ] **Step 5: コミット**

```bash
git add MmdviewApp/mmdview/Resources/viewer.html
git commit -m "feat: viewer.html に SVG / HTML レンダリングを追加する"
```

---

### Task 3: setViewMode() でレンダリング/ソース切り替えを実装する

**Files:**
- Modify: `MmdviewApp/mmdview/Resources/viewer.html:287-343`
- Modify: `MmdviewApp/mmdview/Viewer/ViewerBridge.swift`
- Modify: `MmdviewApp/mmdviewTests/ViewerBridgeTests.swift`

**Interfaces:**
- Consumes: `_lastContent`, `_lastType`, `_lastLang` (既存グローバル変数), `renderCodeHtml()` (viewer.js)
- Produces: JS 関数 `setViewMode(mode)`, `getViewMode()`, Swift の `ViewerBridge.viewModeScript(_:)`, `ViewerBridge.getViewModeScript`

- [ ] **Step 1: viewer.html に `_viewMode` 状態と `setViewMode()` / `getViewMode()` を追加**

`viewer.html` の `_lastLang` 定義の後（L290 付近）に以下を追加:

```javascript
var _viewMode = 'rendered';
```

`render()` 関数を修正して `_viewMode` に応じた分岐を追加。render() の冒頭（`_lastContent = content;` の後）に:

```javascript
if (_viewMode === 'source' && type !== 'code') {
  _renderSource(content, type, lang);
  return;
}
```

ソース表示用のヘルパー関数を追加:

```javascript
function _renderSource(content, type, lang) {
  var diagramWrap = document.getElementById('diagram-wrap');
  diagramWrap.classList.remove('markdown-body');
  diagramWrap.classList.remove('html-body');
  diagramWrap.classList.add('code-body');
  var sourceLang = (type === 'svg' || type === 'html') ? 'xml'
                 : (type === 'md') ? 'markdown'
                 : lang || 'plaintext';
  diagramWrap.innerHTML = renderCodeHtml(window.hljs, content, sourceLang);
  _mmdApplyZoom();
}
```

`setViewMode()` と `getViewMode()` を追加:

```javascript
function setViewMode(mode) {
  if (mode !== 'rendered' && mode !== 'source') return;
  if (mode === _viewMode) return;
  _viewMode = mode;
  if (_lastContent !== null) {
    render(_lastContent, _lastType, _lastLang);
  }
}

function getViewMode() {
  return _viewMode;
}
```

- [ ] **Step 2: ViewerBridgeTests にテストを追加**

`ViewerBridgeTests.swift` に以下を追加:

```swift
@Test("svg タイプは 2 引数のまま（言語引数を付けない）")
func renderScriptOmitsLanguageForSvg() throws {
    let script = try #require(ViewerBridge.renderScript(content: "<svg></svg>", fileType: .svg))
    #expect(script.hasSuffix("', 'svg')"))
}

@Test("html タイプは 2 引数のまま（言語引数を付けない）")
func renderScriptOmitsLanguageForHtml() throws {
    let script = try #require(ViewerBridge.renderScript(content: "<html></html>", fileType: .html))
    #expect(script.hasSuffix("', 'html')"))
}

@Test("viewModeScript がモード文字列を埋め込む")
func viewModeScriptEmbedsMode() {
    #expect(ViewerBridge.viewModeScript(.source) == "setViewMode('source')")
    #expect(ViewerBridge.viewModeScript(.rendered) == "setViewMode('rendered')")
}

@Test("getViewModeScript が正しい JS を返す")
func getViewModeScriptValue() {
    #expect(ViewerBridge.getViewModeScript == "getViewMode()")
}
```

`bridgeFunctionsExistInViewerHTML` テストに以下を追加:

```swift
#expect(html.contains("function setViewMode(mode)"))
#expect(html.contains("function getViewMode()"))
```

- [ ] **Step 3: テストが失敗することを確認**

```bash
cd MmdviewApp && swift test --filter ViewerBridgeTests 2>&1 | tail -20
```
Expected: コンパイルエラー（`ViewerBridge.viewModeScript`, `ViewerBridge.getViewModeScript` が未定義）

- [ ] **Step 4: ViewerBridge.swift に viewModeScript を追加**

`ViewerBridge.swift` に以下を追加:

```swift
enum ViewMode: String {
    case rendered
    case source
}

static func viewModeScript(_ mode: ViewMode) -> String {
    "setViewMode('\(mode.rawValue)')"
}

static let getViewModeScript = "getViewMode()"
```

- [ ] **Step 5: テストが通ることを確認**

```bash
cd MmdviewApp && swift test --filter ViewerBridgeTests 2>&1 | tail -20
```
Expected: All tests passed

- [ ] **Step 6: コミット**

```bash
git add MmdviewApp/mmdview/Resources/viewer.html MmdviewApp/mmdview/Viewer/ViewerBridge.swift MmdviewApp/mmdviewTests/ViewerBridgeTests.swift
git commit -m "feat: setViewMode() でレンダリング/ソース切り替えを実装する"
```

---

### Task 4: NSToolbar にソース表示トグルボタンを追加する

**Files:**
- Modify: `MmdviewApp/mmdview/App/ViewerWindowController.swift`
- Modify: `MmdviewApp/mmdviewTests/ViewerWindowControllerTests.swift`

**Interfaces:**
- Consumes: `ViewerStore.fileType.isRenderable`, `WebViewProxy.webView`, `ViewerBridge.viewModeScript(_:)`, `ViewerBridge.getViewModeScript`, `ViewerBridge.ViewMode`
- Produces: ツールバーの `</>` トグルボタン

- [ ] **Step 1: ViewerWindowController に NSToolbar を追加**

`ViewerWindowController.swift` の `init(fileURL:zoomStore:defaults:)` 内、`window.delegate = self` の直前に NSToolbar を追加:

```swift
let toolbar = NSToolbar(identifier: "ViewerToolbar")
toolbar.delegate = self
toolbar.displayMode = .iconOnly
window.toolbar = toolbar
```

- [ ] **Step 2: NSToolbarDelegate を実装**

`ViewerWindowController` に NSToolbar 関連のコードを追加:

```swift
private static let sourceToggleItemIdentifier = NSToolbarItem.Identifier("sourceToggle")
private var isSourceMode = false
```

extension で `NSToolbarDelegate` に準拠:

```swift
extension ViewerWindowController: NSToolbarDelegate {
    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.sourceToggleItemIdentifier else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Source"
        item.toolTip = "Toggle source view"
        item.isBordered = true
        item.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Source")
        item.target = self
        item.action = #selector(toggleSourceView(_:))
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.sourceToggleItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sourceToggleItemIdentifier, .flexibleSpace, .space]
    }
}
```

- [ ] **Step 3: トグルアクションを追加**

Menu Actions セクションに `toggleSourceView` を追加:

```swift
@objc func toggleSourceView(_ sender: Any?) {
    isSourceMode.toggle()
    let mode: ViewerBridge.ViewMode = isSourceMode ? .source : .rendered
    webViewProxy.webView?.evaluateJavaScript(ViewerBridge.viewModeScript(mode))
    updateSourceToggleAppearance()
}
```

ボタンの外観更新メソッド:

```swift
private func updateSourceToggleAppearance() {
    guard let toolbar = window?.toolbar,
          let item = toolbar.items.first(where: { $0.itemIdentifier == Self.sourceToggleItemIdentifier })
    else { return }
    if isSourceMode {
        item.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "Rendered")
        item.toolTip = "Toggle rendered view"
    } else {
        item.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Source")
        item.toolTip = "Toggle source view"
    }
}
```

- [ ] **Step 4: ファイル切り替え時にトグル状態をリセット**

`switchFile(to:)` と `handleRename(to:)` の末尾で呼ぶリセットメソッド:

```swift
private func resetSourceMode() {
    isSourceMode = false
    updateSourceToggleAppearance()
}
```

`switchFile(to:)` の末尾に `resetSourceMode()` を追加。

- [ ] **Step 5: isRenderable に応じてボタンの表示/非表示を制御**

`switchFile(to:)` でファイルタイプに応じてツールバーアイテムの表示を切り替える:

```swift
private func updateToolbarVisibility() {
    guard let toolbar = window?.toolbar,
          let item = toolbar.items.first(where: { $0.itemIdentifier == Self.sourceToggleItemIdentifier })
    else { return }
    item.isVisible = store.fileType.isRenderable
}
```

`switchFile(to:)` の `store.openFile(newURL)` の後に `updateToolbarVisibility()` を呼ぶ。
初期表示時（`init` の `store.openFile(fileURL)` の後）にも呼ぶ。

ただし `isVisible` は macOS 15+ の API。macOS 14 対応のため、代わりに `NSToolbarDelegate` の `toolbarDefaultItemIdentifiers` 内で `store.fileType.isRenderable` に応じてアイテムを含めるかどうかを動的に切り替え、`toolbar.validateVisibleItems()` で更新する方式にする。

あるいは、非 renderable ファイルでは `item.isEnabled = false`（ボタンをグレーアウト）にする方がシンプル:

```swift
private func updateToolbarVisibility() {
    guard let toolbar = window?.toolbar,
          let item = toolbar.items.first(where: { $0.itemIdentifier == Self.sourceToggleItemIdentifier })
    else { return }
    item.isEnabled = store.fileType.isRenderable
}
```

- [ ] **Step 6: ビルドして動作確認**

```bash
cd MmdviewApp && swift build 2>&1 | tail -5
```
Expected: Build succeeded

アプリを起動し:
1. `.mmd` ファイルを開く → ツールバーに `</>` ボタンが表示される
2. ボタンをクリック → ソース表示に切り替わる
3. もう一度クリック → レンダリング表示に戻る
4. `.swift` ファイルを開く → ボタンがグレーアウト
5. `.svg` ファイルを開く → SVG が画像として表示される
6. `.html` ファイルを開く → HTML がレンダリングされる

- [ ] **Step 7: コミット**

```bash
git add MmdviewApp/mmdview/App/ViewerWindowController.swift
git commit -m "feat: NSToolbar にソース表示トグルボタンを追加する"
```

---

### Task 5: メニューバーに View > Toggle Source を追加する

**Files:**
- Modify: `MmdviewApp/mmdview/App/AppDelegate.swift` (メニュー定義がある場合)
  または XcodeGen の `project.yml` / `MainMenu.xib`

**Interfaces:**
- Consumes: `ViewerWindowController.toggleSourceView(_:)`
- Produces: メニュー項目 View > Toggle Source (⌘U)

- [ ] **Step 1: メニュー定義の場所を確認**

```bash
grep -rn "menuBar\|NSMenu\|mainMenu\|zoomIn\|Zoom In" MmdviewApp/mmdview/App/
```

メニューがコードで定義されているか、XIB で定義されているかを確認する。

- [ ] **Step 2: View メニューに Toggle Source 項目を追加**

既存の View メニュー（Zoom In / Zoom Out / Actual Size があるメニュー）に項目を追加:

```swift
let toggleSourceItem = NSMenuItem(
    title: String(localized: "Toggle Source", comment: "View menu item to toggle source/rendered view"),
    action: #selector(ViewerWindowController.toggleSourceView(_:)),
    keyEquivalent: "u"
)
toggleSourceItem.keyEquivalentModifierMask = [.command]
```

- [ ] **Step 3: validate で isRenderable に応じて有効/無効を切り替え**

`ViewerWindowController` に `validateMenuItem(_:)` を追加するか、既存の validate ロジックに統合:

```swift
override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(toggleSourceView(_:)) {
        menuItem.title = isSourceMode
            ? String(localized: "Show Rendered", comment: "View menu item")
            : String(localized: "Show Source", comment: "View menu item")
        return store.fileType.isRenderable
    }
    return super.validateMenuItem(menuItem)
}
```

- [ ] **Step 4: ビルドして動作確認**

```bash
cd MmdviewApp && swift build 2>&1 | tail -5
```

アプリを起動し:
1. View メニューに "Toggle Source" が表示される
2. ⌘U で切り替えられる
3. `.swift` ファイルを開くとメニュー項目がグレーアウト

- [ ] **Step 5: コミット**

```bash
git add MmdviewApp/mmdview/App/AppDelegate.swift
git commit -m "feat: View メニューに Toggle Source を追加する (⌘U)"
```

---

### Task 6: 設計ドキュメントを更新してコミットする

**Files:**
- Modify: `docs/superpowers/specs/2026-07-05-svg-source-toggle-design.md`

- [ ] **Step 1: 設計ドキュメントをコミット**

既に更新済みの設計ドキュメントを amend:

```bash
git add docs/superpowers/specs/2026-07-05-svg-source-toggle-design.md
git commit --amend --no-edit
```

- [ ] **Step 2: 手動テストチェックリスト**

アプリを `/run` で起動し、以下を確認:

- [ ] `.svg` ファイルが画像として表示される
- [ ] `.html` ファイルが iframe でレンダリング表示される
- [ ] `.mmd` ファイルのソース切り替えが動作する
- [ ] `.md` ファイルのソース切り替えが動作する
- [ ] `.swift` ファイルではトグルボタンが無効
- [ ] ⌘U ショートカットで切り替えられる
- [ ] ファイル切り替え時にレンダリングモードにリセットされる
- [ ] ダークモードで正しく表示される
