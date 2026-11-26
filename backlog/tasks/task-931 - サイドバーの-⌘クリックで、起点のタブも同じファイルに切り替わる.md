---
id: TASK-931
title: サイドバーの ⌘クリックで、起点のタブも同じファイルに切り替わる
status: To Do
assignee: []
created_date: '2026-11-26T04:01:05Z'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 872000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
利用者の報告(2026-11-26): サイドバーでファイルを ⌘クリックすると、左端(起点)のタブがアクティブなままそのファイルを表示する。仕様(docs/dev/native-app-design.md の ViewerTabGrouping 節。Safari と同じ)は、新しいタブを右端に背面で開き、表示も焦点も起点に留める。

原因(実測 / 2026-11-26、開発ビルドに一時的な NSLog を入れて ⌘クリックを 3 回): 1 回の ⌘クリックで次の順に呼ばれる。
1. FileListView.handleRowTap(⌘)→ fileListDidRequestOpenElsewhere → ViewerTabGrouping.present(placement: .end, select: false)。新しいタブは右端に背面で開き、選択は起点のまま(ここは仕様どおり)
2. その後、SwiftUI の List(selection:) 自体も ⌘クリックで行の選択を変え、Binding の set(FileListView.tableSelection → commitSelection)が呼ばれる
3. commitSelection がファイル行なので open(_:with: .currentTab)→ switchFile で、起点のタブが同じファイルに切り替わる
結果、起点のタブと右端の新しいタブの両方が同じファイルを出す(続けて ⌘クリックすると同じファイルのタブが 2 つ並ぶ)。

このブランチ(TASK-930)由来ではない: commitSelection からいまのタブで開く経路は main にもある。930.8 で触れたのはフォルダー行の扱いだけ。いつから起きているか(OS の更新で List が ⌘クリックの選択を変えるようになったのか、元からか)は未確認。

着手時の注意: 同型の判定(修飾キーやフラグで後続の選択変更を握りつぶす)は、過去に誤検知を繰り返した型(CLAUDE.md の「同型のバグが 2 回目に出たら構造で塞ぐ」)。List の選択の書き戻しを、利用者の操作の種別という事実で区別できるか(例: ⌘ 付きのクリックでは List に選択を渡さない、NSTableView 側で修飾キー付きクリックの選択を止める)から検討する。フォルダー行の ⌘クリック(TASK-930.8)も同じ経路を通るので、同時に確かめる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーでファイル行を ⌘クリック / ⌘⇧クリックしても、起点のタブの表示と選択は変わらない
- [ ] #2 新しいタブは右端に背面で開く(既存の仕様どおり)
- [ ] #3 フォルダー行の ⌘クリックでも起点のタブが変わらない
- [ ] #4 実機(開発ビルド)で ⌘クリックの呼び出し順を確かめ、修正を戻すと再現することを確かめる
<!-- AC:END -->
