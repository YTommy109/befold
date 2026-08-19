---
id: TASK-529
title: サイドバーの Cmd+クリックで新規タブを開くとウィンドウ全体がちらつく
status: To Do
assignee: []
created_date: '2026-08-19 13:30'
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
- [ ] #1 Cmd+クリックで新規タブを開いたとき、独立ウィンドウが一瞬表示されてからタブへ吸収される中間状態が目視で確認できない
- [ ] #2 着手時に実機でちらつきを再現・記録し、修正後の比較結果を Implementation Notes に残す（推論のまま修正しない）
- [ ] #3 window が nil の場合の「タブにならずとも開く」縮退（ViewerWindowManager+OpenViewer.swift:59-63 / ViewerTabGrouping.swift:19）が維持されている
- [ ] #4 Cmd+Shift+クリック（.newWindow）とセッション復元経路（SessionRestorer）の表示が退行していない
<!-- AC:END -->
