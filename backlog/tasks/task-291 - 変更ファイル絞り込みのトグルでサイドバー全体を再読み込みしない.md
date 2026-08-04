---
id: TASK-291
title: 変更ファイル絞り込みのトグルでサイドバー全体を再読み込みしない
status: To Do
assignee: []
created_date: '2026-08-04 07:30'
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
- [ ] #1 トグル時に再列挙と git 実行が走らないか、走る必要がある場合はその理由が記録される
- [ ] #2 全ウィンドウ連動と永続化の挙動が変わらない（既存のトリガー経路テストが通る）
- [ ] #3 変更前後の体感（トグルから再描画までのレイテンシ）を実測して記録する
<!-- AC:END -->
