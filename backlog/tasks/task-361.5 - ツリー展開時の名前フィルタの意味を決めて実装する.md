---
id: TASK-361.5
title: ツリー展開時の名前フィルタの意味を決めて実装する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 01:58'
updated_date: '2026-08-10 04:05'
labels: []
dependencies:
  - TASK-361.4
parent_task_id: TASK-361
priority: medium
type: task
ordinal: 659000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ツリー展開時の名前フィルタの意味を決めて実装する。TASK-361 で「決めること」として残された論点。

## 現状（実測 2026-08-10、HEAD a3202d4）

- Viewer/FileListFilter.swift:27 apply(to:in:) は「directory 直下の一覧」に対する filter のみ（ドキュメントコメントにも明記）。子孫を残す・一致する子を持つ祖先を保つといったツリー考慮は無い
- Viewer/FileListModel.swift:269 visibleEntries が listFilter.apply(to: entries, in: entriesDirectory)

## 決めること（いずれか）

- A: 展開済みの階層だけを絞る（現在の意味をそのまま各階層へ適用）
- B: 一致する子を持つ祖先フォルダを残す（未展開のフォルダも一致すれば自動展開する／しない、も併せて決める）

B は未展開フォルダの再帰列挙が要るため、コストと挙動（大きなツリーでの応答性）を実測してから決めること。

## 制約

- 着手前に /review-design を 1 回回すこと
- 既存テスト FileListModelFilterTests(18) を壊さないこと
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ツリー展開時の名前フィルタの意味が決まり、タスクの Implementation Notes に採用理由とともに記録されている
- [x] #2 決めた意味がテストで検証されている
- [x] #3 ドリルダウン時のフィルタ挙動と既存テスト（FileListModelFilterTests 18 件）が壊れていない
- [x] #4 空状態判定 visibleEntries.allSatisfy { $0.kind == .parentNavigation } は FileListView.swift:181 と FolderListingView.swift:126 の 2 箇所にあり、両方が「展開したフォルダの子が全部フィルタで消えた」状態を表せる（片方だけ直すと TASK-320 型の取り残しになる）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 採用: A（展開済みの階層だけを絞る）+ 祖先の保持

判定規則そのものは変えず、**残った行の祖先にあたる行は自分が一致しなくても残す**。
未展開フォルダの自動展開（B）は採らない。

## 現状で壊れていたこと

`FileListFilter.apply(to:in:)` はフラット配列に一様に効くため、ツリー展開後の行配列では
**親フォルダ行だけが消えて子行が残る**。インデントだけが存在しない親を指す孤児行になる。

## B（自動展開）を採らない理由

- B は「一致する子を持つか」を知るために**未展開フォルダの再帰列挙**が要る。
  「展開 1 回につき列挙 1 回」というコストの上限（TASK-361.3 の AC #5）を、
  フィルタの 1 文字ごとに破ることになる。列挙は `containsSupportedFile`
  （フォルダ 1 件ごとにディレクトリ列挙）を伴う
- `SidebarRowBuilder` を「材料を辞書で受けて I/O を構造的に持てない」形にした設計
  （TASK-361.3）と正面から衝突する。B を入れるとフィルタ 1 文字ごとに非同期列挙の
  オーケストレーションが要る
- 打った条件で行が消えるのは納得できるが、**勝手に階層が開く**のは驚きが大きい
- 「ツリーの奥まで探す」需要は Quick Open が既に担っている。サイドバーのフィルタは
  「いま見えている範囲を絞る」ものと位置付ける

## /review-design の指摘への対応

1. **`listingSource` は祖先保持の前の配列から採る**（最重要）。足し戻した配列を渡すと、
   条件に一致しないフォルダがプレビューにも現れる一方、同じフォルダを自前列挙する
   経路では消えるため、1 ウィンドウ内に絞り込みの答えが 2 つ並ぶ（TASK-288 の巻き戻し）
2. **早期 return を 2 本**（絞り込みが効いていない / 全行 depth 0）。素通しは
   「なるはず」ではなくコード上の分岐で担保する。ここは body 評価・キー操作の
   たびに走る経路
3. **祖先の定義は「配列上の depth の連なり」**。pathKey の前置一致では決めない
   （`SidebarRowBuilder` は循環を止めるため訪問済みキーで枝を打ち切るので、パス文字列と
   行構造の一致は保証されない。同名フォルダが別階層にある場合も取り違える）。
   同名フォルダのテストで担保する
4. **`presentedPathKey` の祖先が残る**ことを明示の例外として doc に記録
5. テストは純粋関数だけでなく **`FileListModel.visibleEntries` と `FolderListingView` の
   両経路**に置く（配線されたかは純粋関数のテストでは測れない / TASK-319 と同型）

## 挿入位置

`visibleEntries` 内で `listFilter.apply` → `SidebarTreeFilter.keepingAncestors` →
`SidebarDisclosureResolver.resolving` の順。祖先の連なりは連続する depth の鎖なので、
足し戻した祖先には必ず depth+1 の直接の子が存在し、三角は `.expanded` のまま。
順序を逆にすると「名前は一致するが子が全部消えたフォルダ」の判定が、あとから
足し戻した祖先を子として数える余地が残る。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-10）

### 採用した意味（AC #1）

**A（展開済みの階層だけを絞る）+ 残った行の祖先を保持する。**
未展開フォルダの自動展開（B）は採らない。理由は Implementation Plan に記載。

### レビューで判明した前提の誤り

設計文は「git 絞り込みでも孤児行が生じるので祖先保持が要る」としていたが、
`GitFolderStatus.aggregate` は各変更を**自身と全祖先ディレクトリ**へ OR 集約しており、
**git 絞り込み単独では祖先は元から残る**。祖先保持は冪等な集合演算なので二重適用でも
壊れないが、「git には不要」と結論してはいけない。次の 2 ケースで git でも孤児が出る。

- **`presentedPathKey` 例外**: 未変更でも選択中の行は残る。その祖先フォルダは変更を
  持たないので `hasChange` が false になり、親だけ消える。祖先保持でしか塞げない
- **名前フィルタとの AND**: 名前判定が先に走るため、git 的に残るはずの祖先も
  名前不一致で落ちる

`presentedPathKey` は深い行にも効く（比較は絶対の正規化パスキー同士で、depth も
`entriesDirectory` も参照しない）。ただし名前フィルタには効かない（意図どおり）。

### swiftlint 対応

- `SidebarTreeFilter` のローカル変数名 `id` が `identifier_name` に触れたため `ancestor` へ
- `FileListModelFilterTests` が file_length / type_body_length を超えたため、
  ツリー関連を `FileListModelTreeFilterTests` へ分離
  （`DirectoryListerAppendingOpenFileTests` と同じ理由）

### 検証（実測 2026-08-10）

- swift test（統合テストを含む全件）: **1322 tests / 195 suites 全通過**（変更前 1310）
- 既存 `FileListModelFilterTests` は**分割のみで、既存ケースの期待値は変更なし**（AC #3）
- swiftlint: origin/main とのベースライン比較で**真の新規違反ゼロ**
  （ルール×ファイルの組で比較）。既存違反 2 件は 361.4 で解消したまま
- swiftformat --lint: 0 件
- xcodegen generate 実行済み / xcodebuild build -scheme befold: exit=0

### AC #4（空状態判定）について

`visibleEntries.allSatisfy { $0.kind == .parentNavigation }` は `FileListView` と
`FolderListingView` の 2 箇所にあるが、文言の出し分けは TASK-361.2 で
`SidebarEmptyState` へ共有済みなので、片側だけ直す形にはならない。

祖先保持により「一致が 1 つも無い → `..` だけが残る」となり、この述語はツリーでも
そのまま成立する。「展開したフォルダの子が全部消えた」状態は一覧が空ではない
（そのフォルダ行は残る）ので空状態にはならず、開閉三角の
`.expandedEmpty(isFiltered: true)`（TASK-361.4）が表す。

### 起票したフォローアップ

- **TASK-405**: `SidebarEmptyState` が git 絞り込みの有無しか出し分けておらず、
  名前フィルタで 0 件のときに「対応ファイルがありません」と事実と食い違う
  （TASK-287 と同型の問題が名前フィルタ側に残っていた既存の欠落）
- **TASK-406**: 祖先として残しただけのフォルダが `firstSelectableEntryURL` 経由で
  初期選択になりうる件の挙動決定
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ツリー展開時の名前フィルタの意味を「展開済みの階層だけを絞る + 残った行の祖先は保持する」と決めて実装した。祖先を残さないと親フォルダ行だけが消えて子行が孤児になる。未展開フォルダの自動展開は採らない（フィルタ 1 文字ごとに再帰列挙が必要になり、SidebarRowBuilder が I/O を持たない設計と衝突するため）。祖先保持は FileListFilter（サイドバーとプレビューの共有型）ではなく SidebarTreeFilter へ置き、プレビューへ渡す一覧は祖先保持の前から採ることで 1 ウィンドウ内に絞り込みの答えが 2 つ並ぶのを防いだ。検証: swift test 全 1322 件通過（既存 FileListModelFilterTests は分割のみで期待値の変更なし）、swiftlint 新規違反ゼロ、xcodebuild exit 0。
<!-- SECTION:FINAL_SUMMARY:END -->
