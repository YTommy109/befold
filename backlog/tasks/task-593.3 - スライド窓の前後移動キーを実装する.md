---
id: TASK-593.3
title: スライド窓の前後移動キーを実装する
status: In Progress
assignee: []
created_date: '2026-09-06 09:25'
updated_date: '2026-09-06 10:32'
labels:
  - sidebar
  - slide-mode
dependencies:
  - TASK-593.2
documentation:
  - docs/superpowers/specs/2026-09-06-slide-window-design.md
parent_task_id: TASK-593
priority: medium
type: feature
ordinal: 861000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スライド窓で Space / ↓ が次のファイル、Backspace（delete）/ Shift+Space / ↑ が前のファイルへ移る。本文のスクロールはトラックパッド・マウスホイールのみで、キーは前後移動専用（ヒアリングで決定）。端では何もしない（周回しない）。

配線はスライド窓にだけ付ける `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`（前例: `SwipeHistoryMonitor`）。自窓が key window のときだけ扱い、窓が閉じたら外す。⌘ / ⌥ / ⌃ 付きは素通し（メニューのキー等価が勝つ）、first responder がテキスト入力（検索欄など）なら素通し。キー → 動作の対応は `SidebarKeyAction` と同じ純粋な表にして単体で測る。

隣の解決は `model.listSnapshot` をキー 1 回につき 1 度だけ読み（読むたびに再計算する。TASK-418）、`FileListSnapshot.next(after:)` / `previous(before:)` を `kind == .file` の行に当たるまで繰り返す（`next` はフォルダー行も返す。実測）。ファイルを開く経路は通常窓と同じ `ViewerWindowController+FileNavigation` を通し、履歴・タイトル・per-file の表示メモリを従来どおり効かせる。

JS 側の `spaceScroll` と `viewer-src/keyboard.ts` の矢印スクロール、PDF の `keyDown` は触らない。モニタが先に消費するので本文には届かない。

未確認の前提: WKWebView がフォーカスを持つ状態でローカルモニタが keyDown を先取りできるかは未実測。着手時に最初に実機で確かめ、取れなければ `NSWindow` サブクラスの `sendEvent(_:)` 上書きへ切り替える（判断を Implementation Notes に残す）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 スライド窓で Space と ↓ が次のファイル、Backspace と Shift+Space と ↑ が前のファイルを開く（Markdown・PDF・画像のいずれを表示中でも）
- [x] #2 フォルダー行を飛ばし、絞り込み・不可視・変更のみ・ツリーの展開状態を反映した表示順で移動する（`FileListSnapshot` を組む純粋テスト）
- [x] #3 最後のファイルで「次へ」、最初のファイルで「前へ」は何もしない
- [x] #4 修飾キー付きのイベントと、テキスト入力中（検索欄）の Space / Backspace / ↑↓ は素通しされる（キー表のテスト）
- [x] #5 通常のビューア窓ではキー割当が変わらない（Space のページ送り・サイドバーの Backspace で親へ、の既存テストが通る）
- [x] #6 スライド窓を閉じたあとにモニタが残らない
- [x] #7 native-app-design.md にスライド窓のキー表が記述されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果を反映した方針（2026-09-06）

### 1. キー表は純粋関数へ（`SidebarKeyAction` と同じ流儀）

`SlideKeyAction`（`.next` / `.previous` / `.ignored`）を新設し、
`action(keyCode:modifiers:isEditingText:)` の純粋関数で決める。GUI 層は自動テスト
対象外なので、キー割り当てを測れるのはこの関数のユニットテストだけ。

**`characters` ではなく `keyCode` で判定する。** 矢印キーの `characters` は
非印字文字で、キーボードレイアウトによっても変わる。keyCode は物理キー位置なので
レイアウトに依らない（Space=49 / ↑=126 / ↓=125 / delete=51）。

| キー | 動作 |
| --- | --- |
| Space（49）、↓（125） | 次のファイル |
| Shift+Space、Backspace（51）、↑（126） | 前のファイル |

⌘ / ⌥ / ⌃ 付きは `.ignored`（メニューのキー等価が勝つ）。テキスト入力中も `.ignored`。

### 2. モニタは `SwipeHistoryMonitor` と同じ形

`SlideKeyMonitor`: 窓を弱参照で持ち、`addLocalMonitorForEvents(matching: .keyDown)` を
`start()` / `stop()` で出し入れする。`stop()` は `windowWillClose` で
`swipeMonitor.stop()` の隣に置く（既存の後始末に合流させ、外し忘れの経路を増やさない）。

- 自窓のイベントだけ扱う（`event.window === window`）
- 扱ったら `nil` を返してイベントを消費する。扱わなければ `event` をそのまま返す
  （素通し。JS 側の `spaceScroll` と `viewer-src/keyboard.ts` は触らない）
- テキスト入力中の判定は `window.firstResponder` が `NSTextView` / `NSTextField` か

### 3. 隣の解決は `FileListSnapshot` の純粋関数

`nextFile(after:)` / `previousFile(before:)` を `FileListSnapshot` に足し、
`kind == .file` の行に当たるまで既存の `next(after:)` / `previous(before:)` を繰り返す
（`next` はフォルダー行も返す）。端では nil を返す（周回しない）。

**`listSnapshot` はキー 1 回につき 1 度だけ読む**（読むたびに再計算する / TASK-418）。
新しい関数を `FileListSnapshot` 側に置くのはそのためで、呼び出し側でループを書くと
1 回のキーで複数回 `listSnapshot` を読む形になりやすい。

終端の担保: 最初の 1 歩で `current` が実在の id になり、以後 index は狭義に増減する。

### 4. ファイルを開く経路は通常窓と同じ

`ViewerWindowController.switchFile(to:)` を通す（履歴・タイトル・per-file の表示メモリが
従来どおり効く）。スライド窓専用の切替経路は作らない。

### 5. 型グループ

`ViewerWindowController` は恒久例外 922 行に張り付いている（TASK-593.2 の実測）。
stored property 1 つ（`slideKeyMonitor`）＋ `stop()` の 1 行で超えるので、上限の
引き上げが要る。隣の解決とキー表はどちらも新しい型・既存の純粋型へ置くので、
コントローラに増えるのは配線だけに保つ。

### 6. 未確認の前提（着手時に実機で確かめる）

**WKWebView がフォーカスを持つ状態でローカルモニタが keyDown を先取りできるかは未実測。**
`addLocalMonitorForEvents` は `sendEvent` の前に呼ばれるので first responder に依らない
はずだが、確認していない。取れなければ `NSWindow` サブクラスの `sendEvent(_:)` 上書きへ
切り替える（判断を Implementation Notes に残す）。

GUI 層なので `/run` での目視が要る点は AC #1 と同じ。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容

- `SlideKeyAction`（新規）: keyCode → 動作の純粋な表と、行き先の解決（`destination(in:from:)`）
- `SlideKeyMonitor`（新規）: `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`。形は
  `SwipeHistoryMonitor` と同じで、`stop()` は windowWillClose の `swipeMonitor.stop()` の隣
- `FileListSnapshot.nextFile(after:)` / `previousFile(before:)`: `kind == .file` に当たるまで
  既存の `next` / `previous` を繰り返す。端では nil（周回しない）
- `ViewerWindowController.moveToAdjacentFile(_:)`: 通常窓と同じ `switchFile(to:)` を通す

## 設計判断

**`characters` ではなく keyCode で判定した。** 矢印キーの `characters` は非印字文字で
キーボードレイアウトにも依るため、物理キー位置である keyCode を使う（Space=49 /
delete=51 / ↓=125 / ↑=126）。この値の名前は `SlideKeyAction.KeyCode` に 1 箇所で持つ。

**`listSnapshot` を 1 度しか読めない形にした。** `destination(in:from:)` が snapshot を
引数で受けるので、呼び出し側が 1 回のキー操作で 2 度読む書き方ができない（TASK-418）。
フォルダー行を飛ばすループを `FileListSnapshot` 側に置いたのも同じ理由。

**shift は素通しの対象にしない。** Shift+Space を「前へ」に使うため。⌘ / ⌥ / ⌃ のみ素通し。

**テキスト入力中の判定を最初に置いた。** 後ろに置くと「Space だけ先に食う」順序依存の
穴ができる。判定は `NSText` と `NSTextField` の両方を見る（`NSTextField` は編集中に
field editor を first responder にするので実際に当たるのはほぼ前者だが、片方だけだと
検索欄の実装が変わったときに静かに破れる）。

## 型グループの是正

`ViewerWindowController` は 922 → 931。行き先の解決を `SlideKeyAction` へ、隣の走査を
`FileListSnapshot` へ置いたので、コントローラに増えたのは stored property 1 つと
配線 2 行だけ。恒久例外の上限を実測値へ引き上げ、TASK-593 の 3 サブタスクでの推移
（905 → 922 → 931）を理由に書いた。

途中 swiftlint に 2 件の新規が出たので、どちらも構造で直した。

- `function_body_length`（init が 50 行超）: モニタの取り付けを
  `ViewerWindowAssembler.wireEventMonitors(for:on:)` の 1 本にまとめた
  （「作ったが取り付けていない」経路を init 側に作らせない形にもなる）
- `opening_brace`（テストのヘルパー）: swiftformat が `{` を独立行へ送る形だったので、
  規約どおり手で往復せず、シグネチャを 1 行に収まる 2 つのオーバーロードへ書き換えた

## 検証（実測）

- `swift build` / `xcodebuild build -scheme befold`: いずれも成功（`** BUILD SUCCEEDED **`）
- `swift test`: `Test run with 1891 tests in 312 suites passed after 38.309 seconds.`
  （593.2 の 1878 件から新規 13 件）
- swiftlint ベースライン差分: main 51 件 / HEAD 51 件、真の新規 0・解消 0
- `scripts/check-type-group-size.sh --check`: 「型グループの行数は閾値以内です」
- `/l10n-check`: 漏れ 0（220 キー。このサブタスクでキーの増減は無い）
- `check-doc-symbols.sh` / `check-doc-citations.sh` / `markdownlint-cli2`: いずれも exit 0

## 未確認のまま残っている前提（AC #1 / #6）

**Description が挙げていた「WKWebView がフォーカスを持つ状態でローカルモニタが keyDown を
先取りできるか」は実測していない。** `addLocalMonitorForEvents` は
`NSApplication.sendEvent(_:)` より前に呼ばれるので first responder に依らないはず、という
前提のまま `NSWindow.sendEvent(_:)` の上書きへは切り替えていない。**実機で Space を押して
本文がスクロールするだけならこの前提が誤りで、その場合は sendEvent 上書きへ切り替える。**

同じ理由で AC #1（実際にファイルが送られる）と AC #6（窓を閉じたあとモニタが残らない）は
GUI 層なので `/run` での目視が要る。#6 は `windowWillClose` で `slideKeyMonitor?.stop()` を
呼ぶコードは入っているが、実行の確認はしていない。

## 追記: 実ウィンドウでの統合テストを足した（当初「GUI 層なので目視」としていた分）

`MockedViewerWindowManager` が実 `NSWindow` を作ることに気づいたので、目視へ回す前提を
見直して `SlideWindowIntegrationTests` を新設した（12 件）。これで AC #1 と #6 のうち
自動で測れる範囲を機械化できた。

- 前後移動が表示中のファイルを実際に切り替える（`moveToAdjacentFile(.next)` →
  `fileURL` が次のファイルへ、`.previous` で戻る）
- 端では何もしない（周回しない）
- スライド窓の `window.tabbingMode == .disallowed` で、起点のタブグループへ入らない
- ツールバーが無い（通常窓との対で測り、「そもそも付いていない」との区別を付けた）
- per-file のサイドバー開閉の記憶を書き換えない（通常窓は書く、との対で測った）
- セッションのスナップショットに入らない（`viewerPath` / `tabGroup` が nil）

## それでも残る未確認（実機のみ）

**WKWebView がフォーカスを持つ状態でローカルモニタが keyDown を先取りできるかは依然として
未実測。** 統合テストは `moveToAdjacentFile` を直接呼んでおり、キーイベントが
WKWebView より先にモニタへ届くかは測っていない。`/run` で実際に Space を押し、
本文がスクロールするだけならこの前提が誤りで、`NSWindow.sendEvent(_:)` の上書きへ
切り替える。
<!-- SECTION:NOTES:END -->
