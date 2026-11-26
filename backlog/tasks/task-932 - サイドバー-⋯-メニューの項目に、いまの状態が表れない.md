---
id: TASK-932
title: サイドバー ⋯ メニューの項目に、いまの状態が表れない
status: Done
assignee:
  - '@claude'
created_date: '2026-11-26T08:30:10Z'
updated_date: '2026-11-26T10:44:23Z'
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
- [x] #1 ⋯ メニューの並び順 2 項目のうち、選ばれている側にだけチェックマークが表示される(実機で確認)
- [x] #2 ⋯ メニューの不可視ファイルの項目から、いま表示中かどうかが読み取れる(チェックマーク、または「不可視ファイルを隠す」への項目名の切り替え。実機で確認)
- [x] #3 項目を選んだときに届く SidebarDisplayChange は変わらず、項目の identity とチェックの導出(TASK-592)を破る形にしない。破ったら落ちるテストがある
- [x] #4 修正後の表示を実機で確かめ、修正を戻すとチェックが出ないことも確かめる
- [x] #5 docs/dev/viewer-ui.md の該当節(サイドバーヘッダーの ⋯)を新しい描き方に合わせる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化の検討(2026-11-26): モデル(SidebarOverflowItem の並び・change・isChecked)は変えず、SidebarHeaderControls.overflowMenu の項目の描き方だけを Label+checkmark から Toggle(isOn: isChecked、set で change を発行)へ替える。並び順を Picker に分ける必要はない(チェック済みの側を選び直しても setSortOrder が同値を書くだけで、排他の 2 択として振る舞う)。1 ファイル内の局所修正で状態も経路も増えないため /review-design の対象外
2. Toggle の Binding を作る部分を小さな関数に出し、get = isChecked / set = change の発行をユニットテストで固定する(AC #3)
3. 実機確認: 開発ビルドを用意し、利用者に ⋯ を開いてもらう。修正前の描き方と環境変数で切り替えて比べる(一時コード、コミットしない)。Toggle でチェックが出なければ、並び順は Picker(.inline)、不可視ファイルは項目名の切り替えへ切り替える
4. docs/dev/viewer-ui.md を更新する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-26: Toggle での描画に替え、SidebarHeaderControlsModelTests に overflowToggleReadsCheckAndEmitsChange を追加(set を『true のときだけ発行』に壊すと落ちることを確認)。viewer-ui.md を更新。実機確認は未実施: 背景ジョブは補助アクセスが無く ⋯ を開けない。開発ビルド(.build/xcode、T932_OLD=1 で修正前の描き方)を用意済みで、利用者の確認待ち。

実機(2026-11-26、開発ビルド。修正前の描き方への切り替え T932_OLD は一時コードでコミットしていない): 修正あり(PID 28538)で、並び順の選ばれている側と「不可視ファイルを表示」(⌃⌘H で表示にした後)の両方にチェックが付いた(利用者の目視)。T932_OLD=1(PID 29298、Button のラベルの Label(checkmark))では両方ともチェックが付かず、#793 を再現した。Menu 内の Toggle でチェックが出たので、計画にあった Picker(.inline) / 項目名の切り替えへの代替は不要。swift test(--skip Integration/FileWatcherTests/PDF)1907 件通過、swiftlint は main とのベースライン差分ゼロ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーヘッダーの ⋯ メニューで、どの項目にもチェックマークが出なかった不具合(#793)を直した。項目を Button のラベルの Label(_, systemImage: "checkmark") ではなく Toggle で描く。Toggle の値は SidebarOverflowItem.isChecked を読み、選ばれたら書かれた値を使わず項目の SidebarDisplayChange を発行する(SidebarHeaderControls.overflowToggle)。項目の並び・identity・チェックの導出(TASK-592)は変えていない。並び順の 2 択も Toggle で描くが、チェック済みの側を選び直しても同じ setSortOrder が届くだけで外れない。実機で、修正ありではチェックが付き、修正前の描き方では付かないことを確かめた。
<!-- SECTION:FINAL_SUMMARY:END -->
