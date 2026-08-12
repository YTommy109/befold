---
id: TASK-361.1
title: サイドバーの行モデルを depth 付きフラット配列へ一本化する（振る舞い不変）
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 01:57'
updated_date: '2026-08-10 02:23'
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
- [x] #1 行の生成が「ルート + 展開集合」を入力とする純粋関数に一本化され、ドリルダウンはその縮退形（展開集合が空）として通っている
- [x] #2 FileListEntry が depth を持ち、depth からインデント量が決まる（表示上はドリルダウン時 depth が全て 0 なので見た目は変わらない）
- [x] #3 visibleEntries の添字 = NSTableView の行番号という不変条件が、複数階層を含む行配列でも成立することがテストで検証されている
- [x] #4 キーボード移動・previewTarget 解決・スクロール追従の既存テストが変更なしで通る（FileListViewTests 13 件 / FileListModelPreviewTargetTests 7 件 / FileListModelScrollTests 3 件）
- [x] #5 UI の見た目と操作は本タスクの前後で変化しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果を反映した実装方針（2026-08-10）

サブエージェントによる設計レビューを 1 回実施。チェックリスト 9 項目のうち 6 件が
実装方針を変える指摘だったため、以下を採用する。

### 1. FileListEntry に depth を足す（デフォルト引数は使わない）

- `private(set) var depth: Int = 0` を追加。**init の引数にはしない**。
- 値を変えられるのは `func indented(to depth: Int) -> FileListEntry` だけ。
- 理由（項目 9）: デフォルト引数だと渡し忘れがコンパイルエラーにならず静かに
  depth 0 になる（TASK-319 と同型。.claude/CLAUDE.md が名指しで禁じている形）。
  実測で `FileListEntry(` は 96 箇所 / 20 ファイルあり、全箇所から設定可能に
  なってしまう。indented(to:) 方式なら既存 96 箇所は無変更で通り（AC #4）、
  depth の書き込み点が構造的に SidebarRowBuilder 1 箇所へ固定される。
- `==` / `hash(into:)` を手書きし、**depth を等値・ハッシュから外す**（項目 9 / 指摘 I）。
  比較対象は url / kind / containsSupportedFile / pathKey（現行の合成と同じ）。
  理由: id(= url) と == の意味を一致させる。FolderListingSource が Equatable で
  `case shared([FileListEntry]?)` を持つ（FolderListingView.swift:7-12）ため、
  depth を等値に含めると FolderListingViewFilterTests.swift:134 が 361.2 以降で
  depth 差だけで落ちる。

### 2. SidebarRowBuilder（新設・純粋関数）

```swift
enum SidebarRowBuilder {
    static func rows(
        parentEntry: FileListEntry?,
        rootChildren: [FileListEntry],
        expanded: Set<String>,
        childrenByPathKey: [String: [FileListEntry]]
    ) -> [FileListEntry]
}
```

- **クロージャではなく、既に材料化された辞書を受け取る**（項目 6 / 指摘 C の変形）。
  同期クロージャだと 361.3 で中身が FileManager 列挙 + containsSupportedFile
  （DirectoryLister.swift:83、フォルダ 1 件ごとにディレクトリ列挙）になったとき、
  呼び出し元が MainActor でも型が何も言わない（TASK-322 と同型）。辞書入力なら
  builder は I/O を構造的に持てず、列挙は必ず呼び出し側（既存の nonisolated
  async 経路）で先に済ませることになる。同期の `listEntries`（テスト用入口）も
  そのまま通せる。
- expanded が空なら出力は `parentEntry + rootChildren` そのもの（全行 depth 0）。
- 展開時は .folder 行の直後に配下を depth+1 で挿入する。
- **訪問済み pathKey 集合を持ち、既出のキーは展開しない**（項目 3・9 / 指摘 D）。
  FileListEntryIndex は「先に現れた行が勝つ」（FileListEntryIndex.swift:22-24）で
  重複を黙って飲み込むため、破れても落ちずに previewTarget が並び順依存になる。
  symlink ディレクトリ経由の循環（a/ -> b/ -> a/）もここで止める。

### 3. appendingOpenFile は「フラット化の前」に置く

- 現状 `entries + [FileListEntry(...)]` で配列末尾に足す（DirectoryLister.swift:67）。
  フラット行配列の末尾は「最後に展開したフォルダの最深部の直後」であり、root 直下の
  ファイルがそこに現れると「行の並び = ツリー構造」が壊れる（項目 2 / 指摘 A）。
- 追記は root の子リスト（rootChildren）に対して行い、**その後にフラット化**する。
  361.1 では出力が変わらないので、いま移すのが最も安い。

### 4. インデントは padding ではなく行内 spacer（項目 3 / 指摘 H）

- サイドバーは行インセットをゼロにして `.contentShape(.rect)` で行全幅をヒット領域に
  している（FileListView.swift:164-172、コメントに「インセット部分をダブルクリック
  したとき選択だけされて移動しない取りこぼしを防ぐ」と明記）。Row の内側に
  leading padding を入れると、その分がヒット領域から外れる。
- `SidebarRowIndent.leadingInset(forDepth:)` を純粋関数として切り出し、Row の
  中身の先頭に固定幅の spacer として置く。GUI は自動テスト対象外のため、
  **depth -> インセット値の対応をユニットテストで押さえる**のが AC #5
  「見た目が変わらない」の唯一の測り方（ModeSegments.modes(isSourceDiffEnabled:) と同じ形）。

### 5. テスト

- 新規 SidebarRowBuilderTests: (a) expanded 空 -> parentEntry + rootChildren と一致・
  全行 depth 0、(b) 1 フォルダ展開 -> 直後に depth 1、(c) 入れ子展開 -> depth 0/1/2、
  (d) 行に現れないキーは無視、(e) 祖先自身のキーが expanded に入っても行が重複せず再帰が止まる。
- 新規 SidebarRowIndentTests: depth 0 -> 0pt（AC #5）。
- **縮退の等価性は本番の入口で測る**（項目 7 / 指摘 F）。builder 同士の比較では
  buildEntries の分割（親移動行の切り出し・.alphabetical のマージ順、
  DirectoryLister.swift:87-95）を壊しても通ってしまう。一時ディレクトリに対する
  `DirectoryLister.listEntries` の出力を **.foldersFirst と .alphabetical の両方**で
  「親移動行が先頭 1 件・以降の並びが従来どおり・全行 depth 0」を検証する
  （.alphabetical は親移動行を merge に含めない分岐があり、分離を誤ると .. がソートに混ざる）。
- 既存 FileListModelScrollTests に depth 混在の行配列のケースを足す（AC #3）。

### 6. 変えないもの

List(model.visibleEntries, selection:) のフラット 1 セクション構造、selectedRow の
「添字 = 行番号」、FileListModel の entries / entriesDirectory / setEntries の
単一ディレクトリ前提、FileListFilter.apply。いずれも 361.2 / 361.4 / 361.5 の担当。

### 7. サブタスクへ申し送る（受け取り側の AC にする）

- 361.2: FolderListingSource == に depth 混在の一覧が載ったときのテスト影響
  （FolderListingViewFilterTests.swift:134）／listingSource の .shared(visibleEntries)
- 361.3: childrenOf の [] が「空フォルダ / 列挙失敗 / 未到着」を区別できること
  （gitStatus の「空 != nil」と同型・FileListModel.swift:146-152 が先例）／
  containsSupportedFile(in:) のコスト上限／展開単位の世代ガード（開始時無効化と
  着地時一致確認の両方。既存 2 系統はディレクトリ 1 つ単位で足りない）
- 361.4: enterSelected（FileListView.swift:384）を展開トグルへ変える判断／
  selectNext・selectPrevious・navigateToParent・firstSelectableEntryURL
- 361.5: 空状態判定 visibleEntries.allSatisfy { $0.kind == .parentNavigation } が
  FileListView.swift:181 と FolderListingView.swift:126 の **2 箇所**にあり、
  片方だけ直すと TASK-320 型になる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-10）

### /review-design の指摘への対応

サブエージェントによるレビュー 9 項目のうち、実装方針を変えたのは 5 件。
1 件（指摘 A: appendingOpenFile をフラット化の前段へ移す）は **検証の結果、移す必要が
無いと判断した**。深さ優先で畳んだ配列の末尾は「最後のルート直下行とその配下すべての
直後」であり、そこは配下を持たない新しいルート直下行が入る位置そのもの。追記される行の
depth は既定の 0 で正しい。DirectoryLister.appendingOpenFile の doc コメントにこの
不変条件を明記した（呼び出し元は SidebarNavigator.swift:185 と FolderListingView.swift:78 の 2 箇所）。

指摘 C（childrenOf を async にする）は、**辞書入力へ変える形で採用**した。async 化だと
同期の listEntries（テスト用入口・DirectoryLister.swift:17-28 に明記）が通せなくなる。
childrenByPathKey: [String: [FileListEntry]] を受ける形なら、builder は I/O を構造的に
持てず、列挙は必ず呼び出し側の非同期経路で先に済む。

指摘 H（padding だとヒット領域が欠ける）は、**前提が成立しないことを確認**した。
contentShape(.rect) は FileListView.swift:172 で行の padding より外側に適用されており、
行ビュー自体の幅は leading padding では変わらないため、ヒット領域は縮まない。
ただしインデント量の純粋関数化（SidebarRowIndent）は AC #5 の唯一の測り方なので採用した。

### 追加・変更したもの

- FileListEntry: private(set) var depth（**init の引数にしない**）+ indented(to:) +
  手書きの == / hash（depth を等値から外す）
- SidebarRowBuilder（新規）: 親移動行 + ルート直下 + 展開集合 + 材料辞書 → depth 付き
  フラット行配列。訪問済み pathKey で循環と重複展開を止める
- SidebarRowIndent（新規）: depth → 左インセット（負値は 0 に丸める）
- DirectoryLister: buildEntries を parentNavigationEntry / childEntries へ分離し、
  SidebarRowBuilder.rows（expanded: []）を通す
- FileListEntryRow: content を切り出し、body で leading インセットを適用

### 検証（実測 2026-08-10）

- swift test --skip Integration --skip FileWatcherTests: **1162 tests / 163 suites 全通過**
  （変更前 1159。新規 15 件のうち 12 件が新規スイート）
- 既存テストの差分は FileListModelScrollTests.swift への **26 行追記のみ、削除ゼロ**。
  FileListViewTests / FileListModelPreviewTargetTests / FileListModelScrollTests /
  FolderListingViewFilterTests / DirectoryListerTests / FileListEntryTests は全て変更なしで通過（AC #4）
- swiftformat --lint: 0 files require formatting（全 8 ターゲット）
- swiftlint: origin/main ベースライン 79 件に対し head 79 件、**diff 空**
  （最初 function_parameter_count が 1 件出たため、再帰の引数 6 個を Flattening 構造体へ畳んだ）
- xcodegen generate 実行済み / xcodebuild build -scheme befold: exit=0, error 0 件
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの行生成を SidebarRowBuilder（ルート + 展開集合 + 材料辞書 → depth 付きフラット配列）へ一本化し、ドリルダウンをその縮退形（展開集合が空）として同じ関数に通した。FileListEntry に depth を足したが init 引数にはせず、indented(to:) 経由でのみ書ける構造にして書き込み点を builder 1 箇所へ固定した（TASK-319 と同型の事故を構造で塞ぐ）。等値・ハッシュからは depth を外し、FolderListingSource の Equatable が深さ差で別物にならないようにした。検証: swift test 1162 件全通過（既存テストは追記 26 行のみで無変更）、swiftlint は origin/main とベースライン差分ゼロ、swiftformat クリーン、xcodebuild build -scheme befold が exit 0。
<!-- SECTION:FINAL_SUMMARY:END -->
