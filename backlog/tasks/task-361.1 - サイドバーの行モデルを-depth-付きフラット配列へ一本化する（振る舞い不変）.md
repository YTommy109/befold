---
id: TASK-361.1
title: サイドバーの行モデルを depth 付きフラット配列へ一本化する（振る舞い不変）
status: To Do
assignee: []
created_date: '2026-08-10 01:57'
labels: []
dependencies: []
parent_task_id: TASK-361
priority: medium
type: task
ordinal: 655000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーの行モデルを「単一ディレクトリ直下の配列」から「ルート + 展開集合から生成される、depth を持つフラットな行配列」へ一本化する。**この時点では UI の見た目・操作は一切変えない**（展開集合は常に空、親移動行あり = 現在のドリルダウンと完全に同じ表示になる）。

## なぜ最初にこれをやるか

TASK-361 が挙げた構造上の論点のうち、次の 3 つは「ツリーを別モードとして並置する」場合にのみ発生し、行モデルを一本化すれば論点自体が消える（実測: 2026-08-10、下記いずれも現在の HEAD で成立）。

- スクロール行番号 = visibleEntries の添字前提（Viewer/FileListModel.swift:258-260 のコメントに明記、260 selectedRow / 254 scrollRowToVisible）
- キーボード移動が visibleEntries の前後添字前提（Viewer/FileListView.swift:346-372）
- previewTarget が FileListEntryIndex（フラット配列由来）依存（Viewer/FileListModel.swift:70、索引構築は :25/:56）

フラットな行配列を維持したまま depth を足す形にすれば、これらは変更不要のまま通る。

## 現状（実測 2026-08-10、HEAD a3202d4）

- Viewer/FileListEntry.swift:10-14 の Kind は .parentNavigation / .folder / .file の 3 つ。プロパティは url(16) / kind(17) / containsSupportedFile(21) / pathKey(25) のみで depth・展開状態は無い
- Viewer/FileListModel.swift:21 entries、:38 entriesDirectory、:45 setEntries(_:for:) が単一ディレクトリ前提
- Viewer/DirectoryLister.swift:70 buildEntries が 1 階層直下 + 親 1 件を組む（:160 sortedContents 経由）
- リポジトリ全体で OutlineGroup / DisclosureGroup の使用は 0 件

## 方針

- FileListEntry に depth（ルートからの相対深さ、ルート直下 = 0）を持たせる
- 「ルート URL + 展開済みフォルダの集合」から行配列を組み立てる純粋関数を新設し、DirectoryLister の出力をその入力に据える
- ドリルダウンは「展開集合が空」の縮退形として同じ生成器を通す
- List(model.visibleEntries, selection:)（Viewer/FileListView.swift:161）のフラット 1 セクション構造は維持する（OutlineGroup へは移行しない。行番号 = 添字の不変条件を壊さないため）

## 制約

- 状態の持ち方を変える変更に当たるため、着手前に /review-design を 1 回回し、結果を Implementation Plan に反映すること
- 「visibleEntries の添字が NSTableView の行番号と一致する」という不変条件は本タスク以降も維持する。破れたら落ちるテストを本タスク内で用意すること（FileListModelScrollTests に depth 付き複数階層のケースを足す）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 行の生成が「ルート + 展開集合」を入力とする純粋関数に一本化され、ドリルダウンはその縮退形（展開集合が空）として通っている
- [ ] #2 FileListEntry が depth を持ち、depth からインデント量が決まる（表示上はドリルダウン時 depth が全て 0 なので見た目は変わらない）
- [ ] #3 visibleEntries の添字 = NSTableView の行番号という不変条件が、複数階層を含む行配列でも成立することがテストで検証されている
- [ ] #4 キーボード移動・previewTarget 解決・スクロール追従の既存テストが変更なしで通る（FileListViewTests 13 件 / FileListModelPreviewTargetTests 7 件 / FileListModelScrollTests 3 件）
- [ ] #5 UI の見た目と操作は本タスクの前後で変化しない
<!-- AC:END -->
