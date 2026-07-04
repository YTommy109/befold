# Markdown コードブロックのシンタックスハイライト 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

<!-- derived-from ../specs/2026-07-04-syntax-highlight-design.md -->

**Goal:** Markdown 内の言語指定付きコードブロックを highlight.js でシンタックスハイライトする。

**Architecture:** highlight.js v11.11.1 の common ビルドと GitHub テーマ CSS 2 種を Resources に無改変で同梱し、markdown-it の `highlight` オプション(公式拡張点)から `viewer.js` の純粋関数 `highlightCode()` を呼ぶ。ライト/ダークは `<link media="(prefers-color-scheme: ...)">` で切替。既存の mermaid フェンス特別扱いとは干渉しない。

**Tech Stack:** highlight.js 11.11.1(BSD-3-Clause)/ markdown-it(同梱済み)/ Jest(JS ユニットテスト)/ Swift Package Manager

## Global Constraints

- 同梱する highlight.js のバージョンは **11.11.1** に固定し、`MmdviewApp/package.json` の devDependency と一致させる。
- 上流配布物(`highlight.min.js` / `github.css` / `github-dark.css`)は**無改変**で置く。
- CSP(`viewer.html:13`)は変更しない(`script-src 'self'` / `style-src 'self' 'unsafe-inline'` / `connect-src 'none'` のままで動作する)。
- 言語未指定・未対応言語のフェンスはハイライトしない(highlightAuto は使わない)。
- Swift コードは無変更。`project.yml` も変更不要(Resources フォルダ一括コピーのため)。
- コミットは Conventional Commits + 日本語(プロジェクト規約)。
- 作業ディレクトリ: リポジトリルート。`npm` / `jest` コマンドは `MmdviewApp/` で実行する。

---

### Task 1: アセット同梱とビルド定義

**Files:**
- Create: `MmdviewApp/mmdview/Resources/highlight.min.js`
- Create: `MmdviewApp/mmdview/Resources/github.css`
- Create: `MmdviewApp/mmdview/Resources/github-dark.css`
- Modify: `MmdviewApp/Package.swift:16-23`(resources 配列)
- Modify: `MmdviewApp/package.json`(devDependencies)

**Interfaces:**
- Consumes: なし
- Produces: グローバル `hljs`(highlight.min.js が IIFE で登録。Task 3 が viewer.html から読み込む)/ Jest から `require('highlight.js')` できる devDependency(Task 2 のテストが使用)

- [ ] **Step 1: 上流配布物を 3 ファイルダウンロードする**

```bash
cd MmdviewApp/mmdview/Resources
curl -fsSL -o highlight.min.js "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.11.1/build/highlight.min.js"
curl -fsSL -o github.css "https://cdn.jsdelivr.net/npm/highlight.js@11.11.1/styles/github.css"
curl -fsSL -o github-dark.css "https://cdn.jsdelivr.net/npm/highlight.js@11.11.1/styles/github-dark.css"
```

- [ ] **Step 2: バージョンとファイル内容を検証する**

```bash
grep -o 'version:"[0-9.]*"' MmdviewApp/mmdview/Resources/highlight.min.js | head -1
```

Expected: `version:"11.11.1"`

```bash
head -c 200 MmdviewApp/mmdview/Resources/github.css
ls -la MmdviewApp/mmdview/Resources/
```

Expected: github.css の先頭に `Theme: GitHub` を含むコメントバナー。highlight.min.js は約 120KB、CSS は各 1〜2KB。

- [ ] **Step 3: Package.swift の resources に 3 ファイルを追加する**

`MmdviewApp/Package.swift` の `resources:` 配列を以下にする(既存 6 行 + 新規 3 行):

```swift
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/viewer.html"),
                .copy("Resources/viewer.js"),
                .copy("Resources/style.css"),
                .copy("Resources/mermaid.min.js"),
                .copy("Resources/markdown-it.min.js"),
                .copy("Resources/highlight.min.js"),
                .copy("Resources/github.css"),
                .copy("Resources/github-dark.css"),
            ],
```

- [ ] **Step 4: package.json に devDependency を追加してインストールする**

`MmdviewApp/package.json` の devDependencies を以下にする(アルファベット順):

```json
  "devDependencies": {
    "highlight.js": "11.11.1",
    "jest": "^29.7.0",
    "markdown-it": "14.2.0"
  }
```

```bash
cd MmdviewApp && npm install
```

Expected: エラーなし。`package-lock.json` が更新される。

- [ ] **Step 5: ビルドが通ることを確認する**

```bash
cd MmdviewApp && swift build
```

Expected: `Build complete!`(リソース追加による破壊がないことの確認)

- [ ] **Step 6: コミット**

```bash
git add MmdviewApp/mmdview/Resources/highlight.min.js \
        MmdviewApp/mmdview/Resources/github.css \
        MmdviewApp/mmdview/Resources/github-dark.css \
        MmdviewApp/Package.swift MmdviewApp/package.json MmdviewApp/package-lock.json
git commit -m "chore: highlight.js v11.11.1 と GitHub テーマ CSS を同梱する"
```

---

### Task 2: highlightCode 純粋関数(viewer.js)

**Files:**
- Modify: `MmdviewApp/mmdview/Resources/viewer.js`(関数追加 + module.exports 追加)
- Test: `MmdviewApp/mmdview/Resources/__tests__/viewer.test.js`(describe 追加)

**Interfaces:**
- Consumes: Task 1 の devDependency `highlight.js`(テストで `require('highlight.js')`)
- Produces: `highlightCode(hljs, str, lang) -> string`(成功時 `<pre><code class="hljs language-xxx">…</code></pre>`、フォールバック時 `''`)/ `sanitizeLang(lang) -> string`。Task 3 が viewer.html から `highlightCode` を呼ぶ。

- [ ] **Step 1: 失敗するテストを書く**

`__tests__/viewer.test.js` の `require('../viewer')` の分割代入に `sanitizeLang, highlightCode` を追加し、ファイル末尾に以下を追加:

```js
describe('sanitizeLang', () => {
  test('passes through normal language names', () => {
    expect(sanitizeLang('javascript')).toBe('javascript');
    expect(sanitizeLang('c++')).toBe('c++');
    expect(sanitizeLang('objective-c')).toBe('objective-c');
  });

  test('strips characters not allowed in a class attribute', () => {
    expect(sanitizeLang('js" onload="x')).toBe('jsonloadx');
    expect(sanitizeLang('a<b>')).toBe('ab');
  });

  test('stringifies non-string input', () => {
    expect(sanitizeLang(null)).toBe('null');
  });
});

describe('highlightCode', () => {
  const hljs = require('highlight.js');

  test('wraps known-language code in pre/code with hljs classes', () => {
    const result = highlightCode(hljs, 'const x = 1;', 'javascript');
    expect(result.startsWith('<pre><code class="hljs language-javascript">')).toBe(true);
    expect(result.endsWith('</code></pre>')).toBe(true);
    expect(result).toContain('<span class="hljs-');
  });

  test('highlights swift keywords', () => {
    const result = highlightCode(hljs, 'let x = 1', 'swift');
    expect(result).toContain('hljs-keyword');
  });

  test('returns empty string for unsupported language', () => {
    expect(highlightCode(hljs, 'foo', 'no-such-lang-xyz')).toBe('');
  });

  test('returns empty string when language is missing', () => {
    expect(highlightCode(hljs, 'foo', '')).toBe('');
    expect(highlightCode(hljs, 'foo', undefined)).toBe('');
  });

  test('returns empty string when hljs is unavailable', () => {
    expect(highlightCode(null, 'const x = 1;', 'javascript')).toBe('');
  });

  test('escapes HTML inside code content', () => {
    const result = highlightCode(hljs, 'var s = "<script>alert(1)</script>";', 'javascript');
    expect(result).not.toContain('<script>');
    expect(result).toContain('&lt;script&gt;');
  });
});
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
cd MmdviewApp && npx jest __tests__/viewer.test.js 2>&1 | tail -20
```

Expected: FAIL(`sanitizeLang is not a function` 等)

- [ ] **Step 3: viewer.js に実装を追加する**

`mermaidTheme` 関数の直後に追加:

```js
// class 属性に埋め込める文字(英数字・_・+・-)だけを残す。
// hljs.getLanguage() を通過した言語名しか来ないはずだが、防御的に二重チェックする。
function sanitizeLang(lang) {
  return String(lang).replace(/[^\w+-]/g, '');
}

// Markdown コードブロックのシンタックスハイライト。
// markdown-it の highlight オプションから呼ばれる。hljs は依存注入
// (viewer.html ではグローバル hljs、テストでは npm の highlight.js)。
// 返り値が '<pre' で始まる場合 markdown-it はそれをそのまま採用し、
// '' の場合はデフォルトのエスケープ済み <pre><code> にフォールバックする。
function highlightCode(hljs, str, lang) {
  if (hljs && lang && hljs.getLanguage(lang)) {
    try {
      var result = hljs.highlight(str, { language: lang, ignoreIllegals: true });
      return '<pre><code class="hljs language-' + sanitizeLang(lang) + '">'
        + result.value + '</code></pre>';
    } catch (e) {
      // フォールバックへ
    }
  }
  return '';
}
```

`module.exports` に 2 行追加:

```js
    sanitizeLang: sanitizeLang,
    highlightCode: highlightCode,
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
cd MmdviewApp && npx jest __tests__/viewer.test.js 2>&1 | tail -10
```

Expected: PASS(既存テスト含め全緑)

- [ ] **Step 5: コミット**

```bash
git add MmdviewApp/mmdview/Resources/viewer.js \
        MmdviewApp/mmdview/Resources/__tests__/viewer.test.js
git commit -m "feat: コードブロックをハイライトする highlightCode を追加する"
```

---

### Task 3: viewer.html への配線と markdown-it 統合テスト

**Files:**
- Modify: `MmdviewApp/mmdview/Resources/viewer.html`(`<head>` の link、script 読み込み、markdownit 初期化)
- Test: `MmdviewApp/mmdview/Resources/__tests__/viewer.test.js`(describe 追加)

**Interfaces:**
- Consumes: Task 1 のアセット(`highlight.min.js` / `github.css` / `github-dark.css`)、Task 2 の `highlightCode(hljs, str, lang)`
- Produces: Markdown レンダリング時にハイライトされた HTML(ユーザー可視の最終挙動)

- [ ] **Step 1: markdown-it との統合テストを書く**

viewer.html の配線と同じ形を実物の markdown-it + highlight.js で検証する。`__tests__/viewer.test.js` 末尾に追加:

```js
describe('markdown-it integration with highlightCode', () => {
  const hljs = require('highlight.js');
  const markdownit = require('markdown-it');
  // viewer.html の markdownit 初期化と同じ配線
  const md = markdownit({
    html: true,
    linkify: true,
    typographer: true,
    highlight: function(str, lang) {
      return highlightCode(hljs, str, lang);
    },
  });

  test('fenced block with language gets hljs markup as-is', () => {
    const html = md.render('```javascript\nconst x = 1;\n```\n');
    expect(html).toContain('<pre><code class="hljs language-javascript">');
    expect(html).toContain('<span class="hljs-');
  });

  test('fenced block without language falls back to escaped plain block', () => {
    const html = md.render('```\n<b>raw</b>\n```\n');
    expect(html).toContain('&lt;b&gt;raw&lt;/b&gt;');
    expect(html).not.toContain('hljs');
  });

  test('fenced block with unsupported language falls back to escaped plain block', () => {
    const html = md.render('```no-such-lang-xyz\n<b>raw</b>\n```\n');
    expect(html).toContain('&lt;b&gt;raw&lt;/b&gt;');
    expect(html).not.toContain('<span class="hljs-');
  });
});
```

- [ ] **Step 2: テストが通ることを確認する**

このテストは Task 2 の成果物と markdown-it の仕様(`<pre` 始まりの返り値をそのまま採用)の検証なので、この時点で通る:

```bash
cd MmdviewApp && npx jest __tests__/viewer.test.js 2>&1 | tail -10
```

Expected: PASS

- [ ] **Step 3: viewer.html の `<head>` にテーマ CSS を追加する**

`<link rel="stylesheet" href="style.css">`(viewer.html:16)の直後に追加:

```html
  <link rel="stylesheet" href="github.css" media="(prefers-color-scheme: light)">
  <link rel="stylesheet" href="github-dark.css" media="(prefers-color-scheme: dark)">
```

- [ ] **Step 4: viewer.html に highlight.min.js の読み込みを追加する**

`<script src="markdown-it.min.js"></script>`(viewer.html:34)の直後に追加:

```html
  <script src="highlight.min.js"></script>
```

- [ ] **Step 5: markdownit 初期化に highlight オプションを追加する**

viewer.html:139 の

```js
    md = markdownit({ html: true, linkify: true, typographer: true });
```

を以下に置き換える(fence オーバーライドは無変更):

```js
    md = markdownit({
      html: true,
      linkify: true,
      typographer: true,
      // highlight.min.js の読み込み失敗時は hljs 未定義 → highlightCode が '' を
      // 返し、ハイライトなしの従来表示に縮退する。
      highlight: function(str, lang) {
        return highlightCode(typeof hljs !== 'undefined' ? hljs : null, str, lang);
      },
    });
```

- [ ] **Step 6: ビルドして全テストを実行する**

```bash
cd MmdviewApp && swift build && npx jest 2>&1 | tail -10
```

Expected: `Build complete!` + Jest 全緑

- [ ] **Step 7: コミット**

```bash
git add MmdviewApp/mmdview/Resources/viewer.html \
        MmdviewApp/mmdview/Resources/__tests__/viewer.test.js
git commit -m "feat: Markdown コードブロックにシンタックスハイライトを適用する"
```

---

### Task 4: サンプル追加と手動確認

**Files:**
- Modify: `sample/sample.md`(コードブロックのセクション追加)

**Interfaces:**
- Consumes: Task 3 までの全成果(アプリの最終挙動)
- Produces: リリース前手動チェック用のサンプル(プロジェクト規約: WebView/GUI 層は自動テスト対象外)

- [ ] **Step 1: sample.md にコードブロックのセクションを追加する**

`sample/sample.md` の末尾に追加:

````markdown

## コードブロック

言語指定付きはシンタックスハイライトされる:

```swift
import Foundation

@MainActor @Observable
final class ViewerStore {
    private(set) var content: String = ""

    func update(content: String) {
        self.content = content
    }
}
```

```javascript
function highlightCode(hljs, str, lang) {
  if (hljs && lang && hljs.getLanguage(lang)) {
    return hljs.highlight(str, { language: lang }).value;
  }
  return '';
}
```

言語指定なしはプレーン表示のまま:

```
plain text block
no highlighting here
```
````

- [ ] **Step 2: アプリを起動して目視確認する**

`swift build` は .app バンドルを生成しないため xcodebuild でビルドして起動する(`/run` スキルと同じ手順):

```bash
cd MmdviewApp && xcodegen generate && \
  xcodebuild build -scheme mmdview -configuration Debug -derivedDataPath .build/xcode -quiet
cd .. && open -a MmdviewApp/.build/xcode/Build/Products/Debug/mmdview.app sample/sample.md
```

確認項目(ライト/ダーク両方 — macOS の外観設定を切り替えて確認):
- Swift / JavaScript ブロックにトークン色が付く(キーワード・文字列・コメント)
- 言語なしブロックはモノクロのまま
- コードブロックの地色が既存どおり(ライト `#f4f4f4` / ダーク `#2d2d2d`)で、ハイライト有無で揃っている。テーマ CSS の `.hljs` 背景(白 / `#0d1117`)が透けていないこと
- 既存の mermaid フェンス(`sample.md` 冒頭)が従来どおり図として描画される
- 外観切替時にトークン色が追従する(既存の mermaid 再描画リスナーとは独立に、CSS の media 切替のみで変わる)

地色が崩れていた場合のみ、`style.css` の `#diagram-wrap pre:not(.mermaid) code` 系ルールに最小の上書きを追加する(スペック §3 参照)。

- [ ] **Step 3: コミット**

```bash
git add sample/sample.md
git commit -m "docs: サンプル Markdown にコードブロック例を追加する"
```

(style.css を修正した場合は同コミットに含め、メッセージを `feat: コードブロックの地色をテーマ CSS から保護する` 等に変える)

---

### Task 5: 同梱依存の棚卸し対象に highlight.js を追加する

**Files:**
- Modify: `.claude/commands/check-vendored-deps.md`
- Modify: `.claude/agents/vendored-deps-auditor.md`

**Interfaces:**
- Consumes: Task 1 の同梱ファイル名・バージョン検出コマンド
- Produces: なし(運用ドキュメント)

- [ ] **Step 1: check-vendored-deps.md を更新する**

- 冒頭の対象列挙 `` `mermaid.min.js` / `markdown-it.min.js` は手動ベンダリングで…`` を `` `mermaid.min.js` / `markdown-it.min.js` / `highlight.min.js`(+ テーマ CSS `github.css` / `github-dark.css`)は手動ベンダリングで… `` に変更。
- 「## 1. 同梱バージョンを特定する」のコードブロックに 1 行追加:

```bash
grep -o 'version:"[0-9.]*"' MmdviewApp/mmdview/Resources/highlight.min.js | head -1
```

- 同ブロックの `grep -E 'markdown-it|mermaid' MmdviewApp/package.json` を `grep -E 'markdown-it|mermaid|highlight' MmdviewApp/package.json` に変更。

- [ ] **Step 2: vendored-deps-auditor.md を更新する**

- frontmatter の `description` を「手動ベンダリングされた同梱 JS ライブラリ(mermaid / markdown-it / highlight.js)のバージョンずれと既知脆弱性を監査する。…」に変更。
- 「## 背景」の `` `mermaid.min.js` と `markdown-it.min.js` は`` を `` `mermaid.min.js`・`markdown-it.min.js`・`highlight.min.js`(+ テーマ CSS)は`` に変更。
- 「## 手順」1. のコマンド例に 1 行追加:

```
   - `grep -o 'version:"[0-9.]*"' MmdviewApp/mmdview/Resources/highlight.min.js | head -1`
```

- 「## 手順」2. の脆弱性の着眼点に「highlight.js の XSS / ReDoS」を追記(該当箇所: 「特に mermaid の XSS、markdown-it の ReDoS / DoS / XSS。」→「特に mermaid の XSS、markdown-it の ReDoS / DoS / XSS、highlight.js の XSS / ReDoS。」)。

- [ ] **Step 3: コミット**

```bash
git add .claude/commands/check-vendored-deps.md .claude/agents/vendored-deps-auditor.md
git commit -m "chore: 同梱依存の棚卸し対象に highlight.js を追加する"
```

---

### Task 6: 最終検証

**Files:** なし(検証のみ)

**Interfaces:**
- Consumes: 全タスクの成果
- Produces: 完了報告

- [ ] **Step 1: 全テスト・ビルドを実行する**

```bash
cd MmdviewApp && npx jest 2>&1 | tail -5 && swift build && swift test 2>&1 | tail -5
```

Expected: Jest 全緑 / `Build complete!` / Swift Testing 全緑

- [ ] **Step 2: 未コミットの変更がないことを確認する**

```bash
git status
```

Expected: clean
