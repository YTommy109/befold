# コードファイル・シンタックスハイライト表示 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** mmdview で `.swift` / `.py` / `.js` / `.json` / `.yaml` 等のコードファイルを highlight.js でシンタックスハイライト表示できるようにする。

**Architecture:** `FileType` に `.code(language:)` ケースと拡張子→言語対応表を追加し（単一情報源）、ブリッジは `render(content, 'code', lang)` の 3 引数契約に拡張、JS 側は既存の `highlightCode()` を再利用した `renderCodeHtml()` で全画面コード表示する。新規ライブラリは追加しない（同梱 highlight.min.js は 36 言語対応済み）。

**Tech Stack:** Swift 6 / AppKit + SwiftUI、WKWebView、highlight.js 11.11.1（同梱済み）、Swift Testing、Jest

**Spec:** `docs/superpowers/specs/2026-07-05-code-syntax-highlighting-design.md`

## Global Constraints

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）
- テスト関数名は英語 camelCase（SwiftLint が非 ASCII 開始名を弾く）。日本語説明は `@Test("...")` の表示名で付ける
- 新規 JS/CSS ライブラリの追加禁止（同梱アセットのみ使用）
- コミットは Conventional Commits + 日本語
- **コミット粒度**: 本計画は 1 機能なので、Task 1 で `feat` コミットを作成し、Task 2 以降は `git commit --amend --no-edit` で統合する（未 push の同一機能のため）
- Swift テスト実行: `cd MmdviewApp && swift test`（要 Xcode.app）
- JS テスト実行: `cd MmdviewApp && npm test`
- 作業ディレクトリはすべて `MmdviewApp/` 配下

---

### Task 1: FileType に .code ケースと拡張子対応表を追加

**Files:**
- Modify: `MmdviewApp/mmdview/Viewer/FileType.swift`
- Test: `MmdviewApp/mmdviewTests/FileTypeTests.swift`

**Interfaces:**
- Produces: `FileType.code(language: String)` ケース、`FileType.codeExtensionLanguages: [String: String]`、`FileType.codeExtensions: [String]`、`FileType.allExtensions`（コード拡張子込み）、`fileType.jsValue == "code"`、`fileType.codeLanguage: String?`
- 後続タスクは `codeLanguage`（Task 3）と `codeExtensions`（Task 5）に依存する

- [ ] **Step 1: 失敗するテストを書く**

`MmdviewApp/mmdviewTests/FileTypeTests.swift` を以下の内容に置き換える（既存テストの `unknownExtensionsFallbackToMarkdown` から `"json"` を外し、コード用テストを追加）:

```swift
import Foundation
@testable import mmdview
import Testing

@Suite
struct FileTypeTests {
    /// 既知の拡張子が正しいファイル種別にマッピングされること（大文字小文字を含む）
    @Test(arguments: [
        ("mmd", FileType.mmd),
        ("mermaid", FileType.mmd),
        ("MMD", FileType.mmd),
        ("Mermaid", FileType.mmd),
        ("md", FileType.markdown),
        ("markdown", FileType.markdown),
        ("MD", FileType.markdown),
        ("MARKDOWN", FileType.markdown),
    ])
    func knownExtensions(ext: String, expected: FileType) {
        let url = URL(fileURLWithPath: "/a/b.\(ext)")
        #expect(FileType(url: url) == expected)
    }

    /// コード拡張子が .code(language:) にマッピングされること（代表例＋大文字）
    @Test(arguments: [
        ("swift", "swift"),
        ("py", "python"),
        ("go", "go"),
        ("rs", "rust"),
        ("mjs", "javascript"),
        ("tsx", "typescript"),
        ("kt", "kotlin"),
        ("hpp", "cpp"),
        ("zsh", "bash"),
        ("toml", "ini"),
        ("json", "json"),
        ("jsonc", "json"),
        ("yml", "yaml"),
        ("plist", "xml"),
        ("PY", "python"),
        ("Swift", "swift"),
    ])
    func codeExtensionsMapToLanguage(ext: String, language: String) {
        let url = URL(fileURLWithPath: "/a/b.\(ext)")
        #expect(FileType(url: url) == .code(language: language))
    }

    /// 未知の拡張子は markdown にフォールバックすること
    @Test(arguments: ["txt", "html", ""])
    func unknownExtensionsFallbackToMarkdown(ext: String) {
        let path = ext.isEmpty ? "/a/b" : "/a/b.\(ext)"
        let url = URL(fileURLWithPath: path)
        #expect(FileType(url: url) == .markdown)
    }

    /// jsValue が JavaScript 側の期待する文字列を返すこと
    @Test(arguments: [
        (FileType.mmd, "mmd"),
        (FileType.markdown, "md"),
        (FileType.code(language: "swift"), "code"),
    ])
    func jsValueMapping(fileType: FileType, expected: String) {
        #expect(fileType.jsValue == expected)
    }

    /// codeLanguage は .code のときだけ言語名を返すこと
    @Test
    func codeLanguageOnlyForCode() {
        #expect(FileType.code(language: "python").codeLanguage == "python")
        #expect(FileType.mmd.codeLanguage == nil)
        #expect(FileType.markdown.codeLanguage == nil)
    }

    /// 全拡張子リストに重複がないこと（対応表と mermaid/markdown の衝突検知）
    @Test
    func allExtensionsHasNoDuplicates() {
        let all = FileType.allExtensions
        #expect(Set(all).count == all.count)
    }

    /// 対応表のキーがすべて小文字であること（判定は lowercased() で行うため）
    @Test
    func codeExtensionKeysAreLowercase() {
        for key in FileType.codeExtensionLanguages.keys {
            #expect(key == key.lowercased())
        }
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter FileTypeTests 2>&1 | tail -20`
Expected: コンパイルエラー（`code` ケース・`codeExtensionLanguages` が未定義）

- [ ] **Step 3: FileType.swift を実装する**

`MmdviewApp/mmdview/Viewer/FileType.swift` を以下の内容に置き換える:

```swift
import Foundation

/// ビューアが対応するファイル種別。拡張子から判定する。
/// 対応拡張子の一覧はここが単一情報源(オープンパネルの許可種別もここから解決する)。
enum FileType: Sendable, Equatable {
    case mmd
    case markdown
    case code(language: String)

    /// mermaid ダイアグラムとして扱う拡張子。
    static let mermaidExtensions = ["mmd", "mermaid"]
    /// markdown として扱う拡張子。
    static let markdownExtensions = ["md", "markdown"]
    /// コードとして扱う拡張子 → highlight.js の言語名。
    /// 同梱 highlight.min.js が対応する言語のみを載せる
    /// (整合性は viewer.test.js が同梱ビルドの言語リストと突き合わせて検証する)。
    static let codeExtensionLanguages: [String: String] = [
        "swift": "swift", "py": "python", "go": "go", "rs": "rust",
        "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascript",
        "ts": "typescript", "tsx": "typescript",
        "java": "java", "kt": "kotlin", "kts": "kotlin",
        "c": "c", "h": "c",
        "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp",
        "cs": "csharp", "m": "objectivec", "mm": "objectivec",
        "rb": "ruby", "php": "php", "pl": "perl", "pm": "perl",
        "lua": "lua", "r": "r", "sql": "sql",
        "sh": "bash", "bash": "bash", "zsh": "bash",
        "graphql": "graphql", "gql": "graphql",
        "css": "css", "scss": "scss", "less": "less",
        "ini": "ini", "toml": "ini",
        "diff": "diff", "patch": "diff",
        "mk": "makefile",
        "json": "json", "jsonc": "json",
        "yaml": "yaml", "yml": "yaml",
        "xml": "xml", "plist": "xml", "svg": "xml",
        "vb": "vbnet",
    ]
    /// コードとして扱う拡張子。
    static let codeExtensions = [String](codeExtensionLanguages.keys)
    /// アプリが対応する全拡張子。
    static let allExtensions = mermaidExtensions + markdownExtensions + codeExtensions

    init(url: URL) {
        let ext = url.pathExtension.lowercased()
        if Self.mermaidExtensions.contains(ext) {
            self = .mmd
        } else if let language = Self.codeExtensionLanguages[ext] {
            self = .code(language: language)
        } else {
            self = .markdown
        }
    }

    var jsValue: String {
        switch self {
        case .mmd: "mmd"
        case .markdown: "md"
        case .code: "code"
        }
    }

    /// .code の highlight.js 言語名。他の種別は nil。
    var codeLanguage: String? {
        if case .code(let language) = self { return language }
        return nil
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter FileTypeTests 2>&1 | tail -5`
Expected: PASS（全テスト green）

Run: `cd MmdviewApp && swift test 2>&1 | tail -5`
Expected: PASS（既存テストにも回帰がないこと。ViewerStore 等は FileType を enum 比較で使うが、Equatable 準拠を維持しているため影響なし）

- [ ] **Step 5: コミット（この機能の起点コミットを作る）**

```bash
git add MmdviewApp/mmdview/Viewer/FileType.swift MmdviewApp/mmdviewTests/FileTypeTests.swift
git commit -m "feat: コードファイルのシンタックスハイライト表示に対応する"
```

---

### Task 2: viewer.js に renderCodeHtml を追加

**Files:**
- Modify: `MmdviewApp/mmdview/Resources/viewer.js`
- Test: `MmdviewApp/mmdview/Resources/__tests__/viewer.test.js`

**Interfaces:**
- Consumes: 既存の `highlightCode(hljs, str, lang)`（viewer.js:72）
- Produces: `escapeHtml(text)` と `renderCodeHtml(hljs, str, lang)`（Task 4 の viewer.html が呼ぶ。戻り値は HTML 文字列、失敗時もエスケープ済みプレーン `<pre><code>` を返す）

- [ ] **Step 1: 失敗するテストを書く**

`MmdviewApp/mmdview/Resources/__tests__/viewer.test.js` の `require('../viewer')` の分割代入に `escapeHtml` と `renderCodeHtml` を追加し、ファイル末尾に以下の describe ブロックを追加する:

```js
describe('escapeHtml', () => {
  test('escapes HTML special characters', () => {
    expect(escapeHtml('<b a="c">&</b>')).toBe('&lt;b a=&quot;c&quot;&gt;&amp;&lt;/b&gt;');
  });

  test('passes plain text through', () => {
    expect(escapeHtml('let x = 1')).toBe('let x = 1');
  });

  test('stringifies non-string input', () => {
    expect(escapeHtml(null)).toBe('null');
  });
});

describe('renderCodeHtml', () => {
  const hljs = require('highlight.js');

  test('known language produces full-page hljs markup', () => {
    const result = renderCodeHtml(hljs, 'let x = 1', 'swift');
    expect(result.startsWith('<pre><code class="hljs language-swift">')).toBe(true);
    expect(result).toContain('hljs-keyword');
    expect(result.endsWith('</code></pre>')).toBe(true);
  });

  test('unsupported language falls back to escaped plain block', () => {
    const result = renderCodeHtml(hljs, '<b>raw</b>', 'no-such-lang-xyz');
    expect(result).toBe('<pre><code>&lt;b&gt;raw&lt;/b&gt;</code></pre>');
  });

  test('missing hljs falls back to escaped plain block', () => {
    const result = renderCodeHtml(null, 'const x = 1;', 'javascript');
    expect(result).toBe('<pre><code>const x = 1;</code></pre>');
  });

  test('escapes HTML in fallback path (XSS)', () => {
    const result = renderCodeHtml(null, '<script>alert(1)</script>', 'javascript');
    expect(result).not.toContain('<script>');
    expect(result).toContain('&lt;script&gt;');
  });
});

describe('FileType.swift の言語名契約', () => {
  // FileType.codeExtensionLanguages(FileType.swift)の値と同期させること。
  // npm の highlight.js ではなく同梱の highlight.min.js に対して検証する
  // (同梱ビルドは言語のサブセットのため、npm 版では偽陽性になる)。
  const bundledHljs = require('../highlight.min.js');
  const LANGUAGES = [
    'swift', 'python', 'go', 'rust', 'javascript', 'typescript',
    'java', 'kotlin', 'c', 'cpp', 'csharp', 'objectivec',
    'ruby', 'php', 'perl', 'lua', 'r', 'sql', 'bash',
    'graphql', 'css', 'scss', 'less', 'ini', 'diff', 'makefile',
    'json', 'yaml', 'xml', 'vbnet',
  ];

  test.each(LANGUAGES)('%s is available in the bundled highlight.min.js', (lang) => {
    expect(bundledHljs.getLanguage(lang)).toBeTruthy();
  });
});
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && npm test 2>&1 | tail -15`
Expected: FAIL — `escapeHtml is not a function` / `renderCodeHtml is not a function`

- [ ] **Step 3: viewer.js に実装を追加する**

`MmdviewApp/mmdview/Resources/viewer.js` の `highlightCode` 関数定義の直後（`if (typeof module ...)` の前）に追加:

```js
// HTML 特殊文字をエスケープする(DOM 非依存の純粋関数)。
// viewer.html の _escapeHtml は DOM を使うため Node テストできない。
function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// 単一コードファイル全文のハイライト HTML を組み立てる。
// highlightCode() を再利用し、未対応言語・hljs 不在・例外時は
// エスケープ済みプレーン <pre><code> にフォールバックする。
function renderCodeHtml(hljs, str, lang) {
  var highlighted = highlightCode(hljs, str, lang);
  if (highlighted) { return highlighted; }
  return '<pre><code>' + escapeHtml(str) + '</code></pre>';
}
```

`module.exports` に 2 行追加:

```js
    escapeHtml: escapeHtml,
    renderCodeHtml: renderCodeHtml,
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && npm test 2>&1 | tail -5`
Expected: PASS（全 suite green）

- [ ] **Step 5: コミット（同一機能なので amend）**

```bash
git add MmdviewApp/mmdview/Resources/viewer.js MmdviewApp/mmdview/Resources/__tests__/viewer.test.js
git commit --amend --no-edit
```

---

### Task 3: ViewerBridge.renderScript に言語引数を追加

**Files:**
- Modify: `MmdviewApp/mmdview/Viewer/ViewerBridge.swift:26-33`
- Test: `MmdviewApp/mmdviewTests/ViewerBridgeTests.swift`

**Interfaces:**
- Consumes: `FileType.codeLanguage: String?`（Task 1）
- Produces: `.code` のとき `render(<json>, 'code', '<lang>')`、それ以外は従来の 2 引数呼び出し（Task 4 の viewer.html がこの契約を実装する）

- [ ] **Step 1: 失敗するテストを書く**

`MmdviewApp/mmdviewTests/ViewerBridgeTests.swift` の `renderScriptUsesFileTypeJSValue` の直後にテストを追加:

```swift
    @Test("code タイプは第 3 引数に言語名を渡す")
    func renderScriptAppendsLanguageForCode() throws {
        let script = try #require(
            ViewerBridge.renderScript(content: "let x = 1", fileType: .code(language: "swift"))
        )

        #expect(script.hasSuffix("\", 'code', 'swift')"))
    }

    @Test("mmd / md は従来どおり 2 引数のまま（言語引数を付けない）")
    func renderScriptOmitsLanguageForNonCode() throws {
        let mmd = try #require(ViewerBridge.renderScript(content: "graph TD", fileType: .mmd))
        let md = try #require(ViewerBridge.renderScript(content: "# Hi", fileType: .markdown))

        #expect(mmd.hasSuffix("', 'mmd')"))
        #expect(md.hasSuffix("', 'md')"))
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter ViewerBridgeTests 2>&1 | tail -10`
Expected: FAIL — `renderScriptAppendsLanguageForCode` が `', 'code')` で終わるため suffix 不一致

- [ ] **Step 3: renderScript を実装する**

`MmdviewApp/mmdview/Viewer/ViewerBridge.swift` の `renderScript` を以下に置き換える:

```swift
    /// render(content, type[, lang]) 呼び出しを組み立てる。
    /// content は JSONEncoder でエスケープし、JS インジェクションを防ぐ。
    /// .code の場合のみ第 3 引数で highlight.js の言語名を渡す
    /// (言語名は FileType の対応表由来の固定文字列のみで、ユーザー入力は混入しない)。
    /// エンコードに失敗した場合は nil(呼び出し側は何もしない)。
    static func renderScript(content: String, fileType: FileType) -> String? {
        guard let jsonData = try? JSONEncoder().encode(content),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }
        if let language = fileType.codeLanguage {
            return "render(\(jsonString), '\(fileType.jsValue)', '\(language)')"
        }
        return "render(\(jsonString), '\(fileType.jsValue)')"
    }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter ViewerBridgeTests 2>&1 | tail -5`
Expected: PASS（`bridgeFunctionsExistInViewerHTML` は viewer.html がまだ 2 引数シグネチャのため PASS のまま。シグネチャ変更と期待値更新は Task 4 で同時に行う）

- [ ] **Step 5: コミット（amend）**

```bash
git add MmdviewApp/mmdview/Viewer/ViewerBridge.swift MmdviewApp/mmdviewTests/ViewerBridgeTests.swift
git commit --amend --no-edit
```

---

### Task 4: viewer.html に code 分岐、style.css に .code-body を追加

**Files:**
- Modify: `MmdviewApp/mmdview/Resources/viewer.html`（render 関数まわり: 289-295 行付近と分岐、239 行の再描画呼び出し）
- Modify: `MmdviewApp/mmdview/Resources/style.css`（`.markdown-body` セクションの後）
- Test: `MmdviewApp/mmdviewTests/ViewerBridgeTests.swift:43`（契約テストの期待値更新）

**Interfaces:**
- Consumes: `renderCodeHtml(hljs, str, lang)`（Task 2）、`render(<json>, 'code', '<lang>')` 契約（Task 3）
- Produces: `async function render(content, type, lang)` シグネチャ、`#diagram-wrap.code-body` スタイル

- [ ] **Step 1: 契約テストの期待値を先に更新する（失敗するテスト）**

`MmdviewApp/mmdviewTests/ViewerBridgeTests.swift` の `bridgeFunctionsExistInViewerHTML` 内:

```swift
        // 変更前
        #expect(html.contains("async function render(content, type)"))
        // 変更後
        #expect(html.contains("async function render(content, type, lang)"))
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter ViewerBridgeTests 2>&1 | tail -10`
Expected: FAIL — viewer.html はまだ 2 引数シグネチャのため

- [ ] **Step 3: viewer.html を実装する**

3-a. 状態変数（289-290 行付近）に `_lastLang` を追加:

```js
  // カラースキーム変更時に再描画するため、直近の内容を保持する。
  var _lastContent = null;
  var _lastType = null;
  var _lastLang = null;
```

3-b. `render` のシグネチャと状態保存（292-295 行付近）:

```js
  async function render(content, type, lang) {
    _currentType = type;
    _lastContent = content;
    _lastType = type;
    _lastLang = lang;
```

3-c. カラースキーム再描画（239 行付近）:

```js
      // 変更前
      render(_lastContent, _lastType);
      // 変更後
      render(_lastContent, _lastType, _lastLang);
```

3-d. `render` 内の分岐に `code` を追加（`if (type === 'mmd')` のブロック）:

```js
    if (type === 'mmd') {
      diagramWrap.classList.remove('markdown-body');
      diagramWrap.classList.remove('code-body');
      diagramWrap.innerHTML = '<pre class="mermaid">' + _escapeHtml(content) + '</pre>';
    } else if (type === 'code') {
      // 単一コードファイル。hljs のトークン色は github.css / github-dark.css、
      // レイアウトは style.css の .code-body が担う。
      diagramWrap.classList.remove('markdown-body');
      diagramWrap.classList.add('code-body');
      diagramWrap.innerHTML = renderCodeHtml(window.hljs, content, lang);
    } else {
      // github-markdown-css は .markdown-body プレフィックス前提のため
      // Markdown レンダリング時のみ付与する
      diagramWrap.classList.remove('code-body');
      diagramWrap.classList.add('markdown-body');
      if (md) {
        diagramWrap.innerHTML = md.render(content);
      } else {
        diagramWrap.innerHTML = '<p>markdown-it not loaded</p>';
        return;
      }
    }
```

- [ ] **Step 4: style.css に .code-body スタイルを追加する**

`MmdviewApp/mmdview/Resources/style.css` の `#diagram-wrap.markdown-body code.hljs { ... }` ブロックの直後に追加:

```css
/*
  単一コードファイル表示(.code-body)。トークン色と背景は
  github.css / github-dark.css(.hljs)が担い、ここではレイアウトのみ整える。
  フォントサイズは Markdown のコードブロック(本文 × 0.75em)と揃える。
*/
#diagram-wrap.code-body {
  width: 100%;
  max-width: 980px;
}

#diagram-wrap.code-body pre {
  margin: 0;
}

#diagram-wrap.code-body pre code {
  display: block;
  padding: 16px;
  border-radius: 6px;
  overflow-x: auto;
  font-size: calc(var(--mmd-markdown-font-size, 16px) * 0.75);
  line-height: 1.45;
}

/* ハイライト失敗時のフォールバック(<pre><code> に .hljs が付かない)にも
   最低限の背景を与える */
#diagram-wrap.code-body pre code:not(.hljs) {
  background: rgba(128, 128, 128, 0.08);
}
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter ViewerBridgeTests 2>&1 | tail -5`
Expected: PASS

Run: `cd MmdviewApp && npm test 2>&1 | tail -5`
Expected: PASS（JS 側の回帰なし）

- [ ] **Step 6: コミット（amend）**

```bash
git add MmdviewApp/mmdview/Resources/viewer.html MmdviewApp/mmdview/Resources/style.css MmdviewApp/mmdviewTests/ViewerBridgeTests.swift
git commit --amend --no-edit
```

---

### Task 5: オープンパネル UTI と Info.plist の Finder 登録

**Files:**
- Modify: `MmdviewApp/mmdview/App/AppDelegate.swift:151-167`（supportedContentTypes）
- Modify: `MmdviewApp/mmdview/Info.plist`（UTImportedTypeDeclarations / CFBundleDocumentTypes）
- Test: `MmdviewApp/mmdviewTests/InfoPlistTests.swift`

**Interfaces:**
- Consumes: `FileType.codeExtensions`（Task 1。オープンパネルは `FileType.allExtensions` 経由で自動反映される）
- Produces: UTI `com.degino.mmdview.source-code`（Info.plist で宣言・claim）

- [ ] **Step 1: 失敗するテストを書く**

`MmdviewApp/mmdviewTests/InfoPlistTests.swift` の末尾（`claimsMermaidDiagramTypeAsOwner` の後）にテストを追加:

```swift
    /// コード全拡張子が mmdview 自身の source-code UTI 宣言に含まれていること。
    /// FileType.codeExtensionLanguages と Info.plist のドリフトを検知する。
    @Test
    func importsSourceCodeTypeCoveringAllCodeExtensions() throws {
        let source = try #require(
            importedTypes.first {
                ($0["UTTypeIdentifier"] as? String) == "com.degino.mmdview.source-code"
            }
        )
        let tags = try #require(source["UTTypeTagSpecification"] as? [String: Any])
        let extensions = try #require(tags["public.filename-extension"] as? [String])
        for ext in FileType.codeExtensions {
            #expect(extensions.contains(ext), "\(ext) が Info.plist に宣言されていない")
        }
        let conforms = try #require(source["UTTypeConformsTo"] as? [String])
        #expect(conforms.contains("public.source-code"))
    }

    /// Source Code のドキュメントタイプが自前 UTI と実勢システム UTI を claim していること。
    @Test
    func claimsSourceCodeContentTypes() {
        let claimed = claimedContentTypes()
        #expect(claimed.contains("com.degino.mmdview.source-code"))
        #expect(claimed.contains("public.source-code"))
        #expect(claimed.contains("public.swift-source"))
        #expect(claimed.contains("public.json"))
        #expect(claimed.contains("public.yaml"))
        #expect(claimed.contains("public.xml"))
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter InfoPlistTests 2>&1 | tail -10`
Expected: FAIL — source-code UTI が未宣言のため `#require` が失敗

- [ ] **Step 3: Info.plist を実装する**

3-a. `UTImportedTypeDeclarations` 配列（既存の net.daringfireball.markdown の dict の後）に追加。
拡張子は Task 1 の `codeExtensionLanguages` のキー全 45 個を列挙する:

```xml
		<dict>
			<key>UTTypeIdentifier</key>
			<string>com.degino.mmdview.source-code</string>
			<key>UTTypeDescription</key>
			<string>Source Code</string>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.source-code</string>
			</array>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<array>
					<string>swift</string>
					<string>py</string>
					<string>go</string>
					<string>rs</string>
					<string>js</string>
					<string>mjs</string>
					<string>cjs</string>
					<string>jsx</string>
					<string>ts</string>
					<string>tsx</string>
					<string>java</string>
					<string>kt</string>
					<string>kts</string>
					<string>c</string>
					<string>h</string>
					<string>cpp</string>
					<string>cc</string>
					<string>cxx</string>
					<string>hpp</string>
					<string>cs</string>
					<string>m</string>
					<string>mm</string>
					<string>rb</string>
					<string>php</string>
					<string>pl</string>
					<string>pm</string>
					<string>lua</string>
					<string>r</string>
					<string>sql</string>
					<string>sh</string>
					<string>bash</string>
					<string>zsh</string>
					<string>graphql</string>
					<string>gql</string>
					<string>css</string>
					<string>scss</string>
					<string>less</string>
					<string>ini</string>
					<string>toml</string>
					<string>diff</string>
					<string>patch</string>
					<string>mk</string>
					<string>json</string>
					<string>jsonc</string>
					<string>yaml</string>
					<string>yml</string>
					<string>xml</string>
					<string>plist</string>
					<string>svg</string>
					<string>vb</string>
				</array>
			</dict>
		</dict>
```

3-b. `CFBundleDocumentTypes` 配列（既存の Markdown の dict の後）に追加。
拡張子が既にシステム UTI にバインドされている環境でも「このアプリで開く」に
載るよう、自前 UTI と主要なシステム UTI の両方を claim する（.md と同じ方針）:

```xml
		<dict>
			<key>CFBundleTypeName</key>
			<string>Source Code</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>com.degino.mmdview.source-code</string>
				<string>public.source-code</string>
				<string>public.swift-source</string>
				<string>public.python-script</string>
				<string>public.shell-script</string>
				<string>public.ruby-script</string>
				<string>public.perl-script</string>
				<string>public.php-script</string>
				<string>public.c-source</string>
				<string>public.c-plus-plus-source</string>
				<string>public.c-header</string>
				<string>public.objective-c-source</string>
				<string>com.sun.java-source</string>
				<string>com.netscape.javascript-source</string>
				<string>public.json</string>
				<string>public.yaml</string>
				<string>public.xml</string>
				<string>public.css</string>
			</array>
		</dict>
```

- [ ] **Step 4: AppDelegate の supportedContentTypes に安定 UTI を追記する**

`MmdviewApp/mmdview/App/AppDelegate.swift` の `identifiers` 配列を以下に置き換える（コメントは既存のまま）:

```swift
        let identifiers = [
            "com.degino.mmdview.mermaid-diagram",
            "net.daringfireball.markdown",
            "net.ia.markdown",
            "com.unknown.md",
            "com.degino.mmdview.source-code",
            "public.source-code",
            "public.json",
            "public.yaml",
            "public.xml",
        ]
```

（拡張子由来の UTType は `FileType.allExtensions` から既に解決されるため、
ここは実勢バインドのぶれ対策の追記のみ）

- [ ] **Step 5: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter InfoPlistTests 2>&1 | tail -5`
Expected: PASS

Run: `cd MmdviewApp && swift test 2>&1 | tail -5`
Expected: PASS（全体回帰なし）

- [ ] **Step 6: コミット（amend）**

```bash
git add MmdviewApp/mmdview/Info.plist MmdviewApp/mmdview/App/AppDelegate.swift MmdviewApp/mmdviewTests/InfoPlistTests.swift
git commit --amend --no-edit
```

---

### Task 6: 全体検証と手動スモークチェック

**Files:**
- なし（検証のみ）

**Interfaces:**
- Consumes: Task 1-5 のすべて

- [ ] **Step 1: 全テストを実行する**

Run: `cd MmdviewApp && swift test 2>&1 | tail -5`
Expected: PASS

Run: `cd MmdviewApp && npm test 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 2: サンプルコードファイルを用意する**

```bash
mkdir -p /tmp/mmdview-smoke
cat > /tmp/mmdview-smoke/sample.swift <<'EOF'
import Foundation

/// サンプル
struct Point: Sendable {
    let x: Double
    let y: Double
}
let p = Point(x: 1.0, y: 2.0)
print("point: \(p)")
EOF
cat > /tmp/mmdview-smoke/sample.json <<'EOF'
{ "name": "mmdview", "version": 1, "tags": ["viewer", "mermaid"] }
EOF
cat > /tmp/mmdview-smoke/sample.yaml <<'EOF'
name: mmdview
targets:
  - name: app
    platform: macOS
EOF
```

- [ ] **Step 3: ビルドして起動し、手動確認する**

Run: `/run` スキル（またはユーザーに手動確認を依頼）で以下を確認:

1. `sample.swift` を開く → キーワード・文字列・コメントが色付きで全画面表示される
2. `sample.json` / `sample.yaml` を開く → 構造が色付き表示される
3. ライト/ダークモード切替 → 背景・トークン色が追従する（カラースキーム再描画）
4. ファイルを編集して保存 → 0.2s デバウンス後に自動再描画される
5. Cmd+Plus/Minus でズーム → コード表示にも全体ズームが効く
6. `.md` / `.mmd` ファイル → 従来どおり表示される（回帰なし）
7. Finder でコードファイルを右クリック →「このアプリで開く」に mmdview が出る
   （初回はビルド済み .app を一度起動して LaunchServices に登録された後）

- [ ] **Step 4: 最終確認とプッシュ準備**

手動確認で問題があれば修正して amend。問題なければ完了報告
（push / PR 作成はユーザーの指示を待つ）。

---

## Self-Review 記録

- **Spec coverage**: FileType 拡張=Task 1、ブリッジ契約=Task 3、renderCodeHtml=Task 2、viewer.html/style.css=Task 4、Finder 登録=Task 5、手動確認=Task 6。スペックの全セクションに対応タスクあり。
- **Type consistency**: `codeLanguage`（Task 1 定義 → Task 3 使用）、`renderCodeHtml(hljs, str, lang)`（Task 2 定義 → Task 4 使用）、`render(content, type, lang)`（Task 3 生成 → Task 4 実装）で一致。
- **言語名ドリフト対策**: Task 2 の契約テストが同梱 highlight.min.js の言語リストと突き合わせる。Task 5 のテストが Info.plist と FileType.codeExtensions を突き合わせる。
