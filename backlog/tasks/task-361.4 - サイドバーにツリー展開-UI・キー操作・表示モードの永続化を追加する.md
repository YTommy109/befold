---
id: TASK-361.4
title: サイドバーにツリー展開 UI・キー操作・表示モードの永続化を追加する
status: To Do
assignee: []
created_date: '2026-08-10 01:58'
updated_date: '2026-08-10 02:08'
labels: []
dependencies:
  - TASK-361.1
  - TASK-361.2
  - TASK-361.3
parent_task_id: TASK-361
priority: medium
type: feature
ordinal: 658000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ここで初めてユーザーから見える機能になる。開閉三角による展開 UI、キーボード操作、展開状態と表示モードの永続化を入れる。

## 前提

TASK-361.1 で行モデルは「ルート + 展開集合」から生成されるようになっている。本タスクは展開集合を実際に動かす UI と永続化を足す。

## 方針

- 行の先頭に開閉三角を置き、depth ぶんインデントする（List のフラット 1 セクション構造は維持。OutlineGroup へは移行しない）
- 表示モード（従来のドリルダウン / ツリー展開）を選べるようにし、選択を永続化する
- キーボード: ツリー展開時の →/l と ←/h を「フォルダへ入る/親へ戻る」から「展開/畳む」へ変えるかを決める（Viewer/FileListView.swift:326-399 の handleKey / enterSelected / navigateToParent）。ドリルダウン時の既存の割り当ては変えない
- ツリー展開時に .parentNavigation 行を出すかを決める（Viewer/FileListFilter.swift:30、FileListView.swift:181、FileListModel.swift:279-281）

## 永続化先の注意（実測 2026-08-10）

- App/SidebarStateStore.swift(58 行) は **サイドバーペイン自体の開閉**（UserDefaults キー SidebarCollapsedStates / SidebarLastToggledCollapsed）であって、ツリーの展開状態ではない。名前が紛らわしいので流用・命名衝突に注意する
- App/SidebarDisplayPreference.swift(40 行) は showHiddenFiles(13) / showChangedFilesOnly(23) のみ。表示モードはここへ足すのが自然か、別ストアにするかを /review-design で決める
- 新しい UserDefaults キーを足す・意味を変える場合は CLAUDE.md「UserDefaults キーの廃止・改名」の手順（旧キーの読み手を rg で洗う / defer での削除 / 3 ケースのテスト）に従う

## 制約

- **cmd+1〜4 はプレビューの表示モードに割り当て済み（TASK-356 は Done）**。サイドバーの表示モード切替にこれらを使ってはならない。別のキーにするか View メニュー項目のみとする
- 着手前に /review-design を 1 回回すこと
- 「フォルダを開いたまま複数階層を同時表示する」不変条件に対し、破れたら落ちるテストを本タスク内で用意すること
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーの表示モードとして、従来のドリルダウンとツリー展開を選べる
- [ ] #2 ツリー展開では開閉三角でサブフォルダをその場に展開でき、複数のフォルダを同時に開いたままにできる
- [ ] #3 選んだ表示モードが再起動後も保持される
- [ ] #4 ツリー展開でのキーボード操作（選択の上下移動・展開/畳む・ファイルを開く）が定義され、テストで検証されている
- [ ] #5 選択したファイルへのスクロール追従がツリー展開時も正しく動く
- [ ] #6 cmd+1〜4 に新しい割り当てを追加していない
- [ ] #7 従来のドリルダウン表示の既存の振る舞いと既存テストが壊れていない
- [ ] #8 enterSelected（FileListView.swift:377-391）の .folder に対する動作を「フォルダへ入る」から「展開トグル」へ変えるかを決め、selectNext / selectPrevious（:345-375）・navigateToParent（:393-399）・firstSelectableEntryURL（FileListModel.swift:279-281）の各消費点をツリー前提で棚卸ししている
<!-- AC:END -->
