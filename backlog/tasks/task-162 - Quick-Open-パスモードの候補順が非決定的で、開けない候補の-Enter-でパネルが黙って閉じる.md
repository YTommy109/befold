---
id: TASK-162
title: Quick Open パスモードの候補順が非決定的で、開けない候補の Enter でパネルが黙って閉じる
status: To Do
assignee: []
created_date: '2026-07-27 05:48'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 237000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2つの細部挙動の修正。

(1) パスモードの列挙が未ソート: AppQuickOpenEnvironment.directoryEntries は FileManager.contentsOfDirectory を直接呼び、返却順は未定義。そのためパスモードの候補順・選択位置0番・completePath の「表記は最初の候補から採る」がいずれも非決定的になる。coding_rule.md の単一情報源テーブルは「ディレクトリ列挙（ソート・フィルタ込み）= DirectoryLister.sortedContents」と定めており、これは4箇所目の自前列挙でもある。localizedStandardCompare でソートし、可能なら DirectoryLister に「フォルダ+ファイル混在の全件列挙」API を足して委譲する（隠しファイルの出し分けを呼び出し側で行う設計は維持してよい）。

(2) QuickOpenView の onSubmit が commitSelection() の成否に関わらず onDismiss() を呼ぶ: commitSelection は「開ける対象が無ければ何もしない」契約（空ディレクトリ等で nil）だが、View 側が無条件で閉じるため、開けない候補で Enter するとパネルが黙って消えるだけになる。commitSelection を Bool 返しにして失敗時は閉じない、または「閉じるのは決定経路（PanelController の onOpen 内 dismiss）だけ」に一本化する。

該当: BefoldApp/befold/App/AppQuickOpenEnvironment.swift:67-72 / BefoldApp/befold/App/QuickOpenView.swift:35-38 / BefoldApp/befold/App/QuickOpenModel.swift:83-88
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 パスモードの候補が同じディレクトリ内容に対して常に同じ順序（localizedStandardCompare 昇順）で表示される（テストで固定）
- [ ] #2 ディレクトリ列挙が DirectoryLister 系の単一情報源に委譲されるか、委譲しない場合はその理由が実装コメントに残る
- [ ] #3 開ける対象が無い状態で Enter を押してもパネルが閉じず、一致なし/候補の表示が保たれる（QuickOpenModel のテストで固定）
<!-- AC:END -->
