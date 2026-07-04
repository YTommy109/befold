# Markdown 本文フォントサイズのシステム設定連動 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Markdown プレビューの本文フォントサイズを macOS のシステム本文フォントサイズ(既定 13pt、アクセシビリティのテキストサイズ設定に追従)に一致させる。

**Architecture:** Swift 側で `NSFont.preferredFont(forTextStyle: .body).pointSize` を取得し、既存の `_mmdInitialZoom` と同じ `.atDocumentStart` の `WKUserScript` で `window._mmdSystemFontSize` として注入する。JS 側は `システムサイズ ÷ BASE_SCALE(0.75)` を CSS 変数 `--mmd-markdown-font-size` に設定し、`style.css` が `.markdown-body` の font-size に適用する(ズーム 100% 時の実効表示 = システムサイズ)。

**Tech Stack:** Swift 6 / WKWebView / Swift Testing、素の JS / Jest

**Spec:** `docs/superpowers/specs/2026-07-04-system-font-size-design.md`

## Global Constraints

- Swift 6 strict concurrency(`SWIFT_STRICT_CONCURRENCY: complete`)
- コミットは Conventional Commits + 日本語(例: `feat: ...する`)
- 同一機能内の後続タスクは新規コミットではなく `git commit --amend --no-edit` でまとめる(未 push のため)
- ViewerBridge の文字列(関数名・グローバル変数名)は viewer.html 側と一致させ、ViewerBridgeTests が両ソースを読んで検証する契約
- Jest 実行は `cd MmdviewApp && npm test`、Swift テストは `cd MmdviewApp && swift test`(要 Xcode.app)

---

### Task 1: viewer.js に純粋関数 `markdownFontSize` を追加(Jest TDD)

**Files:**
- Modify: `MmdviewApp/mmdview/Resources/viewer.js`
- Test: `MmdviewApp/mmdview/Resources/__tests__/viewer.test.js`

**Interfaces:**
- Consumes: 既存の `BASE_SCALE`(= 0.75、viewer.js:7)
- Produces: `markdownFontSize(raw) -> number` — システム本文サイズ(pt)を BASE_SCALE 補正済み CSS px に変換。不正値(`undefined` / 非数 / 0 以下)は 16 を返す(従来表示への縮退)。`module.exports` に追加され、Task 2 の viewer.html と Jest から参照される

- [ ] **Step 1: 失敗するテストを書く**

`__tests__/viewer.test.js` の require に `markdownFontSize` を追加:

```js
const {
  ZOOM_MIN,
  ZOOM_MAX,
  ZOOM_STEP,
  ZOOM_DEFAULT,
  BASE_SCALE,
  DIAGRAM_ZOOM_MAX,
  clampZoom,
  stepZoom,
  wheelZoom,
  zoomLabel,
  effectiveZoom,
  parseStoredZoom,
  mermaidTheme,
  sanitizeLang,
  highlightCode,
  diagramScrollHeight,
  markdownFontSize,
} = require('../viewer');
```

ファイル末尾に describe ブロックを追加:

```js
describe('markdownFontSize', () => {
  test('converts system size to BASE_SCALE-compensated px', () => {
    // 13pt ÷ 0.75 = 17.333…px → zoom(×0.75)後の実効表示が 13px になる
    expect(markdownFontSize(13)).toBeCloseTo(13 / BASE_SCALE);
    expect(markdownFontSize(16)).toBeCloseTo(16 / BASE_SCALE);
  });

  test('accepts numeric strings', () => {
    expect(markdownFontSize('13')).toBeCloseTo(13 / BASE_SCALE);
  });

  test('falls back to 16 (legacy effective 12px) for invalid input', () => {
    expect(markdownFontSize(undefined)).toBe(16);
    expect(markdownFontSize('abc')).toBe(16);
    expect(markdownFontSize(0)).toBe(16);
    expect(markdownFontSize(-3)).toBe(16);
  });
});
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd MmdviewApp && npm test`
Expected: FAIL — `markdownFontSize is not a function`

- [ ] **Step 3: 最小実装**

`viewer.js` の `mermaidTheme` の直前あたりに追加:

```js
// システム本文フォントサイズ(pt)を、BASE_SCALE 込みの実効表示がその
// サイズになる CSS px に変換する。未注入・不正値は従来表示(実効 12px)に縮退。
function markdownFontSize(raw) {
  var s = parseFloat(raw);
  if (isNaN(s) || s <= 0) { s = 16 * BASE_SCALE; }
  return s / BASE_SCALE;
}
```

`module.exports` に `markdownFontSize: markdownFontSize,` を追加(`diagramScrollHeight` の後)。

- [ ] **Step 4: テストが通ることを確認**

Run: `cd MmdviewApp && npm test`
Expected: PASS(全テスト)

- [ ] **Step 5: コミット**

```bash
git add MmdviewApp/mmdview/Resources/viewer.js MmdviewApp/mmdview/Resources/__tests__/viewer.test.js
git commit -m "feat: Markdown 本文フォントをシステム設定のテキストサイズに合わせる

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: viewer.html の初期化と style.css の適用

**Files:**
- Modify: `MmdviewApp/mmdview/Resources/viewer.html`(末尾の初期化部、339 行付近)
- Modify: `MmdviewApp/mmdview/Resources/style.css`(`#diagram-wrap.markdown-body` ブロック、134-139 行)

**Interfaces:**
- Consumes: Task 1 の `markdownFontSize(raw)`、Swift が注入する `window._mmdSystemFontSize`(Task 3)
- Produces: CSS 変数 `--mmd-markdown-font-size`(documentElement に設定)、viewer.html 内の `window._mmdSystemFontSize` 参照(Task 3 の契約テストが存在を検証)

- [ ] **Step 1: viewer.html に `_mmdInitFontSize` を追加**

`_mmdInitZoom()` 関数定義(41-44 行)の直後に追加:

```js
  // Swift が注入したシステム本文フォントサイズを CSS 変数へ反映する。
  // 適用先は style.css の #diagram-wrap.markdown-body(Markdown 表示のみ)。
  function _mmdInitFontSize() {
    document.documentElement.style.setProperty(
      '--mmd-markdown-font-size',
      markdownFontSize(window._mmdSystemFontSize) + 'px'
    );
  }
```

末尾の `_mmdInitZoom();`(338 行)を次のように並べる:

```js
  _mmdInitZoom();
  _mmdInitFontSize();
```

- [ ] **Step 2: style.css を変更**

`#diagram-wrap.markdown-body` ブロック(134-139 行)に font-size を追加:

```css
#diagram-wrap.markdown-body {
  /* 背景は github-markdown-css の GitHub 色ではなくアプリ現行色を使う */
  --bgColor-default: var(--bg);
  width: 100%;
  max-width: 980px;
  /* システム本文フォントサイズ(BASE_SCALE 補正済み、viewer.html が設定)。
     未設定時はベンダー既定と同じ 16px */
  font-size: var(--mmd-markdown-font-size, 16px);
}
```

その直後(`pre.mermaid` ルールの前)に追加:

```css
/* ベンダー CSS の固定 12px(基準 16px の 0.75 倍)を em にし、本文サイズに追従させる */
#diagram-wrap.markdown-body tt,
#diagram-wrap.markdown-body code,
#diagram-wrap.markdown-body samp,
#diagram-wrap.markdown-body pre {
  font-size: 0.75em;
}

/* pre 内の code が 0.75em × 0.75em と二重に縮まないよう
   ベンダーの .markdown-body pre code { font-size: 100% } を ID 詳細度で再現する */
#diagram-wrap.markdown-body pre code,
#diagram-wrap.markdown-body pre tt {
  font-size: 100%;
}
```

- [ ] **Step 3: 既存テストが通ることを確認**

Run: `cd MmdviewApp && npm test`
Expected: PASS(この Task で JS ロジックは増えないため既存テストのみ)

- [ ] **Step 4: 前コミットに amend**

```bash
git add MmdviewApp/mmdview/Resources/viewer.html MmdviewApp/mmdview/Resources/style.css
git commit --amend --no-edit
```

---

### Task 3: Swift 側の注入と契約テスト(Swift Testing TDD)

**Files:**
- Modify: `MmdviewApp/mmdview/Viewer/ViewerBridge.swift`
- Modify: `MmdviewApp/mmdview/Viewer/ViewerWebView.swift`(makeNSView、27-32 行付近)
- Test: `MmdviewApp/mmdviewTests/ViewerBridgeTests.swift`

**Interfaces:**
- Consumes: viewer.html 内の `window._mmdSystemFontSize` 参照(Task 2)
- Produces: `ViewerBridge.systemFontSizeScript(_ size: Double) -> String` — `"window._mmdSystemFontSize = <size>;"` を返す

- [ ] **Step 1: 失敗するテストを書く**

`ViewerBridgeTests.swift` の `initialZoomScriptEmbedsValue` の直後に追加:

```swift
    @Test
    func systemFontSizeScriptEmbedsValue() {
        #expect(ViewerBridge.systemFontSizeScript(13.0) == "window._mmdSystemFontSize = 13.0;")
    }
```

`bridgeFunctionsExistInViewerHTML` に 1 行追加:

```swift
        #expect(html.contains("window._mmdSystemFontSize"))
```

- [ ] **Step 2: テストが失敗(ビルドエラー)することを確認**

Run: `cd MmdviewApp && swift test --filter ViewerBridgeTests`
Expected: FAIL — `systemFontSizeScript` 未定義のコンパイルエラー

- [ ] **Step 3: ViewerBridge に実装**

`initialZoomScript` の直後に追加:

```swift
    /// ロード時にシステム本文フォントサイズ(pt)を注入するスクリプト。
    /// viewer.html 側は _mmdInitFontSize() が読んで CSS 変数へ反映する。
    static func systemFontSizeScript(_ size: Double) -> String {
        "window._mmdSystemFontSize = \(size);"
    }
```

- [ ] **Step 4: ViewerWebView で注入**

`makeNSView` の `config.userContentController.addUserScript(zoomScript)`(32 行)の直後に追加:

```swift
        // Markdown 本文をシステム設定のテキストサイズに合わせる。
        // preferredFont(.body) はアクセシビリティのテキストサイズ変更に追従する(既定 13pt)。
        let fontSizeScript = WKUserScript(
            source: ViewerBridge.systemFontSizeScript(
                NSFont.preferredFont(forTextStyle: .body).pointSize
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(fontSizeScript)
```

`ViewerWebView.swift` は `import SwiftUI` / `import WebKit` 済みで `NSFont` は AppKit(SwiftUI 経由で利用可)。ビルドエラーになる場合のみ `import AppKit` を追加する。

- [ ] **Step 5: テストが通ることを確認**

Run: `cd MmdviewApp && swift test`
Expected: PASS(全テスト)

- [ ] **Step 6: 前コミットに amend**

```bash
git add MmdviewApp/mmdview/Viewer/ViewerBridge.swift MmdviewApp/mmdview/Viewer/ViewerWebView.swift MmdviewApp/mmdviewTests/ViewerBridgeTests.swift
git commit --amend --no-edit
```

---

### Task 4: 品質チェックと手動確認

**Files:**
- なし(検証のみ)

**Interfaces:**
- Consumes: Task 1-3 の成果全体
- Produces: なし

- [ ] **Step 1: 品質チェック**

Run: `/check` スキル(SwiftLint / SwiftFormat / swift test / npm test)
Expected: すべて PASS

- [ ] **Step 2: 手動確認(spec のテスト節に従う)**

`/run` スキルでアプリをビルド・起動し、表・コードブロック・mermaid ブロック入りのサンプル Markdown と `.mmd` ファイルで確認:

1. 本文がシステムのテキストサイズ(既定 13pt)相当で表示される(従来の実効 12px より一段大きい)
2. コードブロック・インラインコードが本文に比例したサイズ
3. Markdown 内 mermaid 図と `.mmd` 単体表示が従来どおり
4. ズーム(Cmd +/−、リセット)の挙動が従来どおり
5. (任意)システム設定 > アクセシビリティ > ディスプレイ > テキストサイズを変更し、新しいウィンドウで追従する
