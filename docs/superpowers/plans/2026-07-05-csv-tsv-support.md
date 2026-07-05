# CSV/TSV レンダリング・ソース表示対応 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** mmdview に CSV/TSV ファイルの表レンダリング（rendered view）と Rainbow カラム着色（source view）を追加する。

**Architecture:** 既存の FileType → ViewerBridge → viewer.html パイプラインに `.csv(delimiter:)` ケースを追加する。CSV パーサー・テーブルビルダー・Rainbow ソース着色は viewer.js に純粋関数として実装し、Jest でテストする。viewer.html の `render()` / `_renderSource()` から呼び出す。

**Tech Stack:** Swift 6 / AppKit + SwiftUI, JavaScript (viewer.js / viewer.html), Jest (JS テスト), Swift Testing (Swift テスト)

## Global Constraints

- macOS 14+, Swift 6 strict concurrency
- テスト: Swift Testing フレームワーク、テスト関数名は英語 camelCase
- コミット: Conventional Commits + 日本語
- JS の純粋関数は viewer.js に置き、`module.exports` でエクスポートして Jest テスト可能にする
- viewer.html 内の DOM 操作コードは viewer.js の純粋関数を呼び出す形にする

---

### Task 1: FileType に `.csv(delimiter:)` ケースを追加する

**Files:**
- Modify: `MmdviewApp/mmdview/Viewer/FileType.swift`
- Modify: `MmdviewApp/mmdviewTests/FileTypeTests.swift`

**Interfaces:**
- Produces: `FileType.csv(delimiter: String)` ケース、`FileType.csvExtensions` / `FileType.tsvExtensions` 定数、`FileType.csvDelimiter: String?` プロパティ、`FileType.jsValue` が `"csv"` を返す、`FileType.isRenderable` が `true` を返す

- [ ] **Step 1: FileTypeTests.swift にテストを追加する**

`knownExtensions` テストの引数リストに CSV/TSV を追加する:

```swift
("csv", FileType.csv(delimiter: ",")),
("tsv", FileType.csv(delimiter: "\t")),
("CSV", FileType.csv(delimiter: ",")),
("TSV", FileType.csv(delimiter: "\t")),
```

`jsValueMapping` テストの引数リストに追加する:

```swift
(FileType.csv(delimiter: ","), "csv"),
```

`codeLanguageOnlyForCode` テストに追加する:

```swift
#expect(FileType.csv(delimiter: ",").codeLanguage == nil)
```

`isRenderable` テストに追加する:

```swift
#expect(FileType.csv(delimiter: ",").isRenderable == true)
```

`extensionListsHaveNoDuplicates` テストに CSV/TSV 拡張子リストを追加する:

```swift
let all = FileType.mermaidExtensions + FileType.markdownExtensions + FileType.codeExtensions
    + FileType.svgExtensions + FileType.htmlExtensions
    + FileType.csvExtensions + FileType.tsvExtensions
```

`csvDelimiter` 専用テストを追加する:

```swift
@Test
func csvDelimiterOnlyForCsv() {
    #expect(FileType.csv(delimiter: ",").csvDelimiter == ",")
    #expect(FileType.csv(delimiter: "\t").csvDelimiter == "\t")
    #expect(FileType.mmd.csvDelimiter == nil)
    #expect(FileType.markdown.csvDelimiter == nil)
    #expect(FileType.code(language: "swift").csvDelimiter == nil)
}
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `cd MmdviewApp && swift test 2>&1 | tail -20`
Expected: コンパイルエラー（`csv` ケースが未定義）

- [ ] **Step 3: FileType.swift に `.csv(delimiter:)` を実装する**

enum に `case csv(delimiter: String)` を追加する:

```swift
enum FileType: Sendable, Equatable {
    case mmd
    case markdown
    case svg
    case html
    case csv(delimiter: String)
    case code(language: String)
```

拡張子リストを追加する:

```swift
static let csvExtensions = ["csv"]
static let tsvExtensions = ["tsv"]
```

`init(url:)` に CSV/TSV 判定を追加する（`codeExtensionLanguages` の前に配置して csv/tsv が code にフォールバックしないようにする）:

```swift
} else if Self.csvExtensions.contains(ext) {
    self = .csv(delimiter: ",")
} else if Self.tsvExtensions.contains(ext) {
    self = .csv(delimiter: "\t")
} else if let language = Self.codeExtensionLanguages[ext] {
```

`jsValue` に csv ケースを追加する:

```swift
var jsValue: String {
    switch self {
    case .mmd: "mmd"
    case .markdown: "md"
    case .svg: "svg"
    case .html: "html"
    case .csv: "csv"
    case .code: "code"
    }
}
```

`csvDelimiter` プロパティを追加する:

```swift
var csvDelimiter: String? {
    if case let .csv(delimiter) = self { return delimiter }
    return nil
}
```

`isRenderable` に csv ケースを追加する:

```swift
var isRenderable: Bool {
    switch self {
    case .mmd, .markdown, .svg, .html, .csv: true
    case .code: false
    }
}
```

- [ ] **Step 4: テストを実行して全パスを確認する**

Run: `cd MmdviewApp && swift test 2>&1 | tail -20`
Expected: 全テスト PASS

- [ ] **Step 5: コミットする**

```bash
git add MmdviewApp/mmdview/Viewer/FileType.swift MmdviewApp/mmdviewTests/FileTypeTests.swift
git commit -m "feat: FileType に .csv(delimiter:) ケースを追加する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 2: ViewerBridge で CSV の delimiter を第 3 引数として渡す

**Files:**
- Modify: `MmdviewApp/mmdview/Viewer/ViewerBridge.swift`
- Modify: `MmdviewApp/mmdviewTests/ViewerBridgeTests.swift`

**Interfaces:**
- Consumes: `FileType.csv(delimiter: String)`, `FileType.csvDelimiter: String?`, `FileType.jsValue` が `"csv"` を返す
- Produces: `ViewerBridge.renderScript(content:fileType:)` が `.csv(delimiter: ",")` のとき `render(content, 'csv', ',')` を、`.csv(delimiter: "\t")` のとき `render(content, 'csv', '\t')` を返す

- [ ] **Step 1: ViewerBridgeTests.swift にテストを追加する**

```swift
@Test("csv タイプは第 3 引数に delimiter を渡す")
func renderScriptAppendsDelimiterForCsv() throws {
    let script = try #require(
        ViewerBridge.renderScript(content: "a,b\n1,2", fileType: .csv(delimiter: ","))
    )
    #expect(script.hasSuffix("\", 'csv', ',')"))
}

@Test("tsv タイプは第 3 引数にタブ delimiter を渡す")
func renderScriptAppendsTabDelimiterForTsv() throws {
    let script = try #require(
        ViewerBridge.renderScript(content: "a\tb\n1\t2", fileType: .csv(delimiter: "\t"))
    )
    #expect(script.hasSuffix("\", 'csv', '\\t')"))
}
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `cd MmdviewApp && swift test --filter ViewerBridgeTests 2>&1 | tail -20`
Expected: FAIL（csv の delimiter が渡されていない）

- [ ] **Step 3: ViewerBridge.renderScript を修正する**

`renderScript` メソッド内で、`codeLanguage` チェックに加えて `csvDelimiter` もチェックする。delimiter は `\t` の場合 JS 文字列リテラル内でエスケープが必要なので注意:

```swift
static func renderScript(content: String, fileType: FileType) -> String? {
    guard let jsonData = try? JSONEncoder().encode(content),
          let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }
    if let language = fileType.codeLanguage {
        return "render(\(jsonString), '\(fileType.jsValue)', '\(language)')"
    }
    if let delimiter = fileType.csvDelimiter {
        let escaped = delimiter == "\t" ? "\\t" : delimiter
        return "render(\(jsonString), '\(fileType.jsValue)', '\(escaped)')"
    }
    return "render(\(jsonString), '\(fileType.jsValue)')"
}
```

- [ ] **Step 4: テストを実行して全パスを確認する**

Run: `cd MmdviewApp && swift test --filter ViewerBridgeTests 2>&1 | tail -20`
Expected: 全テスト PASS

- [ ] **Step 5: コミットする**

```bash
git add MmdviewApp/mmdview/Viewer/ViewerBridge.swift MmdviewApp/mmdviewTests/ViewerBridgeTests.swift
git commit -m "feat: ViewerBridge で CSV delimiter を第 3 引数として渡す

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: viewer.js に CSV パーサー・テーブルビルダー・Rainbow ソース着色を追加する

**Files:**
- Modify: `MmdviewApp/mmdview/Resources/viewer.js`
- Modify: `MmdviewApp/mmdview/Resources/__tests__/viewer.test.js`

**Interfaces:**
- Consumes: `escapeHtml(text)` from viewer.js
- Produces:
  - `parseCsv(content, delimiter)` → `string[][]` — RFC 4180 準拠 CSV パーサー
  - `buildTableHtml(rows)` → `string` — 1行目を `<thead>`、残りを `<tbody>` にした HTML テーブル文字列
  - `renderCsvSourceHtml(content, delimiter)` → `string` — Rainbow カラム着色した `<pre><code>` HTML 文字列

- [ ] **Step 1: viewer.test.js に parseCsv のテストを追加する**

```javascript
describe('parseCsv', () => {
  test('parses simple comma-separated rows', () => {
    expect(parseCsv('a,b,c\n1,2,3', ',')).toEqual([['a','b','c'],['1','2','3']]);
  });

  test('parses tab-separated rows', () => {
    expect(parseCsv('a\tb\tc\n1\t2\t3', '\t')).toEqual([['a','b','c'],['1','2','3']]);
  });

  test('handles quoted fields with commas', () => {
    expect(parseCsv('"a,b",c\n1,2', ',')).toEqual([['a,b','c'],['1','2']]);
  });

  test('handles escaped quotes inside quoted fields', () => {
    expect(parseCsv('"say ""hello""",b\n1,2', ',')).toEqual([['say "hello"','b'],['1','2']]);
  });

  test('handles newlines inside quoted fields', () => {
    expect(parseCsv('"line1\nline2",b\n1,2', ',')).toEqual([['line1\nline2','b'],['1','2']]);
  });

  test('handles empty fields', () => {
    expect(parseCsv(',b,\n1,,3', ',')).toEqual([['','b',''],['1','','3']]);
  });

  test('handles single row without trailing newline', () => {
    expect(parseCsv('a,b,c', ',')).toEqual([['a','b','c']]);
  });

  test('handles trailing newline', () => {
    expect(parseCsv('a,b\n1,2\n', ',')).toEqual([['a','b'],['1','2']]);
  });

  test('handles CRLF line endings', () => {
    expect(parseCsv('a,b\r\n1,2', ',')).toEqual([['a','b'],['1','2']]);
  });

  test('returns empty array for empty string', () => {
    expect(parseCsv('', ',')).toEqual([]);
  });

  test('handles single field', () => {
    expect(parseCsv('a', ',')).toEqual([['a']]);
  });
});
```

- [ ] **Step 2: viewer.test.js に buildTableHtml のテストを追加する**

```javascript
describe('buildTableHtml', () => {
  test('builds table with thead and tbody', () => {
    const html = buildTableHtml([['Name','Age'],['Alice','30'],['Bob','25']]);
    expect(html).toContain('<table>');
    expect(html).toContain('<thead>');
    expect(html).toContain('<th>Name</th>');
    expect(html).toContain('<th>Age</th>');
    expect(html).toContain('<tbody>');
    expect(html).toContain('<td>Alice</td>');
    expect(html).toContain('<td>30</td>');
    expect(html).toContain('</table>');
  });

  test('header-only table has empty tbody', () => {
    const html = buildTableHtml([['A','B']]);
    expect(html).toContain('<thead>');
    expect(html).toContain('<tbody></tbody>');
  });

  test('empty rows returns empty string', () => {
    expect(buildTableHtml([])).toBe('');
  });

  test('escapes HTML in cell values', () => {
    const html = buildTableHtml([['<script>'],['&"']]);
    expect(html).not.toContain('<script>');
    expect(html).toContain('&lt;script&gt;');
    expect(html).toContain('&amp;&quot;');
  });

  test('pads short rows with empty cells', () => {
    const html = buildTableHtml([['A','B','C'],['1']]);
    const tdCount = (html.match(/<td>/g) || []).length + (html.match(/<td>[^<]*<\/td>/g) || []).length;
    // 1行目は th×3、2行目は td が 3 つ(うち 2 つは空)
    expect(html).toContain('<td>1</td>');
    expect(html.match(/<td><\/td>/g).length).toBe(2);
  });
});
```

- [ ] **Step 3: viewer.test.js に renderCsvSourceHtml のテストを追加する**

```javascript
describe('renderCsvSourceHtml', () => {
  test('wraps output in pre/code', () => {
    const html = renderCsvSourceHtml('a,b\n1,2', ',');
    expect(html.startsWith('<pre><code class="csv-source">')).toBe(true);
    expect(html.endsWith('</code></pre>')).toBe(true);
  });

  test('applies rotating colors to columns', () => {
    const html = renderCsvSourceHtml('a,b,c', ',');
    // 各列が異なる色の span で囲まれている
    expect(html).toContain('<span class="csv-col-0">');
    expect(html).toContain('<span class="csv-col-1">');
    expect(html).toContain('<span class="csv-col-2">');
  });

  test('delimiter is not wrapped in a color span', () => {
    const html = renderCsvSourceHtml('a,b', ',');
    // delimiter はそのまま表示される
    expect(html).toContain('</span>,<span');
  });

  test('escapes HTML in field values', () => {
    const html = renderCsvSourceHtml('<b>,&', ',');
    expect(html).toContain('&lt;b&gt;');
    expect(html).toContain('&amp;');
  });

  test('handles tab delimiter', () => {
    const html = renderCsvSourceHtml('a\tb', '\t');
    expect(html).toContain('</span>\t<span');
  });

  test('returns empty pre/code for empty string', () => {
    const html = renderCsvSourceHtml('', ',');
    expect(html).toBe('<pre><code class="csv-source"></code></pre>');
  });

  test('handles quoted fields preserving quotes in source view', () => {
    const html = renderCsvSourceHtml('"a,b",c', ',');
    // ソース表示ではクオート付きフィールドを1つの色で表示する
    expect(html).toContain('<span class="csv-col-0">&quot;a,b&quot;</span>');
    expect(html).toContain('<span class="csv-col-1">c</span>');
  });
});
```

- [ ] **Step 4: テストを実行して失敗を確認する**

Run: `cd MmdviewApp/mmdview/Resources && npx jest --testPathPattern=viewer.test 2>&1 | tail -20`
Expected: FAIL（parseCsv, buildTableHtml, renderCsvSourceHtml が未定義）

- [ ] **Step 5: viewer.js に parseCsv を実装する**

viewer.js の `renderCodeHtml` 関数の後に追加する。RFC 4180 準拠の状態マシンベースパーサー:

```javascript
function parseCsv(content, delimiter) {
  if (!content) { return []; }
  var rows = [];
  var row = [];
  var field = '';
  var inQuotes = false;
  var i = 0;
  while (i < content.length) {
    var ch = content[i];
    if (inQuotes) {
      if (ch === '"') {
        if (i + 1 < content.length && content[i + 1] === '"') {
          field += '"';
          i += 2;
        } else {
          inQuotes = false;
          i++;
        }
      } else {
        field += ch;
        i++;
      }
    } else {
      if (ch === '"') {
        inQuotes = true;
        i++;
      } else if (ch === delimiter) {
        row.push(field);
        field = '';
        i++;
      } else if (ch === '\r') {
        row.push(field);
        field = '';
        rows.push(row);
        row = [];
        i++;
        if (i < content.length && content[i] === '\n') { i++; }
      } else if (ch === '\n') {
        row.push(field);
        field = '';
        rows.push(row);
        row = [];
        i++;
      } else {
        field += ch;
        i++;
      }
    }
  }
  if (field !== '' || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}
```

- [ ] **Step 6: viewer.js に buildTableHtml を実装する**

```javascript
function buildTableHtml(rows) {
  if (rows.length === 0) { return ''; }
  var maxCols = 0;
  for (var r = 0; r < rows.length; r++) {
    if (rows[r].length > maxCols) { maxCols = rows[r].length; }
  }
  var html = '<table><thead><tr>';
  for (var c = 0; c < maxCols; c++) {
    html += '<th>' + escapeHtml(c < rows[0].length ? rows[0][c] : '') + '</th>';
  }
  html += '</tr></thead><tbody>';
  for (var r = 1; r < rows.length; r++) {
    html += '<tr>';
    for (var c = 0; c < maxCols; c++) {
      html += '<td>' + escapeHtml(c < rows[r].length ? rows[r][c] : '') + '</td>';
    }
    html += '</tr>';
  }
  html += '</tbody></table>';
  return html;
}
```

- [ ] **Step 7: viewer.js に renderCsvSourceHtml を実装する**

Rainbow カラム着色。ソース表示では生テキストの見た目を保ちつつ、列ごとに色分けする。クオート内の delimiter は列区切りとして扱わない:

```javascript
var CSV_COL_COUNT = 8;

function renderCsvSourceHtml(content, delimiter) {
  if (!content) { return '<pre><code class="csv-source"></code></pre>'; }
  var lines = content.split('\n');
  if (lines.length > 0 && lines[lines.length - 1] === '') { lines.pop(); }
  var htmlLines = [];
  for (var l = 0; l < lines.length; l++) {
    var line = lines[l];
    if (line.endsWith('\r')) { line = line.slice(0, -1); }
    var parts = splitCsvSourceLine(line, delimiter);
    var htmlParts = [];
    for (var c = 0; c < parts.length; c++) {
      var cls = 'csv-col-' + (c % CSV_COL_COUNT);
      htmlParts.push('<span class="' + cls + '">' + escapeHtml(parts[c]) + '</span>');
    }
    htmlLines.push(htmlParts.join(delimiter === '\t' ? '\t' : escapeHtml(delimiter)));
  }
  return '<pre><code class="csv-source">' + htmlLines.join('\n') + '</code></pre>';
}

function splitCsvSourceLine(line, delimiter) {
  var parts = [];
  var current = '';
  var inQuotes = false;
  var i = 0;
  while (i < line.length) {
    var ch = line[i];
    if (inQuotes) {
      current += ch;
      if (ch === '"') {
        if (i + 1 < line.length && line[i + 1] === '"') {
          current += '"';
          i += 2;
        } else {
          inQuotes = false;
          i++;
        }
      } else {
        i++;
      }
    } else {
      if (ch === '"') {
        inQuotes = true;
        current += ch;
        i++;
      } else if (ch === delimiter) {
        parts.push(current);
        current = '';
        i++;
      } else {
        current += ch;
        i++;
      }
    }
  }
  parts.push(current);
  return parts;
}
```

- [ ] **Step 8: viewer.js の module.exports にエクスポートを追加する**

```javascript
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    // ...既存のエクスポート...
    parseCsv: parseCsv,
    buildTableHtml: buildTableHtml,
    renderCsvSourceHtml: renderCsvSourceHtml,
    CSV_COL_COUNT: CSV_COL_COUNT,
  };
}
```

viewer.test.js の先頭の require にも追加する:

```javascript
const {
  // ...既存...
  parseCsv,
  buildTableHtml,
  renderCsvSourceHtml,
  CSV_COL_COUNT,
} = require('../viewer');
```

- [ ] **Step 9: テストを実行して全パスを確認する**

Run: `cd MmdviewApp/mmdview/Resources && npx jest --testPathPattern=viewer.test 2>&1 | tail -30`
Expected: 全テスト PASS

- [ ] **Step 10: コミットする**

```bash
git add MmdviewApp/mmdview/Resources/viewer.js MmdviewApp/mmdview/Resources/__tests__/viewer.test.js
git commit -m "feat: CSV パーサー・テーブルビルダー・Rainbow ソース着色を viewer.js に追加する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 4: viewer.html と style.css に CSV レンダリングを組み込む

**Files:**
- Modify: `MmdviewApp/mmdview/Resources/viewer.html`
- Modify: `MmdviewApp/mmdview/Resources/style.css`

**Interfaces:**
- Consumes: `parseCsv(content, delimiter)`, `buildTableHtml(rows)`, `renderCsvSourceHtml(content, delimiter)` from viewer.js
- Produces: `render(content, 'csv', delimiter)` が rendered view でテーブル、source view で Rainbow 着色を表示する

- [ ] **Step 1: viewer.html の render() に CSV 分岐を追加する**

`render()` 関数内の `} else if (type === 'code') {` の前に CSV 分岐を挿入する:

```javascript
    } else if (type === 'csv') {
      diagramWrap.classList.remove('code-body');
      diagramWrap.classList.remove('html-body');
      diagramWrap.classList.add('markdown-body');
      var rows = parseCsv(content, lang || ',');
      diagramWrap.innerHTML = buildTableHtml(rows);
```

- [ ] **Step 2: viewer.html の _renderSource() に CSV 分岐を追加する**

`_renderSource()` 関数で CSV の場合は Rainbow ソース着色を使う。highlight.js の代わりに `renderCsvSourceHtml()` を呼ぶ:

```javascript
  function _renderSource(content, type, lang) {
    var diagramWrap = document.getElementById('diagram-wrap');
    diagramWrap.classList.remove('markdown-body');
    diagramWrap.classList.remove('html-body');
    diagramWrap.classList.add('code-body');
    if (type === 'csv') {
      diagramWrap.innerHTML = renderCsvSourceHtml(content, lang || ',');
    } else {
      var sourceLang = (type === 'svg' || type === 'html') ? 'xml'
                     : (type === 'md') ? 'markdown'
                     : lang || 'plaintext';
      diagramWrap.innerHTML = renderCodeHtml(window.hljs, content, sourceLang);
    }
    _mmdApplyZoom();
  }
```

- [ ] **Step 3: style.css に Rainbow カラム着色の CSS を追加する**

style.css の末尾（アプリ側スタイル領域）に追加。ライト/ダークモード対応の 8 色パレット:

```css
/* ── CSV Rainbow ソース表示 ── */
.csv-col-0 { color: #c00; }
.csv-col-1 { color: #080; }
.csv-col-2 { color: #00c; }
.csv-col-3 { color: #c80; }
.csv-col-4 { color: #808; }
.csv-col-5 { color: #088; }
.csv-col-6 { color: #c44; }
.csv-col-7 { color: #448; }

@media (prefers-color-scheme: dark) {
  .csv-col-0 { color: #f88; }
  .csv-col-1 { color: #8f8; }
  .csv-col-2 { color: #8af; }
  .csv-col-3 { color: #fd8; }
  .csv-col-4 { color: #f8f; }
  .csv-col-5 { color: #8ff; }
  .csv-col-6 { color: #fa8; }
  .csv-col-7 { color: #8cf; }
}
```

- [ ] **Step 4: swift build で viewer.html / style.css がエラーなくビルドされることを確認する**

Run: `cd MmdviewApp && swift build 2>&1 | tail -10`
Expected: Build succeeded

- [ ] **Step 5: コミットする**

```bash
git add MmdviewApp/mmdview/Resources/viewer.html MmdviewApp/mmdview/Resources/style.css
git commit -m "feat: viewer.html と style.css に CSV テーブルレンダリングと Rainbow ソース表示を追加する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 5: Info.plist に CSV/TSV の UTI 宣言とドキュメントタイプを追加する

**Files:**
- Modify: `MmdviewApp/mmdview/Info.plist`
- Modify: `MmdviewApp/mmdviewTests/InfoPlistTests.swift`

**Interfaces:**
- Consumes: `FileType.csvExtensions`, `FileType.tsvExtensions`
- Produces: macOS が mmdview を CSV/TSV ファイルの「このアプリケーションで開く」候補として認識する

- [ ] **Step 1: InfoPlistTests.swift にテストを追加する**

CSV/TSV のドキュメントタイプが Info.plist に宣言されていることを検証するテストを追加する:

```swift
@Test("CSV/TSV のドキュメントタイプが宣言されている")
func claimsCsvTsvContentTypes() throws {
    let expectedUTIs: Set<String> = [
        "public.comma-separated-values-text",
        "public.tab-separated-values-text",
    ]
    let docTypes = try infoPlist()["CFBundleDocumentTypes"] as! [[String: Any]]
    let allContentTypes = Set(docTypes.flatMap { ($0["LSItemContentTypes"] as? [String]) ?? [] })
    for uti in expectedUTIs {
        #expect(allContentTypes.contains(uti), "Missing UTI: \(uti)")
    }
}
```

既存テストのヘルパー `infoPlist()` があればそれを使う。なければ InfoPlistTests 内の既存パターンに従って Info.plist を読む。

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `cd MmdviewApp && swift test --filter InfoPlistTests 2>&1 | tail -20`
Expected: FAIL（CSV/TSV UTI が未宣言）

- [ ] **Step 3: Info.plist に CFBundleDocumentTypes エントリを追加する**

既存の Source Code ドキュメントタイプエントリの後に、CSV/TSV 用のエントリを追加する:

```xml
<dict>
    <key>CFBundleTypeName</key>
    <string>CSV / TSV</string>
    <key>CFBundleTypeRole</key>
    <string>Alternate</string>
    <key>LSItemContentTypes</key>
    <array>
        <string>public.comma-separated-values-text</string>
        <string>public.tab-separated-values-text</string>
    </array>
</dict>
```

- [ ] **Step 4: テストを実行して全パスを確認する**

Run: `cd MmdviewApp && swift test --filter InfoPlistTests 2>&1 | tail -20`
Expected: 全テスト PASS

- [ ] **Step 5: 全テストスイートを実行して回帰がないことを確認する**

Run: `cd MmdviewApp && swift test 2>&1 | tail -20`
Expected: 全テスト PASS

Run: `cd MmdviewApp/mmdview/Resources && npx jest 2>&1 | tail -10`
Expected: 全テスト PASS

- [ ] **Step 6: コミットする**

```bash
git add MmdviewApp/mmdview/Info.plist MmdviewApp/mmdviewTests/InfoPlistTests.swift
git commit -m "feat: Info.plist に CSV/TSV のドキュメントタイプ宣言を追加する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```
