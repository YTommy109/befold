# 行番号表示とボトムバー実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ソースコード表示時に行番号を表示し、ウィンドウ下部のネイティブ AppKit スタイルのボトムバーで表示/非表示を切り替えられるようにする。

**Architecture:** viewer.js の `renderCodeHtml` / `renderCsvSourceHtml` に行番号付き HTML 生成ロジックを追加し、viewer.html の `setLineNumbers()` JS ブリッジ関数で切り替える。Swift 側は `ViewerStore.showLineNumbers` で状態管理し、SwiftUI の `ViewerBottomBar` で UI を提供する。`UserDefaults` でアプリ全体の設定として永続化する。

**Tech Stack:** Swift 6 / SwiftUI / AppKit / WKWebView / JavaScript / CSS / Jest

## Global Constraints

- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- macOS 14+
- Swift Testing フレームワーク（XCTest ではない）
- テスト関数名は英語 camelCase、日本語説明は `@Test("...")` で付ける
- コミットメッセージは Conventional Commits + 日本語
- JS テストは Jest (`cd BefoldApp && npx jest`)
- Swift テストは `cd BefoldApp && swift test`

---

### Task 1: viewer.js に行番号付きコード HTML 生成関数を追加する

**Files:**
- Modify: `BefoldApp/befold/Resources/viewer.js`
- Modify: `BefoldApp/befold/Resources/__tests__/viewer.test.js`

**Interfaces:**
- Produces: `renderCodeHtml(hljs, str, lang, showLineNumbers)` — 第 4 引数 `showLineNumbers` (bool, デフォルト false) が true のとき行番号付き `<table>` HTML を返す
- Produces: `renderCsvSourceHtml(content, delimiter, showLineNumbers)` — 同上

- [ ] **Step 1: viewer.test.js に renderCodeHtml の行番号テストを追加する**

```javascript
describe('renderCodeHtml with line numbers', () => {
  const hljs = require('highlight.js');

  test('showLineNumbers=true wraps output in a table with line numbers', () => {
    const result = renderCodeHtml(hljs, 'line1\nline2\nline3', 'plaintext', true);
    expect(result).toContain('<table class="code-table">');
    expect(result).toContain('<td class="line-number">1</td>');
    expect(result).toContain('<td class="line-number">2</td>');
    expect(result).toContain('<td class="line-number">3</td>');
    expect(result).toContain('<td class="line-content">');
  });

  test('showLineNumbers=false returns plain pre/code (existing behavior)', () => {
    const result = renderCodeHtml(hljs, 'let x = 1', 'swift', false);
    expect(result).not.toContain('code-table');
    expect(result).toContain('<pre><code');
  });

  test('showLineNumbers defaults to false when omitted', () => {
    const result = renderCodeHtml(hljs, 'let x = 1', 'swift');
    expect(result).not.toContain('code-table');
  });

  test('single line produces one row', () => {
    const result = renderCodeHtml(null, 'hello', 'plaintext', true);
    expect(result).toContain('<td class="line-number">1</td>');
    expect(result).not.toContain('<td class="line-number">2</td>');
  });

  test('empty content produces single empty row', () => {
    const result = renderCodeHtml(null, '', 'plaintext', true);
    expect(result).toContain('<table class="code-table">');
    expect(result).toContain('<td class="line-number">1</td>');
  });

  test('HTML is escaped in line content', () => {
    const result = renderCodeHtml(null, '<script>alert(1)</script>', 'plaintext', true);
    expect(result).not.toContain('<script>');
    expect(result).toContain('&lt;script&gt;');
  });

  test('hljs highlighted code is split into lines and wrapped', () => {
    const result = renderCodeHtml(hljs, 'let x = 1\nlet y = 2', 'swift', true);
    expect(result).toContain('<td class="line-number">1</td>');
    expect(result).toContain('<td class="line-number">2</td>');
    expect(result).toContain('hljs');
  });
});
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && npx jest --testPathPattern viewer.test.js --verbose 2>&1 | tail -20`
Expected: FAIL — renderCodeHtml に第 4 引数が渡されても無視されるため `code-table` が含まれない

- [ ] **Step 3: viewer.js に行番号付き HTML 生成ロジックを実装する**

`viewer.js` の `renderCodeHtml` を拡張する。

```javascript
function wrapWithLineNumbers(codeHtml) {
  var lines = codeHtml.split('\n');
  // 末尾が空行の場合は除去する(highlight.js が末尾に \n を付けることがある)
  if (lines.length > 1 && lines[lines.length - 1] === '') {
    lines.pop();
  }
  var rows = '';
  for (var i = 0; i < lines.length; i++) {
    rows += '<tr><td class="line-number">' + (i + 1)
      + '</td><td class="line-content">' + (lines[i] || '') + '</td></tr>';
  }
  return '<table class="code-table">' + rows + '</table>';
}

function renderCodeHtml(hljs, str, lang, showLineNumbers) {
  var highlighted = highlightCode(hljs, str, lang);
  if (showLineNumbers) {
    if (highlighted) {
      // <pre><code ...>CONTENT</code></pre> から CONTENT を抽出する
      var match = highlighted.match(/^<pre><code[^>]*>([\s\S]*)<\/code><\/pre>$/);
      if (match) {
        var openTag = highlighted.slice(0, highlighted.indexOf('>',
          highlighted.indexOf('<code')) + 1);
        // openTag = '<pre><code class="hljs language-xxx">'
        return '<pre>' + openTag.slice(5) + wrapWithLineNumbers(match[1])
          + '</code></pre>';
      }
    }
    return '<pre><code>' + wrapWithLineNumbers(escapeHtml(str)) + '</code></pre>';
  }
  if (highlighted) { return highlighted; }
  return '<pre><code>' + escapeHtml(str) + '</code></pre>';
}
```

補足: `highlightCode` の返り値は `<pre><code class="hljs language-xxx">...CONTENT...</code></pre>` の形式。行番号モードでは CONTENT を行で分割して `<table>` に包む。`<pre>` の中に `<code>` と `<table>` を入れる構造にして、既存の `.code-body pre code` のスタイルをそのまま活かす。

- [ ] **Step 4: renderCsvSourceHtml にも showLineNumbers を追加する**

viewer.test.js に CSV ソースの行番号テストを追加する:

```javascript
describe('renderCsvSourceHtml with line numbers', () => {
  test('showLineNumbers=true wraps output in a table with line numbers', () => {
    const html = renderCsvSourceHtml('a,b\n1,2', ',', true);
    expect(html).toContain('<table class="code-table">');
    expect(html).toContain('<td class="line-number">1</td>');
    expect(html).toContain('<td class="line-number">2</td>');
    expect(html).toContain('csv-col-');
  });

  test('showLineNumbers=false returns existing format', () => {
    const html = renderCsvSourceHtml('a,b\n1,2', ',', false);
    expect(html).not.toContain('code-table');
  });

  test('showLineNumbers defaults to false when omitted', () => {
    const html = renderCsvSourceHtml('a,b', ',');
    expect(html).not.toContain('code-table');
  });
});
```

`renderCsvSourceHtml` を拡張する:

```javascript
function renderCsvSourceHtml(content, delimiter, showLineNumbers) {
  if (!content) { return '<pre><code class="csv-source"></code></pre>'; }
  var tokenRows = tokenizeCsvRows(content, delimiter);
  var htmlLines = [];
  for (var r = 0; r < tokenRows.length; r++) {
    var cells = tokenRows[r];
    var htmlParts = [];
    for (var c = 0; c < cells.length; c++) {
      var cls = 'csv-col-' + (c % CSV_COL_COUNT);
      htmlParts.push('<span class="' + cls + '">' + escapeHtml(cells[c].raw) + '</span>');
    }
    htmlLines.push(htmlParts.join(delimiter));
  }
  var body = htmlLines.join('\n');
  if (showLineNumbers) {
    body = wrapWithLineNumbers(body);
  }
  return '<pre><code class="csv-source">' + body + '</code></pre>';
}
```

- [ ] **Step 5: module.exports に wrapWithLineNumbers を追加する**

`viewer.js` の `module.exports` ブロックに追加:

```javascript
wrapWithLineNumbers: wrapWithLineNumbers,
```

- [ ] **Step 6: 既存テストが壊れていないことを確認する**

Run: `cd BefoldApp && npx jest --testPathPattern viewer.test.js --verbose 2>&1 | tail -30`
Expected: ALL PASS

- [ ] **Step 7: コミット**

```bash
git add BefoldApp/befold/Resources/viewer.js BefoldApp/befold/Resources/__tests__/viewer.test.js
git commit -m "feat: renderCodeHtml / renderCsvSourceHtml に行番号表示オプションを追加する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 2: viewer.html に setLineNumbers JS ブリッジ関数を追加する

**Files:**
- Modify: `BefoldApp/befold/Resources/viewer.html`
- Modify: `BefoldApp/befold/Resources/style.css`

**Interfaces:**
- Consumes: `renderCodeHtml(hljs, str, lang, showLineNumbers)` (Task 1)
- Consumes: `renderCsvSourceHtml(content, delimiter, showLineNumbers)` (Task 1)
- Produces: JS グローバル関数 `setLineNumbers(show)` — Swift 側から `evaluateJavaScript("setLineNumbers(true)")` で呼び出す

- [ ] **Step 1: viewer.html に _showLineNumbers 変数と setLineNumbers 関数を追加する**

`viewer.html` の `var _viewMode = 'rendered';` の直後に追加する:

```javascript
var _showLineNumbers = false;

function setLineNumbers(show) {
  if (_showLineNumbers === show) return;
  _showLineNumbers = show;
  if (_lastContent !== null) {
    render(_lastContent, _lastType, _lastLang);
  }
}
```

- [ ] **Step 2: render() 内のコード表示分岐で _showLineNumbers を渡す**

`viewer.html` の `render` 関数内、`type === 'code'` の分岐を修正する:

```javascript
} else if (type === 'code') {
  diagramWrap.classList.add('code-body');
  diagramWrap.innerHTML = renderCodeHtml(window.hljs, content, lang, _showLineNumbers);
```

- [ ] **Step 3: _renderSource() 内でも _showLineNumbers を渡す**

`_renderSource` 関数を修正する:

```javascript
function _renderSource(content, type, lang) {
  var diagramWrap = document.getElementById('diagram-wrap');
  diagramWrap.classList.remove('markdown-body', 'html-body', 'csv-body', 'image-body', 'pdf-body');
  diagramWrap.classList.add('code-body');
  if (type === 'csv') {
    diagramWrap.innerHTML = renderCsvSourceHtml(content, lang || ',', _showLineNumbers);
  } else {
    var sourceLang = (type === 'svg' || type === 'html') ? 'xml'
                   : (type === 'md') ? 'markdown'
                   : lang || 'plaintext';
    diagramWrap.innerHTML = renderCodeHtml(window.hljs, content, sourceLang, _showLineNumbers);
  }
  _mmdApplyZoom();
}
```

- [ ] **Step 4: style.css に行番号テーブルのスタイルを追加する**

`style.css` の `#diagram-wrap.code-body pre code` ブロックの後に追加する:

```css
/* ── 行番号テーブル ── */
.code-table {
  border-collapse: collapse;
  border-spacing: 0;
}

.line-number {
  text-align: right;
  padding-right: 1.5ch;
  color: var(--fg-muted);
  opacity: 0.5;
  min-width: 3ch;
  vertical-align: top;
  white-space: nowrap;
  user-select: none;
  -webkit-user-select: none;
}

.line-content {
  white-space: pre-wrap;
  word-break: break-all;
  width: 100%;
}
```

注: `user-select: none` は実装コスト 0 で付けられるため付与する。コピー時に行番号が含まれるかどうかは要件としては不問だが、含まれないほうが一般的に便利。

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/Resources/viewer.html BefoldApp/befold/Resources/style.css
git commit -m "feat: setLineNumbers JS ブリッジ関数と行番号 CSS スタイルを追加する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: ViewerBridge / ViewerStore に行番号状態管理を追加する

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerBridge.swift`
- Modify: `BefoldApp/befold/Viewer/ViewerStore.swift`
- Modify: `BefoldApp/befoldTests/ViewerBridgeTests.swift`
- Modify: `BefoldApp/befoldTests/ViewerStoreTests.swift`

**Interfaces:**
- Consumes: JS `setLineNumbers(show)` (Task 2)
- Produces: `ViewerBridge.lineNumbersScript(_ show: Bool) -> String`
- Produces: `ViewerStore.showLineNumbers: Bool` — `@Observable` プロパティ、`UserDefaults` で永続化

- [ ] **Step 1: ViewerBridgeTests に lineNumbersScript のテストを追加する**

```swift
@Test("lineNumbersScript がブール値を埋め込む")
func lineNumbersScriptEmbedsBool() {
    #expect(ViewerBridge.lineNumbersScript(true) == "setLineNumbers(true)")
    #expect(ViewerBridge.lineNumbersScript(false) == "setLineNumbers(false)")
}
```

- [ ] **Step 2: ViewerBridgeTests のブリッジ契約テストに setLineNumbers を追加する**

`bridgeFunctionsExistInViewerHTML` テスト内に追加:

```swift
#expect(html.contains("function setLineNumbers(show)"))
```

- [ ] **Step 3: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter ViewerBridgeTests 2>&1 | tail -20`
Expected: FAIL — `lineNumbersScript` メソッドが未定義

- [ ] **Step 4: ViewerBridge に lineNumbersScript を実装する**

`BefoldApp/befold/Viewer/ViewerBridge.swift` に追加する:

```swift
static func lineNumbersScript(_ show: Bool) -> String {
    "setLineNumbers(\(show))"
}
```

- [ ] **Step 5: ViewerBridge テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter ViewerBridgeTests 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 6: ViewerStoreTests に showLineNumbers のテストを追加する**

```swift
@Test("showLineNumbers のデフォルトは false")
func showLineNumbersDefaultsToFalse() {
    let store = makeStore(reader: InMemoryFileReader())
    #expect(!store.showLineNumbers)
    store.close()
}

@Test("showLineNumbers のトグルが UserDefaults に永続化される")
func showLineNumbersPersistedToUserDefaults() {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    let store = ViewerStore(
        watcherFactory: { _, _, _ in MockFileWatcher() },
        fileReader: InMemoryFileReader(),
        defaults: defaults
    )

    store.showLineNumbers = true
    #expect(defaults.bool(forKey: "ShowLineNumbers") == true)

    store.showLineNumbers = false
    #expect(defaults.bool(forKey: "ShowLineNumbers") == false)

    store.close()
    defaults.removePersistentDomain(forName: #function)
}
```

- [ ] **Step 7: ViewerStore に showLineNumbers プロパティを追加する**

`BefoldApp/befold/Viewer/ViewerStore.swift` を修正する。

init に `defaults` パラメータを追加する:

```swift
private let defaults: UserDefaults

init(
    watcherFactory: WatcherFactory? = nil,
    fileReader: any FileReading = DefaultFileReader(),
    defaults: UserDefaults = .standard
) {
    self.defaults = defaults
    makeWatcher = watcherFactory ?? { url, onChange, onRename in
        FileWatcher(path: url, onChange: onChange, onRename: onRename)
    }
    self.fileReader = fileReader
    _showLineNumbers = defaults.bool(forKey: Self.showLineNumbersKey)
}
```

プロパティを追加する:

```swift
private static let showLineNumbersKey = "ShowLineNumbers"

var showLineNumbers: Bool {
    didSet {
        defaults.set(showLineNumbers, forKey: Self.showLineNumbersKey)
    }
}
```

`_showLineNumbers` は `init` 内で `defaults` から読み込む。`@Observable` マクロが自動的にストレージを管理するため、`init` 内で `_showLineNumbers` に直接代入する。

- [ ] **Step 8: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter ViewerStoreTests 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 9: コミット**

```bash
git add BefoldApp/befold/Viewer/ViewerBridge.swift BefoldApp/befold/Viewer/ViewerStore.swift \
  BefoldApp/befoldTests/ViewerBridgeTests.swift BefoldApp/befoldTests/ViewerStoreTests.swift
git commit -m "feat: ViewerBridge / ViewerStore に行番号状態管理を追加する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 4: ViewerBottomBar を作成し ViewerContentView に組み込む

**Files:**
- Create: `BefoldApp/befold/Viewer/ViewerBottomBar.swift`
- Modify: `BefoldApp/befold/Viewer/ViewerContentView.swift`

**Interfaces:**
- Consumes: `ViewerStore.showLineNumbers` (Task 3)
- Consumes: `ViewerStore.fileType` — ボトムバーの表示条件に使用
- Consumes: `ViewerStore.isSourceMode` — ボトムバーの表示条件に使用
- Produces: `ViewerBottomBar` SwiftUI ビュー — ウィンドウ下部のステータスバー

- [ ] **Step 1: ViewerBottomBar.swift を作成する**

```swift
import SwiftUI

struct ViewerBottomBar: View {
    let store: ViewerStore

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.showLineNumbers.toggle()
            } label: {
                Image(systemName: "list.number")
                    .foregroundStyle(store.showLineNumbers ? .primary : .secondary)
            }
            .buttonStyle(.borderless)
            .help(store.showLineNumbers
                ? String(localized: "bottomBar.hideLineNumbers", bundle: .l10n)
                : String(localized: "bottomBar.showLineNumbers", bundle: .l10n))

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
```

- [ ] **Step 2: ViewerContentView に ViewerBottomBar を組み込む**

`ViewerContentView.swift` の `body` を修正する:

```swift
var body: some View {
    VStack(spacing: 0) {
        ZStack {
            ViewerWebView(
                content: store.content,
                fileType: store.fileType,
                isDeleted: store.isDeleted,
                filePath: store.filePath,
                isSourceMode: store.isSourceMode,
                initialZoom: currentZoom,
                onZoomChanged: onZoomChanged,
                onOpenReference: onOpenReference,
                webViewProxy: webViewProxy
            )
            .opacity(store.isUnsupported ? 0 : 1)

            if store.isUnsupported {
                UnsupportedFileView(fileURL: store.filePath)
            }
        }

        if showBottomBar {
            ViewerBottomBar(store: store)
        }
    }
}

private var showBottomBar: Bool {
    if store.isUnsupported { return false }
    if store.isSourceMode { return true }
    if case .code = store.fileType { return true }
    return false
}
```

- [ ] **Step 3: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build 2>&1 | tail -10`
Expected: Build succeeded

- [ ] **Step 4: コミット**

```bash
git add BefoldApp/befold/Viewer/ViewerBottomBar.swift BefoldApp/befold/Viewer/ViewerContentView.swift
git commit -m "feat: ViewerBottomBar を作成しウィンドウ下部に配置する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 5: ViewerWebView から JS へ行番号状態を伝搬する

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerWebView.swift`

**Interfaces:**
- Consumes: `ViewerBridge.lineNumbersScript(_ show: Bool)` (Task 3)
- Consumes: `ViewerStore.showLineNumbers` — `ViewerContentView` 経由で渡される

- [ ] **Step 1: ViewerWebView に showLineNumbers プロパティを追加する**

`ViewerWebView` の struct 定義に追加する:

```swift
let showLineNumbers: Bool
```

- [ ] **Step 2: ViewerContentView で showLineNumbers を渡す**

`ViewerContentView.swift` の `ViewerWebView(...)` 呼び出しに追加する:

```swift
ViewerWebView(
    content: store.content,
    fileType: store.fileType,
    isDeleted: store.isDeleted,
    filePath: store.filePath,
    isSourceMode: store.isSourceMode,
    showLineNumbers: store.showLineNumbers,
    initialZoom: currentZoom,
    onZoomChanged: onZoomChanged,
    onOpenReference: onOpenReference,
    webViewProxy: webViewProxy
)
```

- [ ] **Step 3: Coordinator に行番号状態の追跡と伝搬ロジックを追加する**

`Coordinator` クラスに追跡用プロパティを追加する:

```swift
private var lastShowLineNumbers: Bool?
```

`updateContent` メソッドの `doUpdate` クロージャ内で、コンテンツ更新の後に行番号状態の差分を検知して JS を送信する。ただし、`render()` 呼び出しの前に行番号状態を設定する必要があるため、`doUpdate` 内のレンダリング前に送信する。

`updateNSView` を修正して `showLineNumbers` を coordinator に渡す:

```swift
func updateNSView(_ webView: WKWebView, context: Context) {
    context.coordinator.onZoomChanged = onZoomChanged
    context.coordinator.onOpenReference = onOpenReference
    context.coordinator.initialPageZoom = initialZoom
    context.coordinator.updateContent(
        content,
        fileType: fileType,
        isDeleted: isDeleted,
        filePath: filePath,
        isSourceMode: isSourceMode,
        showLineNumbers: showLineNumbers
    )
}
```

`updateContent` のシグネチャに `showLineNumbers: Bool` を追加し、`doUpdate` クロージャ内のレンダリング(render/setViewMode の evaluateJavaScript)の直前で行番号状態を送信する:

```swift
// 行番号状態が変わった場合のみ送信する
if showLineNumbers != lastShowLineNumbers {
    webView.evaluateJavaScript(ViewerBridge.lineNumbersScript(showLineNumbers))
    lastShowLineNumbers = showLineNumbers
}
```

この送信は以下の 3 箇所の描画パスそれぞれの直前に挿入する:
1. 通常の `renderScript` 呼び出しの直前
2. `reloadViewerHTML` のコールバック内、`renderScript` 呼び出しの直前
3. 行番号だけが変わった場合(コンテンツ・ファイルタイプが同じ)に再描画をトリガーする条件追加

`needsRender` の条件に行番号状態の変化を追加する:

```swift
let needsRender = content != lastRenderedContent
    || fileType != lastRenderedFileType
    || lastWasDeleted == true
    || showLineNumbers != lastShowLineNumbers
```

- [ ] **Step 4: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build 2>&1 | tail -10`
Expected: Build succeeded

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/Viewer/ViewerWebView.swift BefoldApp/befold/Viewer/ViewerContentView.swift
git commit -m "feat: ViewerWebView から JS へ行番号状態を伝搬する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 6: View メニューに行番号トグルを追加し、ローカライズする

**Files:**
- Modify: `BefoldApp/befold/App/MainMenuBuilder.swift`
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`
- Modify: `BefoldApp/befoldTests/MainMenuBuilderTests.swift`

**Interfaces:**
- Consumes: `ViewerStore.showLineNumbers` (Task 3)
- Produces: View > Toggle Line Numbers メニュー項目 (⌘⇧L)

- [ ] **Step 1: MainMenuBuilderTests に行番号メニュー項目のテストを追加する**

```swift
@Test("View メニューに Toggle Line Numbers(⌘⇧L) がある")
func viewMenuHasToggleLineNumbers() throws {
    let mainMenu = buildMenu()
    let view = try #require(submenu(titledKey: "menu.view.title", in: mainMenu))

    let item = try #require(
        view.items.first {
            $0.action == #selector(ViewerWindowController.toggleLineNumbers(_:))
        }
    )
    #expect(item.keyEquivalent == "l")
    #expect(item.keyEquivalentModifierMask.contains(.shift))
    #expect(item.keyEquivalentModifierMask.contains(.command))
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter MainMenuBuilderTests 2>&1 | tail -20`
Expected: FAIL — `toggleLineNumbers` セレクタが未定義

- [ ] **Step 3: ViewerWindowController に toggleLineNumbers アクションを追加する**

```swift
@objc func toggleLineNumbers(_ sender: Any?) {
    store.showLineNumbers.toggle()
}
```

`validateMenuItem` に行番号メニュー項目のタイトル更新を追加する:

```swift
if menuItem.action == #selector(toggleLineNumbers(_:)) {
    menuItem.title = store.showLineNumbers
        ? String(localized: "menu.view.hideLineNumbers", bundle: .l10n)
        : String(localized: "menu.view.showLineNumbers", bundle: .l10n)
    return showsCodeContent
}
```

`showsCodeContent` ヘルパーを追加する（ボトムバーの `showBottomBar` と同じ条件）:

```swift
private var showsCodeContent: Bool {
    if store.isUnsupported { return false }
    if store.isSourceMode { return true }
    if case .code = store.fileType { return true }
    return false
}
```

- [ ] **Step 4: MainMenuBuilder の makeViewMenuItem に行番号メニュー項目を追加する**

`toggleSource` 項目の直後に追加する:

```swift
let lineNumbers = menu.addItem(
    withTitle: String(localized: "menu.view.showLineNumbers", bundle: .l10n),
    action: #selector(ViewerWindowController.toggleLineNumbers(_:)),
    keyEquivalent: "l"
)
lineNumbers.keyEquivalentModifierMask = [.command, .shift]
```

- [ ] **Step 5: Localizable.xcstrings にローカライズ文字列を追加する**

`menu.view.showRendered` エントリの後に以下を追加する:

```json
"menu.view.showLineNumbers" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Show Line Numbers" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "行番号を表示" } }
  }
},
"menu.view.hideLineNumbers" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Hide Line Numbers" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "行番号を隠す" } }
  }
},
"bottomBar.showLineNumbers" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Show Line Numbers" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "行番号を表示" } }
  }
},
"bottomBar.hideLineNumbers" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Hide Line Numbers" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "行番号を隠す" } }
  }
}
```

- [ ] **Step 6: 全テストが通ることを確認する**

Run: `cd BefoldApp && swift test 2>&1 | tail -20`
Expected: ALL PASS

Run: `cd BefoldApp && npx jest 2>&1 | tail -10`
Expected: ALL PASS

- [ ] **Step 7: コミット**

```bash
git add BefoldApp/befold/App/MainMenuBuilder.swift \
  BefoldApp/befold/App/ViewerWindowController.swift \
  BefoldApp/befold/Resources/Localizable.xcstrings \
  BefoldApp/befoldTests/MainMenuBuilderTests.swift
git commit -m "feat: View メニューに行番号トグル(⌘⇧L)を追加する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 7: 手動テストとスモークテスト

**Files:** なし（テスト実行のみ）

- [ ] **Step 1: アプリをビルドして起動する**

Run: `cd BefoldApp && swift build`

- [ ] **Step 2: 手動テスト項目を確認する**

以下を確認する:
1. `.swift` ファイルを開き、ボトムバーが表示されること
2. ボトムバーの行番号ボタンをクリックして行番号が表示/非表示されること
3. View > Show Line Numbers (⌘⇧L) で切り替わること
4. `.md` ファイルを開き、レンダリング表示ではボトムバーが非表示であること
5. ソース表示(⌘U)に切り替えるとボトムバーが表示され、行番号トグルが機能すること
6. 行番号設定がアプリ再起動後も保持されること
7. 画像・PDF ファイルではボトムバーが表示されないこと
