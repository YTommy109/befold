---
id: TASK-361.4
title: サイドバーにツリー展開 UI・キー操作・表示モードの永続化を追加する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 01:58'
updated_date: '2026-08-10 03:49'
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
- [x] #1 サイドバーの表示モードとして、従来のドリルダウンとツリー展開を選べる
- [x] #2 ツリー展開では開閉三角でサブフォルダをその場に展開でき、複数のフォルダを同時に開いたままにできる
- [x] #3 選んだ表示モードが再起動後も保持される
- [x] #4 ツリー展開でのキーボード操作（選択の上下移動・展開/畳む・ファイルを開く）が定義され、テストで検証されている
- [x] #5 選択したファイルへのスクロール追従がツリー展開時も正しく動く
- [x] #6 cmd+1〜4 に新しい割り当てを追加していない
- [x] #7 従来のドリルダウン表示の既存の振る舞いと既存テストが壊れていない
- [x] #8 enterSelected（FileListView.swift:377-391）の .folder に対する動作を「フォルダへ入る」から「展開トグル」へ変えるかを決め、selectNext / selectPrevious（:345-375）・navigateToParent（:393-399）・firstSelectableEntryURL（FileListModel.swift:279-281）の各消費点をツリー前提で棚卸ししている
- [x] #9 展開状態の粒度は TASK-361.3 が「ウィンドウごと・メモリのみ」（SidebarExpansion を SidebarNavigator が保持）と決めた。永続化する場合は SidebarStateStore のファイルごとのパターン（PathKeyedDictionary）に倣い、アプリ全体で共有しない
- [x] #10 開閉三角の見た目が、(a) 展開したが子が未到着（SidebarExpansion.Children.loading）、(b) 展開済みで空（.loaded([])）、(c) 名前フィルタ・変更のみ表示で子が全部消えた、の 3 つを区別できる
- [x] #11 cmd+1〜4 は TASK-356 がプレビューの表示モードへ割り当て済み（Done）のため、サイドバーの表示モード切替には使わない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果を反映した実装方針（2026-08-10）

レビューの指摘 A-1/A-2/A-3 は **1 つの設計変更で同時に解ける**ため、そちらを採用した。

### 開閉三角の状態は「行に焼き込む」

SidebarExpansion は意図的に @Observable ではない（描画の真実の源を FileListModel.entries の
1 本に保つため）。View からクロージャ越しに読ませても再描画が飛ばない。そこで
FileListEntry に disclosure を持たせ、depth と同じく **init 引数にせず**
disclosing(_:) 経由でのみ書ける形にした。書けるのは SidebarRowBuilder と
SidebarDisclosureResolver の 2 箇所だけ。

- nil = ドリルダウン / プレビュー内フォルダー一覧 → 従来の見た目のまま（FolderListingView は無改修）
- SidebarExpansion.material に **loading 集合**を追加（.loaded だけだと「読み込み中」の材料が届かない）

### AC #10 の 3 状態

判定を「配列が空かどうか」でしない。SidebarDisclosure.state は
loadedChildCount を **Int?** で受け、nil（未到着）と 0（空フォルダ）を型で分ける。
「絞り込みで 0」は行を組む時点では分からないため、絞り込み後の配列に対して
SidebarDisclosureResolver が確定させる（届いた子はあるのに可視 0 → isFiltered: true）。

### キー操作は純粋関数へ

SidebarKeyAction.action(key:modifiers:target:mode:) に切り出し、handleKey は返った
enum を 1 回 switch するだけ。ダブルクリックも doubleClickAction で同じ判断源を通す
（別々に分岐を書くと片方だけツリー対応する TASK-320 型の穴になる）。
**ドリルダウン側の割り当てが変わっていないことは、この純粋関数のテストが唯一の測り方。**

### 全ウィンドウ反映（レビューで判明した欠落）

表示モードは行配列そのものを変えるため、ViewerWindowManager.toggleSidebarLayoutMode() から
全ウィンドウへ流す。tree → drillDown では各ウィンドウで expansion.invalidateAll() を先に呼ぶ
（呼ばないと、モードを戻しても展開したままの行が残る）。行の組み直しは refreshFileList の
経路へ合流させる（rebuildRows を直接叩くと「ルートの一覧が届く前に組み直さない」不変条件を迂回する）。

### 決めたこと

- **展開状態は永続化しない**（ウィンドウごと・メモリのみ）。AC #3 が求めるのは表示モードの
  永続化であって展開状態ではない。永続化するとキーの上限・掃除という別の設計が要る
- **.. 行はツリーでも出す**。出さないとルートより上へ行く手段がキーボードから消える
- **delete はツリーでも「ルートを 1 つ上げる」のまま**。ツリーでは ← が畳みになるため
- ショートカットは付けない（⌘1〜4 は TASK-356 が割り当て済み。AC #6 / #11）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-10）

### AC #8 の棚卸し結果

- **enterSelected**: ツリーでは .folder に対して「展開トグル」へ変えた（ドリルダウンは
  「フォルダへ入る」のまま）。判断は SidebarKeyAction へ集約し、ダブルクリックも同じ関数を通す
- **selectNext / selectPrevious**: **変更不要**。visibleEntries の前後添字なので、
  フラット配列に深い行が並ぶだけで Finder のリスト表示と同じ挙動になる
- **navigateToParent**: ツリーでは ← が畳みになるが、delete は従来どおりルートを上げる
- **firstSelectableEntryURL**: **変更不要**（.parentNavigation 以外の先頭 = ルート直下の先頭）

### swiftlint 対応で分割したファイル

新規違反ゼロにするため 3 ファイルへ分割した。

- FileListView+Keyboard.swift（file_length / type_body_length / cyclomatic_complexity）
- MainMenuBuilder+ViewMenu.swift（type_body_length）。FeatureGate を参照するため
  .swiftlint.yml の feature_gate_direct_reference allowlist と FeatureGate.swift の
  doc 列挙を両方更新した（FeatureGateEnumerationTests が両方を突き合わせている）
- SidebarExpansion.Material（large_tuple 回避のため 3 要素タプルを構造体へ）

### 検証（実測 2026-08-10）

- swift test（**統合テストを含む全件**）: **1310 tests / 193 suites 全通過**（変更前 1183）
- swiftlint: origin/main とのベースライン比較で **真の新規違反ゼロ**
  （ルール×ファイルの組で比較。件数だけ増減した既存違反は除く）。
  むしろ MainMenuBuilder の function_body_length と FileListView の type_body_length の
  2 件が解消した
- swiftformat --lint: 0 件
- xcodegen generate 実行済み / xcodebuild build -scheme befold: exit=0
- Localizable.xcstrings に menu.view.sidebarTreeLayout を追加（既存の並び順を保ち、
  近縁キー menu.view.showChangedFilesOnly の直前へ挿入）

### 実機確認について

ゲート ON 側は dev リリースの dogfood、OFF 側は次回 stable リリースで担保する。
ローカルの Release ビルドは署名の Team ID が合わず起動できないため（.claude/CLAUDE.md）、
OFF 側の振る舞いは SidebarKeyAction / SidebarRowBuilder / SidebarDisplayPreference の
ゲート値を引数で受けるテストで押さえた。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーにツリー展開の UI・キー操作・表示モードの永続化を追加した。開閉三角の状態は SidebarRowBuilder が行へ焼き込み（disclosure は init 引数にせず disclosing(_:) 経由のみ）、絞り込み後の「見えている子が 0」は SidebarDisclosureResolver が確定させることで、未到着 / 空フォルダ / 絞り込みで 0 の 3 状態を区別する。キー操作は表示モードを引数で受ける純粋関数 SidebarKeyAction に集約し、ダブルクリックも同じ判断源を通す。表示モードは SidebarDisplayPreference へ永続化し、ViewerWindowManager 経由で全ウィンドウへ反映する（tree→drillDown では展開状態も破棄）。展開状態自体は永続化しない（ウィンドウごと・メモリのみ）。検証: swift test 全 1310 件通過、swiftlint は真の新規違反ゼロ（既存違反 2 件が解消）、xcodebuild exit 0。
<!-- SECTION:FINAL_SUMMARY:END -->
