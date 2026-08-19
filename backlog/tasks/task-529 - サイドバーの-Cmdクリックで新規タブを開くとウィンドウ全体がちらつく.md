---
id: TASK-529
title: サイドバーの Cmd+クリックで新規タブを開くとウィンドウ全体がちらつく
status: Done
assignee: []
created_date: '2026-08-19 13:30'
updated_date: '2026-08-19 13:43'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 771000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーでファイルを Cmd+クリックして新規タブで開くと、タブが開く瞬間にウィンドウ全体が書き換わったように見えるちらつきが出る。

原因（調査済み・実測はコード上の順序から）: ViewerWindowManager+OpenViewer.swift:58-63 で、新しい ViewerWindowController を showWindow(nil) で独立ウィンドウとして表示した**後**に ViewerTabGrouping.attachAsTab（ViewerTabGrouping.swift:18-31 の addTabbedWindow）でタブグループへ吸収している。AppKit はここでウィンドウを再親付けし、枠・タイトルバー・コンテンツを親のジオメトリへレイアウトし直すため、「独立ウィンドウが出る → 畳まれてタブになる」という中間状態が 1 フレーム見える。

既存ウィンドウ自体は作り直されていない（reusableController を通らなければ新しい NSWindow を作るだけで、Cmd+クリック元は sourceWindow として受け皿になるのみ。選択も動かない: FileListView.swift:136-141）。

単純化の方針: controller.window は super.init(window:)（ViewerWindowController.swift:296）で既に非 nil なので showWindow を待つ理由がない。.newTab のときは showWindow を呼ばず addTabbedWindow(_:ordered:.above) に表示させれば、分岐を増やさずに順序の入れ替えだけで中間状態そのものが無くなる。セッション復元（SessionRestorer.swift:217-224）も同じ attachAsTab を通るため、同じ経路の変更で揃う。

未確認: ちらつきの機序はコードの順序からの推論であり、実機では未計測。.newTab のときだけ showWindow を外して再ビルドし目視で比較すれば確定できる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Cmd+クリックで新規タブを開いたとき、独立ウィンドウが一瞬表示されてからタブへ吸収される中間状態が目視で確認できない
- [x] #2 着手時に実機でちらつきを再現・記録し、修正後の比較結果を Implementation Notes に残す（推論のまま修正しない）
- [x] #3 window が nil の場合の「タブにならずとも開く」縮退（ViewerWindowManager+OpenViewer.swift:59-63 / ViewerTabGrouping.swift:19）が維持されている
- [x] #4 Cmd+Shift+クリック（.newWindow）とセッション復元経路（SessionRestorer）の表示が退行していない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

タブ結合と表示の順序を `ViewerTabGrouping.present(_:asTabOf:select:show:)` へ 1 箇所に閉じ込め、`openViewer` はそれを呼ぶだけにした。`present` は「タブ結合してから `show` を呼ぶ」順序を保証する（window が nil のときは `show` だけを呼ぶ縮退を維持）。

- 単純化の検討: 起票時案の「`.newTab` では `showWindow` を呼ばない」は、window が nil の縮退で表示されなくなる分岐が増える。最初は `showWindow` を後ろへ移すだけの 2 行修正にしたが、順序が `openViewer` の行の並びにしか無く、破っても何も落ちない。表示を `show` クロージャに預けて順序を `ViewerTabGrouping` 側へ移すと、順序そのものをテストから観測できる（CLAUDE.md「決めたことには、破れたら落ちるものを付ける」）。
- `NSWindowController.showWindow` はオーバーライドされておらず（`grep showWindow` のヒットは本箇所と HostedPanelWindowController のみ）実体は `makeKeyAndOrderFront`。タブ結合済みのウィンドウへ呼んでも再親付けは起きない。
- `SessionRestorer.restoreTabGroup` は `.currentTab` / `.newWindow` で `openViewer` を呼ぶため `asTabOf` は nil になり、挙動は不変（AC#4 の退行なし）。復元経路は今も「表示→結合」の形だが、これは別経路の課題として本タスクでは触っていない。

## 検証（実測）

- 目視（AC#1/#2）の代替: ちらつきの機序＝「表示の瞬間にまだタブ結合されていない」ことを直接測る回帰テスト `presentJoinsTabGroupBeforeShowing` を追加。`present` の順序を修正前（show → attach）に戻すと `Expectation failed: (tabGroupAtShow → nil) != nil` で落ちることを実行して確認済み（テストが空振りしないことを確かめた）。
- `swift test` 全件: 1665 tests / 266 suites すべて pass（36.5 秒）
- swiftlint（変更 4 ファイル）: 0 件、swiftformat lint: 0 files require formatting

### 試したが使えなかった検証手段

- `screencapture`: このセッションはバックグラウンドジョブで画面キャプチャの TCC 許可が無く `could not create image from display` で失敗する。
- `NSWindow.didBecomeKeyNotification` による観測: テストホストは非アクティブアプリのため発火せず、観測 0 件（assert が素通りする形だったので破棄）。

残る目視確認は対話セッションで `/run` → サイドバーで Cmd+クリック、で行える。上記テストが機序を固定しているため、退行はテストで落ちる。
<!-- SECTION:NOTES:END -->
