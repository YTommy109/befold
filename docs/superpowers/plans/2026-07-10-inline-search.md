# プレビュー内検索(Cmd+F) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 現在表示中のプレビュー内容(レンダリング結果 or ソース表示中の生テキスト)に対する検索機能を、Cmd+F で開くフローティング検索バー(大文字小文字区別・単語マッチ・正規表現の3トグル付き)として追加する。置換機能は持たない。

**Architecture:** 検索の実体(DOM 走査・ハイライト・ナビゲーション)は `viewer.html`/`viewer.js` の JS で完結させる(既存のズーム・パス参照検出と同じパターン)。Swift 側は Cmd+F を Edit メニューに追加し `ViewerWindowController.find(_:)` から `evaluateJavaScript` で JS 側を開くだけ。3トグルの状態は `zoomChanged` と同型の postMessage ブリッジで `UserDefaults`(新規 `FindOptionsPreference`)にアプリ全体で永続化する。

**Tech Stack:** Swift 6 / AppKit + SwiftUI、WKWebView、Swift Testing(`befoldTests`)。JS 側に自動テスト基盤は存在しない(プロジェクト規約: 「WebView/GUI 層: 自動テスト対象外」)ため、JS ロジックは手動テストで検証する。

## Global Constraints

- 置換機能は実装しない(検索のみ)。
- 検索対象は常に「その時点で `#diagram-wrap` に描画されている DOM のテキスト」(レンダリング表示中はレンダリング結果、ソース表示中はソースコード)。
- 3トグル(大文字小文字区別・単語マッチ・正規表現)は `UserDefaults` でアプリ全体・再起動後も永続化する。検索語(クエリ文字列)自体は永続化しない。
- 検索バーはプレビュー右上のフローティングパネル。Esc または × で閉じる。Enter / Shift+Enter で次/前へ循環ナビゲーション。
- ライブリロード中(バー表示中にファイルが外部変更された場合)は、クエリとトグルを保ったまま新しい DOM に対して自動的に再検索する。
- `.html` ファイルの直接ロード表示中(`isDirectHTMLMode == true`)は Cmd+F を無効化する(viewer.html の JS が存在しないモードのため)。
- コミットメッセージは Conventional Commits + 日本語(例: `feat: プレビュー内検索を追加する`)。関連する作業は `git commit --amend --no-edit` でまとめてよいが、本計画では各タスクの終わりで新規コミットとする(タスクごとに独立してレビュー可能にするため)。

参照設計書: `docs/superpowers/specs/2026-07-10-inline-search-design.md`

---

## Task 1: `FindOptionsPreference`(検索トグルの永続化)

**Files:**
- Create: `BefoldApp/befold/App/FindOptionsPreference.swift`
- Test: `BefoldApp/befoldTests/FindOptionsPreferenceTests.swift`

**Interfaces:**
- Consumes: `makeIsolatedDefaults(prefix:)`(`BefoldApp/befoldTests/TestSupport.swift` 既存ヘルパー)
- Produces: `FindOptionsPreference`(`@MainActor final class`)。プロパティ `caseSensitive: Bool` / `wholeWord: Bool` / `useRegex: Bool`(いずれも `didSet` で `UserDefaults` へ即時保存)。`init(defaults: UserDefaults = .standard)`。後続タスクがこの3プロパティ名とデフォルト値(すべて `false`)をそのまま使う。

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/FindOptionsPreferenceTests.swift` を新規作成する。

```swift
@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct FindOptionsPreferenceTests {
    @Test("デフォルトはすべて false(大文字小文字区別なし・単語マッチなし・正規表現なし)")
    func defaultsToAllFalseWhenUnsaved() {
        let preference = FindOptionsPreference(defaults: makeIsolatedDefaults(prefix: "FindOptionsPreferenceTests"))

        #expect(preference.caseSensitive == false)
        #expect(preference.wholeWord == false)
        #expect(preference.useRegex == false)
    }

    @Test("caseSensitive をトグルした値は UserDefaults に永続化され、次のインスタンスへ引き継がれる")
    func caseSensitiveTogglePersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults(prefix: "FindOptionsPreferenceTests")

        FindOptionsPreference(defaults: defaults).caseSensitive = true

        #expect(FindOptionsPreference(defaults: defaults).caseSensitive == true)
    }

    @Test("wholeWord をトグルした値は UserDefaults に永続化され、次のインスタンスへ引き継がれる")
    func wholeWordTogglePersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults(prefix: "FindOptionsPreferenceTests")

        FindOptionsPreference(defaults: defaults).wholeWord = true

        #expect(FindOptionsPreference(defaults: defaults).wholeWord == true)
    }

    @Test("useRegex をトグルした値は UserDefaults に永続化され、次のインスタンスへ引き継がれる")
    func useRegexTogglePersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults(prefix: "FindOptionsPreferenceTests")

        FindOptionsPreference(defaults: defaults).useRegex = true

        #expect(FindOptionsPreference(defaults: defaults).useRegex == true)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter FindOptionsPreferenceTests`
Expected: FAIL(`FindOptionsPreference` が存在しないためビルドエラー)

- [ ] **Step 3: 最小実装を書く**

`BefoldApp/befold/App/FindOptionsPreference.swift` を新規作成する(`HiddenFilesPreference` と同じ「薄い永続化専用クラス」パターン)。

```swift
import Foundation

/// 検索バーの3トグル(大文字小文字区別・単語マッチ・正規表現)を UserDefaults に永続化する。
/// ファイル単位ではなくアプリ全体で共有する単一の状態(ZoomStore の per-file 方式とは異なる)。
@MainActor
final class FindOptionsPreference {
    private let defaults: UserDefaults
    private static let caseSensitiveKey = "FindCaseSensitive"
    private static let wholeWordKey = "FindWholeWord"
    private static let useRegexKey = "FindUseRegex"

    var caseSensitive: Bool {
        didSet { defaults.set(caseSensitive, forKey: Self.caseSensitiveKey) }
    }
    var wholeWord: Bool {
        didSet { defaults.set(wholeWord, forKey: Self.wholeWordKey) }
    }
    var useRegex: Bool {
        didSet { defaults.set(useRegex, forKey: Self.useRegexKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        caseSensitive = defaults.bool(forKey: Self.caseSensitiveKey)
        wholeWord = defaults.bool(forKey: Self.wholeWordKey)
        useRegex = defaults.bool(forKey: Self.useRegexKey)
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter FindOptionsPreferenceTests`
Expected: PASS(4 tests)

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/FindOptionsPreference.swift BefoldApp/befoldTests/FindOptionsPreferenceTests.swift
git commit -m "feat: 検索トグルの永続化用 FindOptionsPreference を追加する

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 2: `ViewerBridge` に検索用のブリッジ関数を追加

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerBridge.swift`
- Modify: `BefoldApp/befoldTests/ViewerBridgeTests.swift`

**Interfaces:**
- Consumes: なし(Task 1 とは独立)
- Produces: `ViewerBridge.openFindScript: String`(`"_mmdOpenFind()"`)、`ViewerBridge.findOptionsChangedMessageName: String`(`"findOptionsChanged"`)、`ViewerBridge.FindOptions`(`caseSensitive: Bool, wholeWord: Bool, useRegex: Bool` を持つ struct)、`ViewerBridge.initialFindOptionsScript(_ options: FindOptions) -> String`。Task 4・5 がこれらをそのまま使う。

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/ViewerBridgeTests.swift` の `lineNumbersScriptEmbedsBool` テストの直後(65行目、`bridgeFunctionsExistInViewerHTML` テストの手前)に追加する。

```swift
    @Test("openFindScript が固定の呼び出し文字列である")
    func openFindScriptIsFixedCall() {
        #expect(ViewerBridge.openFindScript == "_mmdOpenFind()")
    }

    @Test("findOptionsChangedMessageName が固定値である")
    func findOptionsChangedMessageNameIsFixed() {
        #expect(ViewerBridge.findOptionsChangedMessageName == "findOptionsChanged")
    }

    @Test("initialFindOptionsScript がトグル値を埋め込む")
    func initialFindOptionsScriptEmbedsValues() {
        let options = ViewerBridge.FindOptions(caseSensitive: true, wholeWord: false, useRegex: true)

        #expect(
            ViewerBridge.initialFindOptionsScript(options)
                == "window._mmdInitialFindOptions = { caseSensitive: true, wholeWord: false, useRegex: true };"
        )
    }

```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter ViewerBridgeTests`
Expected: FAIL(`ViewerBridge.openFindScript` 等が存在しないためビルドエラー)

- [ ] **Step 3: 最小実装を書く**

`BefoldApp/befold/Viewer/ViewerBridge.swift` の `lineNumbersScript(_:)`(64-65行目)の直後に追加する。

```swift

    /// 検索バーを開く(未オープンなら表示してフォーカス)スクリプト。
    static let openFindScript = "_mmdOpenFind()"

    /// JS 側で検索トグル(大文字小文字区別・単語マッチ・正規表現)が変わったときに
    /// postMessage されるメッセージハンドラ名。
    static let findOptionsChangedMessageName = "findOptionsChanged"

    /// 検索の3トグルの状態。
    struct FindOptions: Equatable {
        var caseSensitive: Bool
        var wholeWord: Bool
        var useRegex: Bool
    }

    /// ロード時に検索トグルの保存済み状態を注入するスクリプト。
    /// viewer.html 側は _mmdInitFind() が window._mmdInitialFindOptions を読んで適用する。
    static func initialFindOptionsScript(_ options: FindOptions) -> String {
        "window._mmdInitialFindOptions = { caseSensitive: \(options.caseSensitive), " +
            "wholeWord: \(options.wholeWord), useRegex: \(options.useRegex) };"
    }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter ViewerBridgeTests`
Expected: PASS(既存テストを含め全て通る。`bridgeFunctionsExistInViewerHTML` は Task 3 まで変更しないためこの時点でも PASS のまま)

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/Viewer/ViewerBridge.swift BefoldApp/befoldTests/ViewerBridgeTests.swift
git commit -m "feat: ViewerBridge に検索用のスクリプト・メッセージ名を追加する

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 3: `viewer.html` / `viewer.js` / `style.css` — 検索バー UI とロジック

**Files:**
- Modify: `BefoldApp/befold/Resources/viewer.js`
- Modify: `BefoldApp/befold/Resources/viewer.html`
- Modify: `BefoldApp/befold/Resources/style.css`
- Modify: `BefoldApp/befoldTests/ViewerBridgeTests.swift`

**Interfaces:**
- Consumes: `ViewerBridge.findOptionsChangedMessageName`(Task 2、テストの文字列比較のみに使用。JS 側は文字列リテラル `'findOptionsChanged'` を直接埋め込む)
- Produces: JS 関数 `_mmdOpenFind()` / `_mmdCloseFind()` / `_mmdFindRefresh()` / `_mmdFindIsOpen()`、グローバル `window._mmdInitialFindOptions`。Task 4 の `ViewerBridge.openFindScript`(`_mmdOpenFind()`)呼び出しと `window._mmdInitialFindOptions` 注入がこれらと結線される。

- [ ] **Step 1: `viewer.js` に正規表現組み立ての純粋関数を追加する**

`BefoldApp/befold/Resources/viewer.js` の末尾に追加する(この関数は既存のプロジェクト規約により自動テスト基盤がないため、Task 3 の Step 6(手動テスト)で検証する)。

```js

// --- Find ---

// クエリと3トグル(caseSensitive / wholeWord / useRegex)から RegExp を組み立てる。
// クエリが空、または正規表現として不正な場合は null を返す(呼び出し側はエラー表示に切り替える)。
function buildFindRegExp(query, options) {
  if (!query) { return null; }
  var source = options.useRegex ? query : query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  if (options.wholeWord) { source = '\\b(?:' + source + ')\\b'; }
  var flags = 'g' + (options.caseSensitive ? '' : 'i');
  try {
    return new RegExp(source, flags);
  } catch (e) {
    return null;
  }
}
```

- [ ] **Step 2: `style.css` に検索バーのスタイルを追加する**

`BefoldApp/befold/Resources/style.css` の `.diagram-zoom-label:hover { color: var(--accent); }`(387-389行目)の直後、`/* ── CSV テーブル表示 ── */`(391行目)の手前に追加する。

```css

/* ── 検索バー(Cmd+F) ── */
.mmd-find-bar {
  position: fixed;
  top: 12px;
  right: 12px;
  z-index: 100;
  display: none;
  align-items: center;
  gap: 4px;
  background: var(--panel-bg);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  border: 1px solid var(--panel-border);
  border-radius: 8px;
  padding: 6px 8px;
  box-shadow: 0 1px 4px var(--panel-shadow);
  font-size: 13px;
}

.mmd-find-input {
  width: 180px;
  padding: 3px 6px;
  border: 1px solid var(--panel-border);
  border-radius: 4px;
  background: transparent;
  color: var(--fg);
  font-size: 13px;
  outline: none;
}

.mmd-find-input.mmd-find-error {
  border-color: var(--error-border);
  background: var(--error-bg);
  color: var(--error-fg);
}

.mmd-find-count {
  min-width: 64px;
  text-align: center;
  color: var(--fg-muted);
  white-space: nowrap;
}

.mmd-find-bar button {
  width: 22px;
  height: 22px;
  border: none;
  background: none;
  cursor: pointer;
  font-size: 13px;
  color: var(--btn-fg);
  border-radius: 4px;
  display: flex;
  align-items: center;
  justify-content: center;
  line-height: 1;
}

.mmd-find-bar button:hover {
  background: var(--btn-hover-bg);
}

.mmd-find-toggle.active {
  background: var(--accent);
  color: #fff;
}

mark.mmd-find-match {
  background: rgba(255, 213, 0, 0.55);
  color: inherit;
}

mark.mmd-find-match-current {
  background: var(--accent);
  color: #fff;
}
```

- [ ] **Step 3: `viewer.html` に検索バーの HTML を追加する**

`BefoldApp/befold/Resources/viewer.html` の `</div>`(25行目、`.viewer` の閉じタグ)の直後、`<script src="viewer.js"></script>`(27行目)の手前に追加する。

```html

  <div id="mmd-find-bar" class="mmd-find-bar">
    <input id="mmd-find-input" type="text" class="mmd-find-input" placeholder="検索">
    <span id="mmd-find-count" class="mmd-find-count"></span>
    <button id="mmd-find-prev" class="mmd-find-nav" title="前へ (Shift+Enter)">&#728;</button>
    <button id="mmd-find-next" class="mmd-find-nav" title="次へ (Enter)">&#711;</button>
    <button id="mmd-find-case" class="mmd-find-toggle" title="大文字・小文字を区別">Aa</button>
    <button id="mmd-find-word" class="mmd-find-toggle" title="単語単位で検索">ab|</button>
    <button id="mmd-find-regex" class="mmd-find-toggle" title="正規表現">.*</button>
    <button id="mmd-find-close" class="mmd-find-close" title="閉じる (Esc)">&times;</button>
  </div>
```

- [ ] **Step 4: `viewer.html` の検索ロジックを追加する**

`BefoldApp/befold/Resources/viewer.html` 内、`md.validateLink = isSafeLinkURL;` を含む markdown-it セットアップブロックの終わり(413行目 `}`)の直後、`// --- Render ---`(415行目)の手前に追加する。

```js

  // --- Find ---
  var _mmdFindOptions = { caseSensitive: false, wholeWord: false, useRegex: false };
  var _mmdFindQuery = '';
  var _mmdFindMatches = [];
  var _mmdFindCurrentIndex = -1;
  var _mmdFindIsOpenFlag = false;

  // ロード時に保存済みトグル状態(window._mmdInitialFindOptions、Swift から注入)を反映する。
  function _mmdInitFind() {
    var opts = window._mmdInitialFindOptions || {};
    _mmdFindOptions.caseSensitive = !!opts.caseSensitive;
    _mmdFindOptions.wholeWord = !!opts.wholeWord;
    _mmdFindOptions.useRegex = !!opts.useRegex;
    document.getElementById('mmd-find-case').classList.toggle('active', _mmdFindOptions.caseSensitive);
    document.getElementById('mmd-find-word').classList.toggle('active', _mmdFindOptions.wholeWord);
    document.getElementById('mmd-find-regex').classList.toggle('active', _mmdFindOptions.useRegex);
  }

  function _mmdFindIsOpen() {
    return _mmdFindIsOpenFlag;
  }

  function _mmdOpenFind() {
    _mmdFindIsOpenFlag = true;
    document.getElementById('mmd-find-bar').style.display = 'flex';
    var input = document.getElementById('mmd-find-input');
    input.value = _mmdFindQuery;
    input.focus();
    input.select();
    _mmdFindRun();
  }

  function _mmdCloseFind() {
    _mmdFindIsOpenFlag = false;
    document.getElementById('mmd-find-bar').style.display = 'none';
    _mmdFindClearMarks();
    _mmdFindMatches = [];
    _mmdFindCurrentIndex = -1;
  }

  // 前回検索でハイライトした <mark> を平文へ復元する(次の検索前に必ず呼ぶ)。
  function _mmdFindClearMarks() {
    var marks = document.querySelectorAll('#diagram-wrap mark.mmd-find-match');
    marks.forEach(function(mark) {
      var text = document.createTextNode(mark.textContent);
      var parent = mark.parentNode;
      if (!parent) return;
      parent.replaceChild(text, mark);
      parent.normalize();
    });
  }

  // 1つのテキストノード内のマッチをすべて <mark> に置換し、matches に追加する。
  // ゼロ幅マッチ(例: 正規表現 "a*" の空文字一致)は無限ループを避けるため読み飛ばす。
  function _mmdFindWalkText(node, regex, matches) {
    var text = node.textContent;
    regex.lastIndex = 0;
    var ranges = [];
    var match;
    while ((match = regex.exec(text)) !== null) {
      if (match[0].length === 0) {
        regex.lastIndex++;
        if (regex.lastIndex > text.length) break;
        continue;
      }
      ranges.push({ index: match.index, text: match[0] });
    }
    if (ranges.length === 0) return;
    var frag = document.createDocumentFragment();
    var lastIndex = 0;
    ranges.forEach(function(range) {
      if (range.index > lastIndex) {
        frag.appendChild(document.createTextNode(text.slice(lastIndex, range.index)));
      }
      var mark = document.createElement('mark');
      mark.className = 'mmd-find-match';
      mark.textContent = range.text;
      frag.appendChild(mark);
      matches.push(mark);
      lastIndex = range.index + range.text.length;
    });
    if (lastIndex < text.length) {
      frag.appendChild(document.createTextNode(text.slice(lastIndex)));
    }
    node.parentNode.replaceChild(frag, node);
  }

  // #diagram-wrap 配下のテキストノードを再帰的に歩き、マッチを <mark> に置換する。
  // 既知の制約: シンタックスハイライトの <span> 境界やパス参照 <span> の境界をまたぐ
  // 一致は検出しない(_PATH_RE の制約と同じ考え方)。
  function _mmdFindWalk(node, regex, matches) {
    if (node.nodeType === 3) {
      _mmdFindWalkText(node, regex, matches);
    } else if (node.nodeType === 1 && node.tagName !== 'MARK') {
      var children = Array.prototype.slice.call(node.childNodes);
      for (var i = 0; i < children.length; i++) {
        _mmdFindWalk(children[i], regex, matches);
      }
    }
  }

  function _mmdFindUpdateCount() {
    var countEl = document.getElementById('mmd-find-count');
    var input = document.getElementById('mmd-find-input');
    if (_mmdFindQuery.length === 0 || input.classList.contains('mmd-find-error')) {
      countEl.textContent = '';
    } else if (_mmdFindMatches.length === 0) {
      countEl.textContent = '見つかりません';
    } else {
      countEl.textContent = (_mmdFindCurrentIndex + 1) + '/' + _mmdFindMatches.length;
    }
  }

  function _mmdFindHighlightCurrent() {
    _mmdFindMatches.forEach(function(mark) { mark.classList.remove('mmd-find-match-current'); });
    var current = _mmdFindMatches[_mmdFindCurrentIndex];
    if (!current) return;
    current.classList.add('mmd-find-match-current');
    current.scrollIntoView({ block: 'center', behavior: 'smooth' });
  }

  // 入力・トグル変更のたびに呼ばれる: 現在のハイライトをクリアして再検索する。
  function _mmdFindRun() {
    var input = document.getElementById('mmd-find-input');
    _mmdFindQuery = input.value;
    _mmdFindClearMarks();
    _mmdFindMatches = [];
    _mmdFindCurrentIndex = -1;

    var regex = buildFindRegExp(_mmdFindQuery, _mmdFindOptions);
    input.classList.toggle('mmd-find-error', _mmdFindQuery.length > 0 && regex === null);

    if (regex) {
      _mmdFindWalk(document.getElementById('diagram-wrap'), regex, _mmdFindMatches);
    }

    if (_mmdFindMatches.length > 0) {
      _mmdFindCurrentIndex = 0;
      _mmdFindHighlightCurrent();
    }
    _mmdFindUpdateCount();
  }

  // render() の末尾から呼ばれる: バーが開いていれば同じクエリ・トグルのまま
  // 新しい DOM に対して再検索し、可能なら現在位置を維持する(ライブリロード追従)。
  function _mmdFindRefresh() {
    var previousIndex = _mmdFindCurrentIndex;
    _mmdFindRun();
    if (_mmdFindMatches.length > 0) {
      _mmdFindCurrentIndex = Math.min(Math.max(previousIndex, 0), _mmdFindMatches.length - 1);
      _mmdFindHighlightCurrent();
      _mmdFindUpdateCount();
    }
  }

  function _mmdFindNext() {
    if (_mmdFindMatches.length === 0) return;
    _mmdFindCurrentIndex = (_mmdFindCurrentIndex + 1) % _mmdFindMatches.length;
    _mmdFindHighlightCurrent();
    _mmdFindUpdateCount();
  }

  function _mmdFindPrev() {
    if (_mmdFindMatches.length === 0) return;
    _mmdFindCurrentIndex = (_mmdFindCurrentIndex - 1 + _mmdFindMatches.length) % _mmdFindMatches.length;
    _mmdFindHighlightCurrent();
    _mmdFindUpdateCount();
  }

  // トグルボタン共通のハンドラ: 状態を反転し、見た目を更新し、Swift へ永続化を依頼して再検索する。
  function _mmdFindToggleOption(optionName, buttonId) {
    _mmdFindOptions[optionName] = !_mmdFindOptions[optionName];
    document.getElementById(buttonId).classList.toggle('active', _mmdFindOptions[optionName]);
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.findOptionsChanged) {
      window.webkit.messageHandlers.findOptionsChanged.postMessage({
        caseSensitive: _mmdFindOptions.caseSensitive,
        wholeWord: _mmdFindOptions.wholeWord,
        useRegex: _mmdFindOptions.useRegex
      });
    }
    _mmdFindRun();
  }

  document.getElementById('mmd-find-input').addEventListener('input', _mmdFindRun);
  document.getElementById('mmd-find-input').addEventListener('keydown', function(e) {
    if (e.key === 'Enter') {
      e.preventDefault();
      if (e.shiftKey) { _mmdFindPrev(); } else { _mmdFindNext(); }
    } else if (e.key === 'Escape') {
      e.preventDefault();
      _mmdCloseFind();
    }
  });
  document.getElementById('mmd-find-next').addEventListener('click', _mmdFindNext);
  document.getElementById('mmd-find-prev').addEventListener('click', _mmdFindPrev);
  document.getElementById('mmd-find-close').addEventListener('click', _mmdCloseFind);
  document.getElementById('mmd-find-case').addEventListener('click', function() {
    _mmdFindToggleOption('caseSensitive', 'mmd-find-case');
  });
  document.getElementById('mmd-find-word').addEventListener('click', function() {
    _mmdFindToggleOption('wholeWord', 'mmd-find-word');
  });
  document.getElementById('mmd-find-regex').addEventListener('click', function() {
    _mmdFindToggleOption('useRegex', 'mmd-find-regex');
  });
```

- [ ] **Step 5: 既存の keydown ハンドラに Esc、`render()` に再検索フック、初期化呼び出しを追加する**

`BefoldApp/befold/Resources/viewer.html` の3箇所を編集する。

1つ目、既存の `document.addEventListener('keydown', function(e) {`(108行目)の直後(`document.body.classList.toggle('cmd-held', e.metaKey);` の手前)に Esc 分岐を追加する。

```js
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && _mmdFindIsOpen()) {
      e.preventDefault();
      _mmdCloseFind();
      return;
    }
    document.body.classList.toggle('cmd-held', e.metaKey);
```

2つ目、`render()` 内の `_annotatePathRefs();`(567行目)の直後、`_mmdApplyZoom();`(568行目)の手前に追加する。

```js
    _annotatePathRefs();
    if (_mmdFindIsOpen()) { _mmdFindRefresh(); }
    _mmdApplyZoom();
```

3つ目、ファイル末尾の初期化呼び出し(594-595行目)に追加する。

```js
  _mmdInitZoom();
  _mmdInitFontSize();
  _mmdInitFind();
```

- [ ] **Step 6: `ViewerBridgeTests` の整合性チェックを拡張する**

`BefoldApp/befoldTests/ViewerBridgeTests.swift` の `bridgeFunctionsExistInViewerHTML` テスト(69-85行目)内、既存の `#expect` 群の末尾(`#expect(html.contains("function setLineNumbers(show)"))` の直後)に追加する。

```swift
        #expect(html.contains("function _mmdOpenFind()"))
        #expect(html.contains("function _mmdCloseFind()"))
        #expect(html.contains("function _mmdFindRefresh()"))
        #expect(html.contains("window._mmdInitialFindOptions"))
        #expect(html.contains("messageHandlers.\(ViewerBridge.findOptionsChangedMessageName)"))
```

- [ ] **Step 7: テストを実行してすべて通ることを確認する**

Run: `cd BefoldApp && swift test --filter ViewerBridgeTests`
Expected: PASS(`bridgeFunctionsExistInViewerHTML` を含め全て通る)

- [ ] **Step 8: 手動テストで JS ロジックを検証する**

`buildFindRegExp` を含む JS ロジックにはこのプロジェクトの自動テスト基盤が及ばない(`WebView/GUI 層: 自動テスト対象外` — プロジェクト規約)ため、この時点でアプリをビルドして手動確認する。

Run: `cd BefoldApp && xcodegen generate && xcodebuild build -scheme befold`
Expected: ビルド成功

アプリを起動し、任意の `.md` ファイルを開いて以下を確認する:
- Cmd+F でプレビュー右上に検索バーが表示され、入力欄にフォーカスが当たる
- 一致する語を入力すると黄色でハイライトされ、件数(`1/3` など)が表示される
- Enter / Shift+Enter で次/前の一致(オレンジ/青のハイライト)へ循環しながら移動する
- `Aa` / `ab|` / `.*` の各トグルを押すと見た目がアクティブ表示に変わり、再検索される
- 不正な正規表現(例: `(` のみ)を入力すると入力欄が赤枠になり件数が空になる
- Esc または × でバーが閉じ、ハイライトが消える

- [ ] **Step 9: コミット**

```bash
git add BefoldApp/befold/Resources/viewer.js BefoldApp/befold/Resources/viewer.html \
  BefoldApp/befold/Resources/style.css BefoldApp/befoldTests/ViewerBridgeTests.swift
git commit -m "feat: プレビュー内検索バーの UI とロジックを viewer.html に追加する

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 4: `FindOptionsPreference` を全層へ注入し `ViewerWebView` にブリッジ配線する

**Files:**
- Modify: `BefoldApp/befold/App/AppDelegate.swift`
- Modify: `BefoldApp/befold/App/ViewerWindowManager.swift`
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`
- Modify: `BefoldApp/befold/Viewer/ViewerContentView.swift`
- Modify: `BefoldApp/befold/Viewer/ViewerWebView.swift`

**Interfaces:**
- Consumes: `FindOptionsPreference`(Task 1)、`ViewerBridge.findOptionsChangedMessageName` / `ViewerBridge.FindOptions` / `ViewerBridge.initialFindOptionsScript(_:)`(Task 2)
- Produces: `ViewerWebView.findOptionsPreference: FindOptionsPreference`(必須プロパティ、デフォルト値なし)。`Coordinator.findOptionsPreference: FindOptionsPreference?`。`ViewerWindowController.findOptionsPreference`(Task 5 の `find(_:)` アクションが使う)。

`ViewerWebView`(SwiftUI の `NSViewRepresentable` struct)の格納プロパティにクラス生成式のデフォルト値を与えると、メインアクター分離の評価文脈が不明瞭になりビルドが不安定になりうる(このコードベースの `ViewerWebView` / `ViewerContentView` に前例のないパターンのため)。そのため `AppDelegate` で生成した単一の共有インスタンスを、デフォルト値なしで `ViewerWindowManager` → `ViewerWindowController` → `ViewerContentView` → `ViewerWebView` まで一括で配線する(`zoomStore` の配線と同じ経路)。

このタスクは WKWebView のランタイム結線であり、プロジェクト規約(`WebView/GUI 層: 自動テスト対象外`)により自動テストは書かない。`swift build` の成功のみを確認する。

- [ ] **Step 1: `AppDelegate` で `FindOptionsPreference` を1つ生成し `ViewerWindowManager` に渡す**

`BefoldApp/befold/App/AppDelegate.swift` の `override init()`(22-39行目)を編集する。

```swift
    override init() {
        let sessionStore = SessionStore()
        let zoomStore = ZoomStore()
        let recentDocumentsStore = RecentDocumentsStore()
        let hiddenFilesPreference = HiddenFilesPreference()
        let findOptionsPreference = FindOptionsPreference()
        let windowManager = ViewerWindowManager(
            sessionStore: sessionStore,
            zoomStore: zoomStore,
            recentDocumentsStore: recentDocumentsStore,
            hiddenFilesPreference: hiddenFilesPreference,
            findOptionsPreference: findOptionsPreference
        )
        self.sessionStore = sessionStore
        self.recentDocumentsStore = recentDocumentsStore
        self.windowManager = windowManager
        self.hiddenFilesPreference = hiddenFilesPreference
        sessionRestorer = SessionRestorer(sessionStore: sessionStore, windowManager: windowManager)
        super.init()
    }
```

- [ ] **Step 2: `ViewerWindowManager` に `findOptionsPreference` を追加し `ViewerWindowController` へ渡す**

`BefoldApp/befold/App/ViewerWindowManager.swift` を編集する。プロパティ・初期化(9-23行目)。

```swift
    private let zoomStore: ZoomStore
    private let recentDocumentsStore: RecentDocumentsStore
    private let hiddenFilesPreference: HiddenFilesPreference
    private let findOptionsPreference: FindOptionsPreference

    /// - Parameter hiddenFilesPreference: 本番では必ず AppDelegate が持つ単一の共有インスタンスを渡すこと。
    ///   デフォルト値は、不可視ファイル挙動に無関心なテストが省略できるようにするためのもの。
    /// - Parameter findOptionsPreference: 同上。検索トグル挙動に無関心なテストが省略できるようにする。
    init(
        sessionStore: SessionStore, zoomStore: ZoomStore, recentDocumentsStore: RecentDocumentsStore,
        hiddenFilesPreference: HiddenFilesPreference = HiddenFilesPreference(),
        findOptionsPreference: FindOptionsPreference = FindOptionsPreference()
    ) {
        self.sessionStore = sessionStore
        self.zoomStore = zoomStore
        self.recentDocumentsStore = recentDocumentsStore
        self.hiddenFilesPreference = hiddenFilesPreference
        self.findOptionsPreference = findOptionsPreference
    }
```

`openViewer(for:forceSidebarVisible:)` 内の `ViewerWindowController(` 呼び出し(54-59行目)。

```swift
        let controller = ViewerWindowController(
            fileURL: url,
            zoomStore: zoomStore,
            hiddenFilesPreference: hiddenFilesPreference,
            findOptionsPreference: findOptionsPreference,
            forceSidebarVisible: forceSidebarVisible
        )
```

- [ ] **Step 3: `ViewerWindowController` に `findOptionsPreference` を追加する**

`BefoldApp/befold/App/ViewerWindowController.swift` のプロパティ(15-17行目)。

```swift
    private let zoomStore: ZoomStore
    private let hiddenFilesPreference: HiddenFilesPreference
    private let findOptionsPreference: FindOptionsPreference
    private let forceSidebarVisible: Bool
```

`init(...)`(56-68行目)。

```swift
    /// - Parameter hiddenFilesPreference: 本番では必ず AppDelegate → ViewerWindowManager から
    ///   注入される単一の共有インスタンスを渡すこと。デフォルト値は、不可視ファイル挙動に
    ///   無関心なテストが省略できるようにするためのもの。
    /// - Parameter findOptionsPreference: 同上。検索トグル挙動に無関心なテストが省略できるようにする。
    init(
        fileURL: URL, zoomStore: ZoomStore, defaults: UserDefaults = .standard,
        hiddenFilesPreference: HiddenFilesPreference = HiddenFilesPreference(),
        findOptionsPreference: FindOptionsPreference = FindOptionsPreference(),
        forceSidebarVisible: Bool = false
    ) {
        self.fileURL = fileURL
        self.zoomStore = zoomStore
        self.defaults = defaults
        self.hiddenFilesPreference = hiddenFilesPreference
        self.findOptionsPreference = findOptionsPreference
        self.forceSidebarVisible = forceSidebarVisible
```

`makeSplitViewController()` 内の `ViewerContentView(` 呼び出し(153-165行目)。

```swift
        let contentView = ViewerContentView(
            store: store,
            zoomStore: zoomStore,
            findOptionsPreference: findOptionsPreference,
            // 現在の fileURL は rename で書き換わるため、旧値を捕捉せず self 経由で参照する
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

- [ ] **Step 4: `ViewerContentView` に `findOptionsPreference` を追加し `ViewerWebView` へ渡す**

`BefoldApp/befold/Viewer/ViewerContentView.swift` を編集する。

```swift
struct ViewerContentView: View {
    let store: ViewerStore
    let zoomStore: ZoomStore
    let findOptionsPreference: FindOptionsPreference
    let onZoomChanged: @MainActor (Double) -> Void
    let onOpenReference: @MainActor (_ href: String, _ isExternal: Bool, _ newWindow: Bool) -> Void
    let webViewProxy: WebViewProxy
```

`body` 内の `ViewerWebView(` 呼び出し。

```swift
                ViewerWebView(
                    content: store.content,
                    fileType: store.fileType,
                    filePath: store.filePath,
                    isSourceMode: store.isSourceMode,
                    showLineNumbers: store.showLineNumbers,
                    initialZoom: currentZoom,
                    onZoomChanged: onZoomChanged,
                    onOpenReference: onOpenReference,
                    findOptionsPreference: findOptionsPreference,
                    webViewProxy: webViewProxy
                )
```

- [ ] **Step 5: `ViewerWebView` に `findOptionsPreference` プロパティを追加する**

`BefoldApp/befold/Viewer/ViewerWebView.swift` の `let webViewProxy: WebViewProxy`(23行目)の直後に追加する。

```swift
    /// AppKit 側（メニューアクション）へ WKWebView を公開するプロキシ。
    let webViewProxy: WebViewProxy
    /// 検索バーの3トグル(大文字小文字区別・単語マッチ・正規表現)の永続化ストア。
    let findOptionsPreference: FindOptionsPreference
```

- [ ] **Step 6: `makeNSView` に検索トグルの初期値注入とメッセージハンドラ登録を追加する**

`BefoldApp/befold/Viewer/ViewerWebView.swift` の `config.userContentController.addUserScript(fontSizeScript)`(50行目)の直後、`config.userContentController.add(` (51行目、zoomChanged ハンドラ登録)の手前に追加する。

```swift
        config.userContentController.addUserScript(fontSizeScript)
        let findOptionsScript = WKUserScript(
            source: ViewerBridge.initialFindOptionsScript(
                ViewerBridge.FindOptions(
                    caseSensitive: findOptionsPreference.caseSensitive,
                    wholeWord: findOptionsPreference.wholeWord,
                    useRegex: findOptionsPreference.useRegex
                )
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(findOptionsScript)
        config.userContentController.add(
            WeakScriptMessageHandler(delegate: context.coordinator),
            name: ViewerBridge.findOptionsChangedMessageName
        )
        context.coordinator.findOptionsPreference = findOptionsPreference
        config.userContentController.add(
```

- [ ] **Step 7: `updateNSView` で `findOptionsPreference` を都度更新する**

`BefoldApp/befold/Viewer/ViewerWebView.swift` の `updateNSView(_:context:)`(83-94行目)内、`context.coordinator.onOpenReference = onOpenReference`(85行目)の直後に追加する。

```swift
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onZoomChanged = onZoomChanged
        context.coordinator.onOpenReference = onOpenReference
        context.coordinator.findOptionsPreference = findOptionsPreference
        context.coordinator.initialPageZoom = initialZoom
```

- [ ] **Step 8: `dismantleNSView` でハンドラを解除する**

`BefoldApp/befold/Viewer/ViewerWebView.swift` の `dismantleNSView(_:coordinator:)`(108-113行目)に追加する。

```swift
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController
            .removeScriptMessageHandler(forName: ViewerBridge.zoomChangedMessageName)
        nsView.configuration.userContentController
            .removeScriptMessageHandler(forName: ViewerBridge.referenceActivatedMessageName)
        nsView.configuration.userContentController
            .removeScriptMessageHandler(forName: ViewerBridge.findOptionsChangedMessageName)
    }
```

- [ ] **Step 9: `Coordinator` にプロパティとメッセージ処理を追加する**

`BefoldApp/befold/Viewer/ViewerWebView.swift` の `Coordinator` クラス内、`var onOpenReference: (...)?`(142行目)の直後に追加する。

```swift
        var onOpenReference: (@MainActor (_ href: String, _ isExternal: Bool, _ newWindow: Bool) -> Void)?
        /// 検索バーの3トグルの永続化ストア。findOptionsChanged 受信時に書き戻す。
        var findOptionsPreference: FindOptionsPreference?
```

同ファイル `userContentController(_:didReceive:)`(158-175行目)の `else if message.name == ViewerBridge.referenceActivatedMessageName, ...` ブロックの直後(`onOpenReference?(href, isExternal, newWindow)` の次、閉じ `}` の直前に分岐を追加)。

```swift
            } else if message.name == ViewerBridge.referenceActivatedMessageName,
                      let body = message.body as? [String: Any],
                      let href = body["href"] as? String,
                      let isExternal = body["isExternal"] as? Bool,
                      let newWindow = body["newWindow"] as? Bool
            {
                onOpenReference?(href, isExternal, newWindow)
            } else if message.name == ViewerBridge.findOptionsChangedMessageName,
                      let body = message.body as? [String: Any],
                      let caseSensitive = body["caseSensitive"] as? Bool,
                      let wholeWord = body["wholeWord"] as? Bool,
                      let useRegex = body["useRegex"] as? Bool
            {
                findOptionsPreference?.caseSensitive = caseSensitive
                findOptionsPreference?.wholeWord = wholeWord
                findOptionsPreference?.useRegex = useRegex
            }
```

- [ ] **Step 10: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build && swift test`
Expected: ビルド成功・全テスト PASS(既存の `ViewerWindowControllerTests` などは `findOptionsPreference` にデフォルト値付きの新規パラメータが増えるだけのため変更不要でそのまま通る)

- [ ] **Step 11: コミット**

```bash
git add BefoldApp/befold/App/AppDelegate.swift BefoldApp/befold/App/ViewerWindowManager.swift \
  BefoldApp/befold/App/ViewerWindowController.swift BefoldApp/befold/Viewer/ViewerContentView.swift \
  BefoldApp/befold/Viewer/ViewerWebView.swift
git commit -m "feat: FindOptionsPreference を全層へ注入し ViewerWebView にブリッジ配線する

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 5: Cmd+F メニュー配線

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`
- Modify: `BefoldApp/befold/App/MainMenuBuilder.swift`
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ViewerBridge.openFindScript`(Task 2)、`ViewerWindowController.findOptionsPreference` は使わない(このアクションは検索バーを開くだけで、トグル値の読み書きは JS 側と `findOptionsChanged` ブリッジ(Task 4)が担う)。`ViewerWindowController.webViewProxy`(既存)を使う。
- Produces: `ViewerWindowController.find(_:)`(`@objc` アクション)。Edit メニューの「検索…」項目(Cmd+F)。

- [ ] **Step 1: `ViewerWindowController` に `find(_:)` アクションを実装する**

`BefoldApp/befold/App/ViewerWindowController.swift` の `printDocument(_:)`(394-406行目)の直後に追加する。

```swift
    /// Edit > 検索…。プレビュー右上の検索バーを開く。
    /// HTML ファイルの直接ロード表示中は viewer.html の JS が存在しないため無効化する
    /// (validateMenuItem 側で判定)。
    @objc func find(_ sender: Any?) {
        guard let webView = webViewProxy.webView, !webViewProxy.isDirectHTMLMode else { return }
        webView.evaluateJavaScript(ViewerBridge.openFindScript)
    }
```

- [ ] **Step 2: `validateMenuItem` に無効化条件を追加する**

`BefoldApp/befold/App/ViewerWindowController.swift` の `validateMenuItem(_:)`(459-473行目)に分岐を追加する。

```swift
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSourceView(_:)) {
            menuItem.title = isSourceMode
                ? String(localized: "menu.view.showRendered", bundle: .l10n)
                : String(localized: "menu.view.toggleSource", bundle: .l10n)
            return canToggleSourceMode
        }
        if menuItem.action == #selector(toggleLineNumbers(_:)) {
            menuItem.title = store.showLineNumbers
                ? String(localized: "menu.view.hideLineNumbers", bundle: .l10n)
                : String(localized: "menu.view.showLineNumbers", bundle: .l10n)
            return store.showsCodeContent
        }
        if menuItem.action == #selector(find(_:)) {
            return !webViewProxy.isDirectHTMLMode
        }
        return true
    }
```

- [ ] **Step 3: `MainMenuBuilder` の Edit メニューに「検索…」を追加する**

`BefoldApp/befold/App/MainMenuBuilder.swift` の `makeEditMenuItem()`(106-148行目)、`selectAll` 項目(142-146行目)の直後、`return item`(147行目)の手前に追加する。

```swift
        menu.addItem(
            withTitle: String(localized: "menu.edit.selectAll", bundle: .l10n),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.edit.find", bundle: .l10n),
            action: #selector(ViewerWindowController.find(_:)),
            keyEquivalent: "f"
        )
        return item
```

- [ ] **Step 4: ローカライズ文字列を追加する**

`BefoldApp/befold/Resources/Localizable.xcstrings` に `menu.edit.find` キーを追加する。既存の `menu.edit.selectAll` エントリ(`"strings"` 直下)の直後にキーを追加する形で、以下の JSON 断片を該当箇所に挿入する。

```json
    "menu.edit.find" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Find…"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "検索…"
          }
        }
      }
    },
```

- [ ] **Step 5: ビルドとテストが通ることを確認する**

Run: `cd BefoldApp && swift build && swift test`
Expected: ビルド成功・全テスト PASS

- [ ] **Step 6: 手動テストでメニュー配線を確認する**

Run: `cd BefoldApp && xcodegen generate && xcodebuild build -scheme befold`
Expected: ビルド成功

アプリを起動し以下を確認する:
- Edit メニューに「検索…」(Cmd+F)が表示され、選択するとプレビュー右上に検索バーが開く
- `.html` ファイルを開いて直接プレビュー表示している間は、Edit メニューの「検索…」がグレーアウトして無効になっている
- 大文字小文字区別・単語マッチ・正規表現のいずれかのトグルを ON にした状態でアプリを再起動しても、トグルの ON 状態が保持されている
- 複数ウィンドウを開いている状態で一方のトグルを変更しても既存動作(既存メニュー等)に影響しない(新規ウィンドウには最新のトグル状態が反映される)

- [ ] **Step 7: コミット**

```bash
git add BefoldApp/befold/App/ViewerWindowController.swift BefoldApp/befold/App/MainMenuBuilder.swift \
  BefoldApp/befold/Resources/Localizable.xcstrings
git commit -m "feat: Cmd+F で検索バーを開くメニュー配線を追加する

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 6: 最終的な手動検証(仕上げ)

**Files:** なし(検証のみ)

- [ ] **Step 1: 全自動テストを実行する**

Run: `cd BefoldApp && swift test`
Expected: 全テスト PASS

- [ ] **Step 2: quality-loop で規約準拠を確認する**

Run: `/quality-loop`(プロジェクトの品質チェックスキル。SwiftLint 等の既存規約違反がないか確認する)
Expected: 違反なし、または指摘があれば修正してから次へ進む

- [ ] **Step 3: アプリを起動し、設計書のテスト計画を通しで手動確認する**

Run: `cd BefoldApp && xcodegen generate && xcodebuild build -scheme befold`(または `/run` スキル)

`docs/superpowers/specs/2026-07-10-inline-search-design.md` のテスト計画に沿って以下を通しで確認する:

- Cmd+F でのバー表示・Esc/×での終了
- 大文字小文字・単語マッチ・正規表現それぞれの ON/OFF での検索結果の変化
- Enter/Shift+Enter・前後ボタンでの循環ナビゲーション(最後の一致から次へ進むと最初に戻る)
- ソース⇄レンダリング表示切替時、開いたままの検索バーが新しい DOM に追従する
- 外部エディタでファイルを変更し、ライブリロード中も検索状態(クエリ・ハイライト・件数)が保たれる
- `.html` ファイル直接表示中の Cmd+F 無効化(メニューがグレーアウト)
- 画像/PDF 表示時に検索すると「見つかりません」が表示される(クラッシュしない)
- アプリ再起動後もトグル(大文字小文字・単語マッチ・正規表現)の ON/OFF が保持されている

- [ ] **Step 4: 未コミットの変更がないことを確認する**

Run: `git status`
Expected: `nothing to commit, working tree clean`(Task 1〜5 で各タスクをコミット済みのため)
