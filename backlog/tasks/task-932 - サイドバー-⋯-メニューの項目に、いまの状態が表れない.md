---
id: TASK-932
title: サイドバー ⋯ メニューの項目に、いまの状態が表れない
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-26T08:30:10Z'
labels: []
dependencies: []
references:
  - https://github.com/YTommy109/befold/issues/793
priority: high
type: bug
ordinal: 873000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
利用者の報告(GitHub #793)。サイドバーヘッダーの ⋯ メニューは、全項目(並び順の「フォルダーを先に」「名前順」と「不可視ファイルを表示」)の状態をチェックマークだけで示す設計だが、実機ではチェックマークが 1 つも描かれない。並び順は 2 択の両方が同じ見た目で並び、どちらが選ばれているか分からない。不可視ファイルも、表示中かどうかがメニューから読み取れない。

原因(コード参照 / 2026-11-26): SidebarHeaderControls.overflowMenu は、Menu 内の Button のラベルに Label(title, systemImage: "checkmark") を置いてチェックを描いており、これが実機で表示されない。モデル側の SidebarOverflowItem.isChecked は正しく導出され、SidebarHeaderControlsModelTests(hiddenFilesItemIsCheckedWhenShown ほか)も通る。描画の段階でチェックが失われているため、モデルのテストでは捕まえられない。一方、同じヘッダーの比較基準 ▾(SidebarHeaderControls.changedFilesOnlyMenu)は、独立した Menu 内の Picker(.inline) で描いており、実機でチェックが出る(TASK-678 の実機確認。docs/dev/viewer-ui.md の「差分の比較基準」節)。

既存の制約: SidebarOverflowItem は「項目の identity = 選ぶと起こる SidebarDisplayChange」で、チェックは init で受け取らず settings.isOn から導く(TASK-592)。overflowMenu のコメントは「3 項目のうち 2 つが排他選択で意味がずれるため Toggle は使わない」としている。並び順(排他)と不可視ファイル(ON/OFF)を同じ形で描いていることが、この判断の前提になっている。表示メニュー側の不可視ファイル項目は、AppDelegate.validateMenuItem が menu.view.showHiddenFiles / menu.view.hideHiddenFiles を切り替えている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ⋯ メニューの並び順 2 項目のうち、選ばれている側にだけチェックマークが表示される(実機で確認)
- [ ] #2 ⋯ メニューの不可視ファイルの項目から、いま表示中かどうかが読み取れる(チェックマーク、または「不可視ファイルを隠す」への項目名の切り替え。実機で確認)
- [ ] #3 項目を選んだときに届く SidebarDisplayChange は変わらず、項目の identity とチェックの導出(TASK-592)を破る形にしない。破ったら落ちるテストがある
- [ ] #4 修正後の表示を実機で確かめ、修正を戻すとチェックが出ないことも確かめる
- [ ] #5 docs/dev/viewer-ui.md の該当節(サイドバーヘッダーの ⋯)を新しい描き方に合わせる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. /review-design を回す(⋯ の項目の持ち方・描き方を変え、TASK-592 の不変条件に触れるため)。論点: 並び順を Picker(.inline) の 2 択、不可視ファイルを Toggle に分けたときの SidebarOverflowItem の形 / 選択が SidebarDisplayChange へ届く経路を 1 本に保つこと / Menu 内の Toggle でチェックが出るか
2. 並び順: 比較基準 ▾ と同じく Picker(.inline) で描く(実機でチェックが出る実績のある形)
3. 不可視ファイル: Toggle で描く。実機でチェックが出なければ、表示メニューと同じく「表示 / 隠す」の項目名切り替えにする(キーは AppDelegate.validateMenuItem と共有)
4. SidebarHeaderControlsModelTests を新しい形に合わせ、項目の並びと change の対応を固定する
5. 実機確認: 背景ジョブは補助アクセスが無くメニューを開けない(TASK-931 の実測)。開発ビルドを用意して、利用者に ⋯ を開いてもらう。修正前のビルドとも比べる
6. docs/dev/viewer-ui.md を更新する
<!-- SECTION:PLAN:END -->
