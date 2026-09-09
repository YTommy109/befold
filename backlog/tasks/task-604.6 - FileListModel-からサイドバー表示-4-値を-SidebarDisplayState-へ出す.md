---
id: TASK-604.6
title: FileListModel からサイドバー表示 4 値を SidebarDisplayState へ出す
status: To Do
assignee: []
created_date: '2026-09-09 00:02'
labels:
  - refactor
dependencies: []
parent_task_id: TASK-604
priority: low
ordinal: 882000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befold/Viewer/FileListModel` グループは 393 行（本体 355 + `+Snapshot` 38）。TASK-585 で 418 → 393 へ返済済み（名前フィルターとスライドモードを `SidebarTransientState` へ、境界は「保存値の対を持つか」）。当時 7 値の移設案は 57 ファイル波及で見送られた。**その見送り分の一部がまだ返済余地として残っている。**

## 返済先（約 −20〜25 行、393 → 約 368〜373）

サイドバー表示 4 値のライブ値（`FileListModel.swift:174-192`）を `SidebarDisplayState`（`SidebarTransientState` と並ぶ兄弟型）へ。

決め手は実測: **4 値のうち 3 つ（`sortOrder` / `showHiddenFiles` / `layoutMode`）は `FileListModel` 内から一度も読まれていない**（宣言と init 代入のみ）。読み手は全部外側（`SidebarListingCoordinator` 10 参照 / `SidebarHeaderControlsModel` 7 / `ViewerDisplayOptionsApplier` 6 / `SidebarTreePresenter` 5）。モデルが「窓ごとの設定バッグ」として使われている状態で、規約の「複数の関心が 1 クラスに同居し始めたら凝集単位で分割する」に該当する。`showChangedFilesOnly` だけは内部でも使う（`:315,328`）。

`FileListModel` は `let display = SidebarDisplayState(settings:)` を 1 本持つ形（`transient` と同じ）。対応する値型 `SidebarDisplaySettings` は既存なので写像はそのまま使える。

## 返済対象にしないもの（根拠）

- **git 状態は ADR 0003 が固定**（`applyGitStatus` 1 関数への一本化）。ただし ADR の再検討トリップワイヤ #1 が「FileListModel に判定以外の責務が増え肥大化する」なので、この返済はそれに応える動き
- **`previewTarget`（`:116-125`）は ADR 0002 の単一導出点**。4 つの材料を同時に要るので出すと結合が増える
- `tableFocuser` は既に `SidebarTableFocuser` へ出済み

## 注意

- 波及は本番 15 ファイル / テスト 31 ファイル（上振れ見積り）。効果 20〜25 行に対して大きいので、閾値に押されるまで急がなくてよい
- `BefoldApp/befold/App/SidebarDisplaySettings.swift:122` に `extension FileListModel` があり、**ディレクトリが違うため 393 に合算されていない**。型の実サーフェスは 393 行より広い
- **この判断（何が切り出せて何が ADR 0002 / 0003 で固定されているか）を `FileListModel` の型 doc へ残すこと。** 残さないと次に閾値へ近づいたときに 3 度目の同じ調査が走る（TASK-585 → TASK-604 で既に 2 回）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバー表示 4 値が SidebarDisplayState へ出ている（または見送る判断と理由が記録されている）
- [ ] #2 FileListModel の型 doc に、何が切り出せて何が ADR 0002 / 0003 で固定されているかが書いてある
- [ ] #3 swift test が通り、サイドバーの表示切り替えが実機で動く
<!-- AC:END -->
