---
id: TASK-291
title: 変更ファイル絞り込みのトグルでサイドバー全体を再読み込みしない
status: Done
assignee: []
created_date: '2026-08-04 07:30'
updated_date: '2026-08-04 09:43'
labels: []
dependencies: []
priority: low
type: enhancement
ordinal: 481000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review(high, 2026-08-04)。ViewerWindowManager.toggleChangedFilesOnly() は不可視ファイルと同じ refreshAllSidebars() を再利用しているが、不可視ファイルはディスク列挙の入力が変わるのに対し、この絞り込みはメモリ上のデータに対する純粋な表示述語であり、再列挙も git 実行も要らない。

観測（レビューの主張、未実測）: ウィンドウ 3 枚・大きなリポジトリで ⌘⌃G 1 回につき git status 3 回とディレクトリ全列挙 3 回が走り、サイドバーが一瞬止まって行が再ソートされる。

着手前に体感レイテンシで実測すること（固定間隔の計測は結論が逆転しうる）。効果が小さければ現状維持の判断も可とし、その理由を記録する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 トグル時に再列挙と git 実行が走らないか、走る必要がある場合はその理由が記録される
- [x] #2 全ウィンドウ連動と永続化の挙動が変わらない（既存のトリガー経路テストが通る）
- [x] #3 変更前後の体感（トグルから再描画までのレイテンシ）を実測して記録する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測(swift test -c release、この worktree をリポジトリとして使用、ウィンドウ 3 枚を模した SidebarNavigator 3 個、実 DirectoryLister + 実 GitStatusStore): トグル 1 回の所要時間は 全再読み込み=365.7/373.3/379.4/400.0/383.3 ms、表示設定の同期のみ=いずれも 0.001 ms 未満。計測は使い捨てのテスト(ChangedFilesOnlyToggleLatencyMeasurement.swift)で行い、計測後に削除した。レビューの主張どおり、⌘⌃G のたびに全ウィンドウでディレクトリ列挙と git status が走っていた。

方針: 新しいメソッドを足すのではなく、既存の syncDisplayPreferences()(fileListModel のミラーを設定へ同期するだけの処理)を internal にして再利用した。トグル経路はこれ 1 回で足り、再列挙も git 実行も起こさない。git 状態の鮮度は既存の別経路(windowDidBecomeKey / ディレクトリ移動での一覧取得、.git/index 監視、表示中ファイルの onContentReloaded)で保たれるため、トグルで取り直す必要はない。

検証: 回帰テスト『表示設定の反映では再列挙も git 実行も走らない』を追加(注入クロージャの呼び出し回数が増えないことを、発行済みタスクを await したうえで確認)。試しに refreshFileList() を戻すと 2 件失敗することを確認済み。既存のトリガー経路テスト(ViewerWindowManagerIntegrationTests のメニュー/アイコンボタン両経路)を含め swift test 全 1074 件が通過。swiftlint は main とのベースライン差分ゼロ(SidebarNavigator.swift はちょうど 400 行に収め file_length を新規発生させていない)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
⌘⌃G のトグルを全サイドバー再読み込みから既存 syncDisplayPreferences() の再利用へ変更し、再列挙と git 実行を無くした。実測(release、ウィンドウ 3 枚)で 366-400ms → 0.001ms 未満。再列挙・git が走らないことの回帰テストを追加し、全 1074 テスト通過。
<!-- SECTION:FINAL_SUMMARY:END -->
