# モード切替時の検索状態リフレッシュ Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** レンダリング⇔ソース表示モード切替の際、開いている検索バーの件数・ハイライトが新しい DOM に対して自動的に再計算され、常に1件目のマッチへ位置がリセットされるようにする。

**Architecture:** `viewer.html` の `_mmdFindRefresh()` に `resetToFirst` 引数を追加し、`setViewMode()` がモード変更を検知したフラグを `render()` / `_renderSource()` の末尾で消費する。Swift 側（`ViewerWebView.swift` 等）の変更は不要。

**Tech Stack:** 素の JavaScript（`BefoldApp/befold/Resources/viewer.html` 内のインラインスクリプト）。

## Global Constraints

- 検索クエリ文字列・大文字小文字区別/単語単位/正規表現の3トグルはモード切替でリセットしない（`_mmdFindOptions` / `_mmdFindQuery` に触れない）。
- 検索バーはモード切替前後で開いたまま維持する（閉じない）。
- 同一モード内でのファイル内容更新（ライブリロード）時の「現在位置をできるだけ維持する」既存挙動は変更しない。
- この機能は `viewer.html` インラインスクリプト内で完結し、DOM (`document`, `window.webkit` 等) に依存するため Jest 単体テストの対象外（プロジェクト規約: WebView/GUI 層は自動テスト対象外、手動確認のみ）。既存の `__tests__/viewer.test.js` は `viewer.js` からエクスポートされた純粋関数のみを対象としており、本変更はそこに新規テストを追加しない。

---

## Task 1: `_mmdFindRefresh()` に `resetToFirst` 引数を追加する

**Files:**
- Modify: `BefoldApp/befold/Resources/viewer.html:610-620`

**Interfaces:**
- Consumes: なし（既存のモジュール内変数 `_mmdFindCurrentIndex`, `_mmdFindMatches` と既存関数 `_mmdFindRun()`, `_mmdFindHighlightCurrent()`, `_mmdFindUpdateCount()` をそのまま使う）
- Produces: `_mmdFindRefresh(resetToFirst)` — `resetToFirst` が truthy なら新しいマッチ集合の1件目（インデックス0）に位置を合わせる。falsy または省略時は従来どおり直前のインデックス番号をできるだけ維持する。Task 2, 3 で呼び出す。

- [ ] **Step 1: 現在の実装を確認する**

```bash
sed -n '605,621p' BefoldApp/befold/Resources/viewer.html
```

期待される現状の内容:

```js
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
```

- [ ] **Step 2: `resetToFirst` 引数を追加する**

`BefoldApp/befold/Resources/viewer.html:610-620` を以下に置き換える:

```js
// render() / _renderSource() の末尾から呼ばれる: バーが開いていれば
// 同じクエリ・トグルのまま新しい DOM に対して再検索する。
// resetToFirst が真の場合は1件目に位置をリセットする(モード切替時: レンダリング結果と
// ソースコードとで DOM 構造に連続性がないため、位置維持に意味がない)。
// 省略時は可能な限り現在位置を維持する(ライブリロード追従)。
function _mmdFindRefresh(resetToFirst) {
  var previousIndex = resetToFirst ? 0 : _mmdFindCurrentIndex;
  _mmdFindRun();
  if (_mmdFindMatches.length > 0) {
    _mmdFindCurrentIndex = Math.min(Math.max(previousIndex, 0), _mmdFindMatches.length - 1);
    _mmdFindHighlightCurrent();
    _mmdFindUpdateCount();
  }
}
```

- [ ] **Step 3: 既存呼び出し元(`render()`末尾)が壊れていないことを確認する**

```bash
grep -n "_mmdFindRefresh()" BefoldApp/befold/Resources/viewer.html
```

期待: `viewer.html:826` あたりに `if (_mmdFindIsOpen()) { _mmdFindRefresh(); }` が変更されずに残っている(引数なし呼び出しなので `resetToFirst` は `undefined` = falsy、従来どおり位置維持)。この時点ではまだ Task 2/3 未着手のため、この行は次のタスクで書き換える。

- [ ] **Step 4: コミット**

```bash
git add BefoldApp/befold/Resources/viewer.html
git commit -m "feat: _mmdFindRefresh に resetToFirst 引数を追加する"
```

---

## Task 2: モード切替検出フラグを `setViewMode()` に追加する

**Files:**
- Modify: `BefoldApp/befold/Resources/viewer.html:684` (変数宣言部)
- Modify: `BefoldApp/befold/Resources/viewer.html:848-851` (`setViewMode` 本体)

**Interfaces:**
- Consumes: 既存のモジュール内変数 `_viewMode`(`viewer.html:684`)
- Produces: モジュール内変数 `_mmdModeJustSwitched`(初期値 `false`)。`setViewMode(mode)` は、渡された `mode` が現在の `_viewMode` と異なるときだけ `_mmdModeJustSwitched = true` をセットしてから `_viewMode` を更新する。Task 3 で `render()` / `_renderSource()` から読み取り、消費後に `false` へ戻す。

- [ ] **Step 1: 現在の実装を確認する**

```bash
sed -n '680,686p;845,852p' BefoldApp/befold/Resources/viewer.html
```

期待される現状:

```js
var _viewMode = 'rendered';
```

```js
// モードを切り替えるだけで再描画はしない: 呼び出し側(Swift)が
// 常にこの直後に render() を送るため、ここで再描画すると
// 古い内容による二重描画が発生する。
function setViewMode(mode) {
  if (mode !== 'rendered' && mode !== 'source') return;
  _viewMode = mode;
}
```

- [ ] **Step 2: `_mmdModeJustSwitched` 変数を宣言する**

`BefoldApp/befold/Resources/viewer.html:684` の `var _viewMode = 'rendered';` の直後に1行追加する:

```js
var _viewMode = 'rendered';
// setViewMode() が直前と異なるモードを検知したら true になり、
// render()/_renderSource() が検索リフレッシュ(先頭リセット)に使った後 false へ戻す。
var _mmdModeJustSwitched = false;
```

- [ ] **Step 3: `setViewMode()` でモード変更を検知する**

`BefoldApp/befold/Resources/viewer.html:848-851` の `setViewMode` を以下に置き換える:

```js
function setViewMode(mode) {
  if (mode !== 'rendered' && mode !== 'source') return;
  if (mode !== _viewMode) {
    _mmdModeJustSwitched = true;
  }
  _viewMode = mode;
}
```

- [ ] **Step 4: コミット**

```bash
git add BefoldApp/befold/Resources/viewer.html
git commit -m "feat: setViewMode にモード切替検出フラグを追加する"
```

---

## Task 3: `render()` と `_renderSource()` でモード切替フラグを消費する

**Files:**
- Modify: `BefoldApp/befold/Resources/viewer.html:826` (`render()` 末尾)
- Modify: `BefoldApp/befold/Resources/viewer.html:830-843` (`_renderSource()`)

**Interfaces:**
- Consumes: `_mmdFindRefresh(resetToFirst)`(Task 1)、`_mmdModeJustSwitched`(Task 2)、既存の `_mmdFindIsOpen()`
- Produces: なし(末端タスク)。両モードで検索バーが開いていれば新しい DOM に対して再検索し、モード切替時のみ1件目へ位置をリセットする。

- [ ] **Step 1: 現在の実装を確認する**

```bash
sed -n '824,843p' BefoldApp/befold/Resources/viewer.html
```

期待される現状:

```js
    _annotatePathRefs();
    if (_mmdFindIsOpen()) { _mmdFindRefresh(); }
    _mmdApplyZoom();
  }

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

- [ ] **Step 2: `render()` 末尾を書き換える**

`BefoldApp/befold/Resources/viewer.html:826` の1行を以下に置き換える:

```js
    _annotatePathRefs();
    if (_mmdFindIsOpen()) { _mmdFindRefresh(_mmdModeJustSwitched); }
    _mmdModeJustSwitched = false;
    _mmdApplyZoom();
```

- [ ] **Step 3: `_renderSource()` に検索リフレッシュを追加する**

`BefoldApp/befold/Resources/viewer.html:830-843` の `_renderSource` を以下に置き換える:

```js
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
    if (_mmdFindIsOpen()) { _mmdFindRefresh(_mmdModeJustSwitched); }
    _mmdModeJustSwitched = false;
    _mmdApplyZoom();
  }
```

- [ ] **Step 4: 既存の Jest テストが壊れていないことを確認する**

```bash
cd BefoldApp/befold/Resources && npx jest
```

期待: 全テスト PASS(この変更はインラインスクリプトのみで `viewer.js` のエクスポート関数に触れていないため、既存の `__tests__/viewer.test.js` の結果に影響しない)。

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/Resources/viewer.html
git commit -m "fix: モード切替時に検索状態を再計算し先頭マッチへリセットする"
```

- [ ] **Step 6: 手動確認**

`/webview-smoke` スキル、または以下の手順で手動確認する:

```bash
cd BefoldApp && swift build
```

ビルドしたアプリで Mermaid を含む `.md` ファイルを開き、以下を確認する:

1. Cmd+F で検索バーを開き、複数ヒットするクエリを入力する。件数表示(`n/total`)とハイライトが出ることを確認する。
2. レンダリング表示からソース表示へ切り替える(トグルボタンまたはメニュー)。件数表示が新しい DOM(ソースコード)に対する件数に更新され、1件目のマッチへハイライト・スクロールしていることを確認する。
3. ソース表示からレンダリング表示へ戻す。同様に件数が更新され、1件目のマッチへリセットされていることを確認する。
4. 検索バーのクエリ文字列、および大文字小文字区別/単語単位/正規表現のトグル状態が、モード切替の前後で変わっていないことを確認する。
5. 検索バーを開いたまま、外部でファイルを編集して保存する(ライブリロード)。現在位置ができるだけ維持される既存挙動(先頭に飛ばない)が壊れていないことを確認する。
6. 検索バーが閉じている状態でモード切替を行っても、エラーや不具合が発生しないことを確認する(`_mmdFindIsOpen()` が false のため `_mmdFindRefresh` は呼ばれない)。

---
