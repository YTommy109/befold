---
id: TASK-361
title: サイドバーにツリー展開（Finder のリスト表示相当）の表示モードを追加する
status: To Do
assignee: []
created_date: '2026-08-08 06:00'
updated_date: '2026-08-10 01:58'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 615500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー中、特に git 差分表示モードで、変更されたファイルは複数のフォルダに散らばる。現在のサイドバーは 1 階層ずつのドリルダウンしか持たないため、フォルダを行き来する操作が挟まり目的のファイルへ届きにくい。Finder のリスト表示（cmd+2）のように、開閉三角でサブフォルダをその場に展開し、複数フォルダを同時に開いたまま行き来できる表示モードを追加する。

## スコープ（ユーザーとの確認済み事項）

- 追加するのは**ツリー展開（Finder のリスト表示相当）**。階層を畳んだフラット一覧は本タスクでは作らない。
- 適用範囲は**サイドバー全体（常時）**。git 差分表示モードのときだけの挙動にはしない。通常のファイル閲覧でも同じ表示モードを使える。
- 従来のドリルダウン表示は残し、ユーザーが表示モードとして選べるようにする。選択は永続化する。

## 現状（調査結果、2026-08-08）

- 表示は `List(model.visibleEntries, selection:)` のフラットな 1 セクション（`BefoldApp/befold/Viewer/FileListView.swift:161`）。`OutlineGroup` / `DisclosureGroup` は未使用で、`FileListEntry.Kind` は `.parentNavigation` / `.folder` / `.file` の 3 つのみ、展開状態を持つプロパティは無い（`Viewer/FileListEntry.swift:10-14`）。
- 移動はダブルクリック（`FileListView.swift:301-313`）、`return`/`→`/`l` の `enterSelected()`（`:377-391`）、`←`/`h`/`delete`/`cmd+↑` の `navigateToParent()`（`:393-399`）で、いずれも `SidebarNavigator.navigateToFolder(_:)` に落ちる。
- 列挙は 1 ディレクトリ直下のみ（`Viewer/DirectoryLister.swift:34-40,70-98`）。保持も現在ディレクトリ 1 つぶんだけ（`Viewer/FileListModel.swift:21-48`）。
- 名前フィルタは現在の 1 階層だけが対象（`FileListModel.visibleEntries` `:269-271` が `entries` に `FileListFilter.apply` を適用、`Viewer/FileListFilter.swift:26-37`）。

## 構造上の論点（着手時に必ず詰めること）

現在の実装は「サイドバー = 単一ディレクトリの平坦配列」を複数箇所で前提にしている。ツリー展開はこの前提を崩すため、以下はいずれも設計判断が要る。

- `entries` / `entriesDirectory` の単一ディレクトリ前提（`FileListModel.swift:21-48,269-271,279-281`）
- スクロール行番号の算出が「visibleEntries の添字 = NSTableView の行番号」前提（`FileListModel.swift:251-263`。コメント 258-259 行に明記）
- キーボード移動が `visibleEntries` の前後添字前提（`FileListView.swift:345-375`）。展開時の `→`/`←` を「フォルダへ入る/親へ戻る」から「展開/畳む」へ変えるかどうかも決める
- `previewTarget` の導出が `FileListEntryIndex`（フラット配列由来）依存（`FileListModel.swift:70-78`）
- **git 状態の突き合わせが単一の `directoryKey` 前提**（`App/SidebarGitStatus.swift`、`FileListFilter.swift:45-50`、`FileListModel.swift:193,333-335`）。複数階層を同時表示すると 1 つの directoryKey では対応付けできない。差分表示との併用が本タスクの動機なので、ここは避けて通れない
- `performListing` の単一世代ガード（`App/SidebarNavigator.swift:222-258`）と、展開ごとの非同期列挙の競合
- 親移動行 `.parentNavigation` の扱い（`FileListFilter.swift:30`、`FileListView.swift:181`、`FileListModel.swift:279-281`）。ツリー表示では不要になる可能性がある
- 名前フィルタの意味。ツリー展開時に「展開済みの階層だけを絞る」のか「一致する子を持つ祖先を残す」のかを決める
- 展開状態の永続化先。現在サイドバー関連の永続化は `App/SidebarStateStore.swift`（開閉状態）と `App/SidebarDisplayPreference.swift`（隠しファイル・変更のみ）にあり、現在ディレクトリ・スクロール位置・展開状態を持つストアは存在しない

## 制約

- **cmd+1〜4 は TASK-356 がプレビューの表示モードに割り当てる予定**。サイドバーの表示モード切替に cmd+1 / cmd+2 を使ってはならない。ショートカットを付けるなら別のキーにするか、View メニュー項目のみとする
- 状態の持ち方を変える変更に当たるため、実装着手前に `/review-design` を 1 回回し、結果を Implementation Plan に反映すること。1 PR に収まらないと判断したらサブタスクへ分割し、サブタスクごとに `/review-design` を回すこと
- ツリー展開は「フォルダを開いたまま複数階層を同時表示する」という不変条件を新設する。決めた粒度・不変条件には、破れたら落ちるテストを同じタスク内で用意すること
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーの表示モードとして、従来のドリルダウンとツリー展開を選べる
- [ ] #2 ツリー展開では開閉三角でサブフォルダをその場に展開でき、複数のフォルダを同時に開いたままにできる
- [ ] #3 選んだ表示モードが再起動後も保持される
- [ ] #4 ツリー展開でも git ステータスのバッジと「変更されたファイルのみ表示」が、表示中のすべての階層に対して正しく効く
- [ ] #5 ツリー展開でのキーボード操作（選択の上下移動・展開/畳む・ファイルを開く）が定義され、テストで検証されている
- [ ] #6 名前フィルタのツリー展開時の意味が決まっており、その仕様がテストで検証されている
- [ ] #7 ツリー展開時に選択したファイルへスクロールが正しく追従する（行番号の算出がフラット配列前提のままになっていない）
- [ ] #8 従来のドリルダウン表示の既存の振る舞いと既存テストが壊れていない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 調査（2026-08-10）

Description の「現状（2026-08-08）」に書いた 12 の主張を HEAD a3202d4 で再検証し、**すべて現在も成立**することを確認した（行番号のズレも無し。FileListView.swift:161 の List(model.visibleEntries, selection:) も一致、OutlineGroup / DisclosureGroup の使用は全体で 0 件）。

## 単純化の検討 → サブタスクへ分割

「構造上の論点」8 件のうち、次の 3 件は **ツリーを別モードとして並置する場合にのみ発生する**。行モデルを「ルート + 展開集合から生成される depth 付きフラット配列」へ一本化し、ドリルダウンをその縮退形（展開集合が空）として通せば、論点自体が消える。

- スクロール行番号 = visibleEntries の添字前提（FileListModel.swift:258-260）
- キーボード移動の前後添字前提（FileListView.swift:346-372）
- previewTarget の FileListEntryIndex 依存（FileListModel.swift:70）

一方、単純化しても残る本質的な設計変更は次の 3 件。

- git 状態の単一 directoryKey 前提（SidebarGitStatus.swift:16 / FileListFilter.swift:47 / FileListModel.swift:193,214）
- performListing のサイドバー全体 1 世代ガード（SidebarNavigator.swift:222-240）
- 名前フィルタのツリー時の意味（FileListFilter.swift:27）

この整理に沿って TASK-361.1〜361.5 へ分割した（361.1 が土台、361.2/361.3 が並行可能、361.4 で初めてユーザーに見える、361.5 が仕上げ）。親タスクの AC はサブタスク側の AC で満たされる。

## 確定した制約

- TASK-356（cmd+1〜4 をプレビュー表示モードへ割り当て）は **Done**。「使ってはならない」は予定でなく確定事項として 361.4 の AC に入れた。
<!-- SECTION:NOTES:END -->
