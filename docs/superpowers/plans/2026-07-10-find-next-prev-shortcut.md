# 検索結果の前後移動ショートカット（⌘G / ⌘Shift+G）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Edit メニューに「次を検索」(⌘G) / 「前を検索」(⌘Shift+G) を追加し、検索バーが開いている間はフォーカス位置に関わらずウィンドウ全体で検索結果の前後移動ができるようにする。

**Architecture:** 既存の `⌘F`（`ViewerWindowController.find(_:)` → `ViewerBridge.openFindScript` → JS `_mmdOpenFind()`）と同じ Swift→JS ブリッジのパターンを踏襲する。開閉状態の単一ソースは JS 側の `_mmdFindIsOpenFlag`（`_mmdFindIsOpen()`）のままとし、Swift 側に新しい状態は追加しない。

**Tech Stack:** Swift 6 / AppKit（メニュー・`NSMenuItem.keyEquivalentModifierMask`）、WKWebView 上の JavaScript（`viewer.html`）。

## Global Constraints

- WebView/GUI 層はプロジェクト規約により自動テスト対象外。検証は実機ビルド＋手動確認で行う（`.claude/CLAUDE.md` テスト規約）。
- コミットメッセージは Conventional Commits + 日本語（例: `feat: 検索結果の前後移動に ⌘G / ⌘Shift+G を追加する`）。
- 関連する作業は `git commit --amend --no-edit` でまとめる（未 push の間のみ）。本プランのタスクは全て同一機能のため、Task 1 でコミットした後の Task 2〜4 は amend で積み重ねる。

---

### Task 1: viewer.html に開閉ガード付きラッパー関数を追加する

**Files:**
- Modify: `BefoldApp/befold/Resources/viewer.html:471-491`（`_mmdFindIsOpen` 〜 `_mmdCloseFind` の直後に追記）

**Interfaces:**
- Consumes: 既存の `_mmdFindIsOpen()`（`viewer.html:471`）、`_mmdFindNext()`（`viewer.html:625`）、`_mmdFindPrev()`（`viewer.html:632`）
- Produces: グローバル関数 `_mmdFindNextIfOpen()` / `_mmdFindPrevIfOpen()`（引数なし、戻り値なし）。Task 2 の Swift 側スクリプト定数がこれを文字列で呼び出す。

- [ ] **Step 1: `_mmdCloseFind()` の直後に2つのラッパー関数を追加する**

`BefoldApp/befold/Resources/viewer.html:485-491` は以下の内容:

```js
  function _mmdCloseFind() {
    _mmdFindIsOpenFlag = false;
    document.getElementById('mmd-find-bar').style.display = 'none';
    _mmdFindClearMarks();
    _mmdFindMatches = [];
    _mmdFindCurrentIndex = -1;
  }
```

この直後（492行目、次の空行の前）に追記する:

```js
  // ⌘G / ⌘Shift+G から呼ばれる。検索バーが閉じている間は何もしない
  // (フォーカス位置に関わらずグローバルショートカットとして配線されるため、
  // 呼び出し側では開閉判定をせずここで一元的にガードする)。
  function _mmdFindNextIfOpen() {
    if (!_mmdFindIsOpen()) return;
    _mmdFindNext();
  }

  function _mmdFindPrevIfOpen() {
    if (!_mmdFindIsOpen()) return;
    _mmdFindPrev();
  }
```

- [ ] **Step 2: ブラウザ／WebView 上での動作確認は Task 4 でまとめて行うため、ここではファイル保存のみ**

このタスク単体では実行環境がないため、構文が正しいことは次の Step で `node --check` を使って確認する。

- [ ] **Step 3: JS 構文チェック**

Run: `node --check BefoldApp/befold/Resources/viewer.html 2>&1 || true`

`viewer.html` は HTML ファイルなので `node --check` はそのままでは使えない。代わりに `<script>` タグ内身を抽出して確認する:

Run:
```bash
awk '/<script>/{flag=1;next}/<\/script>/{flag=0}flag' BefoldApp/befold/Resources/viewer.html > /tmp/viewer_script_check.js && node --check /tmp/viewer_script_check.js
```

Expected: 出力なし（構文エラーなしなら `node --check` は何も出力せず終了コード0）。

- [ ] **Step 4: コミット**

```bash
git add BefoldApp/befold/Resources/viewer.html
git commit -m "feat: 検索結果の前後移動に ⌘G / ⌘Shift+G を追加する"
```

---

### Task 2: ViewerBridge にスクリプト定数を追加し、ViewerWindowController に findNext/findPrevious を追加する

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerBridge.swift:67-68`
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift:413-419`（`find(_:)` の直後）、`472-489`（`validateMenuItem(_:)`）

**Interfaces:**
- Consumes: Task 1 の JS 関数 `_mmdFindNextIfOpen()` / `_mmdFindPrevIfOpen()`
- Produces: `ViewerBridge.findNextScript: String`, `ViewerBridge.findPrevScript: String`、`ViewerWindowController.findNext(_:)`, `ViewerWindowController.findPrevious(_:)`（`@objc`、Task 3 のメニュー項目の `action` セレクタとして使用）

- [ ] **Step 1: ViewerBridge.swift にスクリプト定数を追加する**

`BefoldApp/befold/Viewer/ViewerBridge.swift:67-68` は以下:

```swift
    /// 検索バーを開く(未オープンなら表示してフォーカス)スクリプト。
    static let openFindScript = "_mmdOpenFind()"
```

この直後に追記する:

```swift

    /// 次のマッチへ移動するスクリプト。検索バーが閉じている間は JS 側で無視される。
    static let findNextScript = "_mmdFindNextIfOpen()"

    /// 前のマッチへ移動するスクリプト。検索バーが閉じている間は JS 側で無視される。
    static let findPrevScript = "_mmdFindPrevIfOpen()"
```

- [ ] **Step 2: ViewerWindowController.swift に findNext / findPrevious を追加する**

`BefoldApp/befold/App/ViewerWindowController.swift:413-419` は以下:

```swift
    /// Edit > 検索…。プレビュー右上の検索バーを開く。
    /// HTML ファイルの直接ロード表示中は viewer.html の JS が存在しないため無効化する
    /// (validateMenuItem 側で判定)。
    @objc func find(_ sender: Any?) {
        guard let webView = webViewProxy.webView, !webViewProxy.isDirectHTMLMode else { return }
        webView.evaluateJavaScript(ViewerBridge.openFindScript)
    }
```

この直後（420行目、次の空行の前）に追記する:

```swift

    /// Edit > 次を検索。検索バーが開いている間のみ JS 側で処理される。
    @objc func findNext(_ sender: Any?) {
        guard let webView = webViewProxy.webView, !webViewProxy.isDirectHTMLMode else { return }
        webView.evaluateJavaScript(ViewerBridge.findNextScript)
    }

    /// Edit > 前を検索。検索バーが開いている間のみ JS 側で処理される。
    @objc func findPrevious(_ sender: Any?) {
        guard let webView = webViewProxy.webView, !webViewProxy.isDirectHTMLMode else { return }
        webView.evaluateJavaScript(ViewerBridge.findPrevScript)
    }
```

- [ ] **Step 3: validateMenuItem に findNext / findPrevious の判定を追加する**

`BefoldApp/befold/App/ViewerWindowController.swift:485-488` は以下:

```swift
        if menuItem.action == #selector(find(_:)) {
            return !webViewProxy.isDirectHTMLMode
        }
        return true
```

以下に置き換える:

```swift
        if menuItem.action == #selector(find(_:)) {
            return !webViewProxy.isDirectHTMLMode
        }
        if menuItem.action == #selector(findNext(_:)) || menuItem.action == #selector(findPrevious(_:)) {
            return !webViewProxy.isDirectHTMLMode
        }
        return true
```

- [ ] **Step 4: ビルドして構文・型エラーがないことを確認する**

Run: `cd BefoldApp && xcodebuild build -scheme befold -configuration Debug -derivedDataPath .build/xcode -quiet`

Expected: ビルド成功（エラー出力なし）。この時点ではメニュー項目がまだ無いため実行時には呼ばれないが、コンパイルが通ることを確認する。

- [ ] **Step 5: コミット（Task 1 に amend で積み上げる）**

```bash
git add BefoldApp/befold/Viewer/ViewerBridge.swift BefoldApp/befold/App/ViewerWindowController.swift
git commit --amend --no-edit
```

---

### Task 3: MainMenuBuilder にメニュー項目を追加し、Localizable.xcstrings にキーを追加する

**Files:**
- Modify: `BefoldApp/befold/App/MainMenuBuilder.swift:147-152`
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings:158-174`

**Interfaces:**
- Consumes: `ViewerWindowController.findNext(_:)` / `ViewerWindowController.findPrevious(_:)`（Task 2 で追加済み）
- Produces: なし（UI 末端）

- [ ] **Step 1: Localizable.xcstrings にキーを追加する**

`BefoldApp/befold/Resources/Localizable.xcstrings:158-174` は以下:

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

この直後（175行目、`"menu.view.title"` の前）に追記する:

```json
    "menu.edit.findNext" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Find Next"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "次を検索"
          }
        }
      }
    },
    "menu.edit.findPrevious" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Find Previous"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "前を検索"
          }
        }
      }
    },
```

- [ ] **Step 2: JSON の妥当性を確認する**

Run: `python3 -c "import json; json.load(open('BefoldApp/befold/Resources/Localizable.xcstrings'))"`

Expected: エラーなし（出力なしで終了コード0）。

- [ ] **Step 3: MainMenuBuilder.swift にメニュー項目を追加する**

`BefoldApp/befold/App/MainMenuBuilder.swift:147-152` は以下:

```swift
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.edit.find", bundle: .l10n),
            action: #selector(ViewerWindowController.find(_:)),
            keyEquivalent: "f"
        )
        return item
    }
```

以下に置き換える:

```swift
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.edit.find", bundle: .l10n),
            action: #selector(ViewerWindowController.find(_:)),
            keyEquivalent: "f"
        )
        menu.addItem(
            withTitle: String(localized: "menu.edit.findNext", bundle: .l10n),
            action: #selector(ViewerWindowController.findNext(_:)),
            keyEquivalent: "g"
        )
        let findPrevious = menu.addItem(
            withTitle: String(localized: "menu.edit.findPrevious", bundle: .l10n),
            action: #selector(ViewerWindowController.findPrevious(_:)),
            keyEquivalent: "g"
        )
        findPrevious.keyEquivalentModifierMask = [.command, .shift]
        return item
    }
```

- [ ] **Step 4: xcodegen + ビルド**

Run: `cd BefoldApp && xcodegen generate && xcodebuild build -scheme befold -configuration Debug -derivedDataPath .build/xcode -quiet`

Expected: ビルド成功（エラー出力なし）。

- [ ] **Step 5: コミット（Task 1 に amend で積み上げる）**

```bash
git add BefoldApp/befold/App/MainMenuBuilder.swift BefoldApp/befold/Resources/Localizable.xcstrings
git commit --amend --no-edit
```

---

### Task 4: 実機での手動確認

**Files:** なし（検証のみ）

**Interfaces:**
- Consumes: Task 1〜3 の全成果物
- Produces: なし

- [ ] **Step 1: アプリを起動する**

Run:
```bash
pkill -x befold 2>/dev/null
open /Users/tokutomi/.warp/worktrees/behold/mogote-switchback/BefoldApp/.build/xcode/Build/Products/Debug/befold.app
```

- [ ] **Step 2: 検索バーが閉じている状態で `⌘G` / `⌘Shift+G` を押しても何も起きないことを確認する**

Mermaid または Markdown ファイルを開き、検索バーを開かずに `⌘G` と `⌘Shift+G` を押す。表示内容・フォーカスに変化がないこと。Edit メニューを開き、「次を検索」「前を検索」がグレーアウトしていることも確認する。

- [ ] **Step 3: 検索バーを開いた状態で前後移動が動くことを確認する**

`⌘F` で検索バーを開き、複数マッチする語を入力する。検索フィールド外（プレビュー領域）をクリックしてフォーカスを外した状態で `⌘G` を押し、次のマッチへ移動すること。続けて `⌘Shift+G` を押し、前のマッチへ戻ることを確認する。

- [ ] **Step 4: HTML 直接表示モードでの無効化を確認する**

`.html` ファイルを直接開き（`isDirectHTMLMode`）、Edit メニューの「検索…」「次を検索」「前を検索」がすべてグレーアウトしていることを確認する。

- [ ] **Step 5: 前回修正（IME Enter 確定）とのリグレッションがないことを確認する**

検索フィールドで日本語入力→変換→Enter で確定してもマッチ移動しないこと（既存の修正が壊れていないこと）を再確認する。

- [ ] **Step 6: 最終コミット状態を確認する**

Run: `git log --oneline -3 && git status`

Expected: Task 1〜3 の変更が1コミットにまとまっていること（amend 済み）。作業ツリーがクリーンであること。
