---
id: TASK-442.1
title: サイドバーの行生成を 1 箇所へ一本化する
status: Done
assignee: []
created_date: '2026-08-11 07:34'
updated_date: '2026-08-11 08:08'
labels: []
dependencies: []
parent_task_id: TASK-442
ordinal: 673000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SidebarExpansion.swift:15 の doc は「行の生成は SidebarNavigator の 1 箇所だけが行う」と書いているが、実態は 2 箇所。DirectoryLister.buildEntries (DirectoryLister.swift:96) が「展開集合が空」の縮退形で SidebarRowBuilder.rows を通して行を組み、それを SidebarNavigator+Expansion.applyRows (:25-27) が kind == .parentNavigation で分解し直して再度 SidebarRowBuilder.rows へ通している。1 回の列挙で行の組み立てが 2 回走っている。

TASK-442 の分割で行の組み立てを独立型へ移すが、その型の doc に「1 箇所」と書いた時点で嘘になるため、先にここを片付ける。

方針の候補: DirectoryLister が組み立て済みの [FileListEntry] を返すのをやめ、(parentEntry, rootChildren) を返す形にして、組み立ては呼び出し側の 1 箇所だけにする。appendingOpenFile / listEntriesAsync / childEntriesAsync のシグネチャと、それらを直接使っているテストへの波及を調べた上で決めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーの行の組み立て (SidebarRowBuilder.rows の呼び出し) がプロダクトコードで 1 箇所だけになっている
- [x] #2 その事実をソース走査で検証するテストがある (ViewerBridgeTests のソース突き合わせと同じ流儀)。呼び出しを 2 箇所目へ増やすと落ちる
- [x] #3 SidebarExpansion.swift の doc の記述が実態と一致している
- [x] #4 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
採用方針: 材料型 DirectoryListing を導入し、行の畳み込みを 1 メソッドへ閉じる（最小案「素の連結へ置き換えるだけ」はユーザー判断で不採用。applyRows の kind 分解と rebuildRows の depth==0 復元が残るため）。

不変条件:
- I1: SidebarRowBuilder.rows を呼ぶプロダクトコードは DirectoryListing.swift の 1 箇所だけ
- I2: 組み立て済み行配列を分解して材料へ戻す経路が無い（kind == .parentNavigation での分割、depth == 0 でのフィルタを行の再組み立てに使わない）
- I3: fileListModel.setEntries を呼ぶプロダクトコードは applyRows の 1 箇所だけ

ステップ（各段でビルド・テストが通る単位）:
1. SidebarExpansion.Material を SidebarRowBuilder.Material へ移設し Sendable を付ける（@MainActor 隔離を外し、非 MainActor テストから rows を呼べるようにするため）
2. DirectoryListing を新規追加。rows(material:showsDisclosure:) と appendingOpenFile を実装し、SidebarRowBuilder.rows の呼び出しをここへ持つ
3. DirectoryLister の入口を listing / listingAsync へ差し替え、buildEntries を削除。FolderListingView:159 を .rows() へ。DirectoryLister 系テスト 3 本を追随
4. SidebarNavigator の配管（directoryLister の型 / performListing の onApplied / refreshFileList / +FolderNavigation）と、スタブを持つテスト群を追随
5. applyRows / rebuildRows を書き換え lastListing（private(set)）を導入。分解 2 箇所を削除
6. doc の是正: SidebarExpansion.swift:15、DirectoryLister.childEntriesAsync、SidebarNavigator.childrenLister の「畳んだ形を返す」記述
7. I1/I2/I3 のソース走査テストを追加（FeatureGateEnumerationTests の #filePath 走査の流儀）
8. 型グループ行数ベースライン更新、swift test、swiftlint 差分ゼロ確認

注意点（実装時に落としやすい）:
- SidebarNavigatorFolderNavigationTests.swift:179 のスタブは配列に .parentNavigation を含む。rootChildren へ流さず parentEntry へ移す（SidebarRowBuilder は rootChildren の kind を見ない）
- appendingOpenFile が末尾でよい理由のコメント（DirectoryLister.swift:59-64）を DirectoryListing へ持っていく
- FolderListingView の .shared 経路は配列版 appendingOpenFile のまま残す（DirectoryListing 版へ寄せると経路が壊れる）
- lastListing と entriesDirectory は applyRows 内の同一同期区間で書く
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装（構造案）:
- DirectoryListing（parentEntry + rootChildren の材料型、Sendable/Equatable）を新設。SidebarRowBuilder.rows を呼ぶプロダクトコードはこの型の rows(material:showsDisclosure:) 1 箇所だけになった。
- DirectoryLister.listEntries / listEntriesAsync → listing / listingAsync（戻り値 DirectoryListing）。buildEntries は buildListing になり、行を作らなくなった。
- SidebarNavigator.applyRows が DirectoryListing を受ける形になり、kind == .parentNavigation による再分解を撤去。lastListing を保持して rebuildRows の depth == 0 復元も撤去。この 2 つは applyRows の引数型が [FileListEntry] を受け付けないことで構造的に塞がっている（コンパイルが通らない）。
- SidebarExpansion.Material を SidebarRowBuilder.Material へ移設し Sendable 化。@MainActor クラスのネスト型のままだと畳み込み自体が MainActor を要求してしまうため。
- FolderListingView は listingAsync(...).rows() で従来と同じ行配列を得る（cachedEntries の型も .shared 経路も無変更）。

判断の記録:
- 最小案（DirectoryLister の縮退呼び出しを素の連結へ置き換えるだけ）は AC #1 を満たすが、applyRows の kind 分解と rebuildRows の depth==0 復元が残るため、ユーザー判断で不採用。
- 不変条件 I2「分解して材料へ戻す経路が無い」はソース走査ではなく型で担保した。kind == .parentNavigation / depth == 0 の出現はプレビューの空状態判定や FileListModel の .shared 経路など正当な用途が複数あり、走査にすると除外リストのほうが重くなる。
- SidebarNavigatorFolderNavigationTests のスタブは配列に親移動行を混ぜていた。SidebarRowBuilder は rootChildren の kind を見ないため、そのまま流すと二重に並ぶ。parents: [String: URL] を別引数にして分離した。

検証:
- swift test: 1401 tests / 206 suites すべて成功（新規 2 件を含む）
- 新規テストの検知確認（実測）: FolderListingView へ SidebarRowBuilder.rows の 2 箇所目を一時的に足すと SidebarRowAssemblySingleSourceTests が失敗することを確認した
- swiftlint: HEAD を git archive で別ディレクトリへ展開して比較。新規・解消ともにゼロ（SidebarNavigatorListingCoherenceTests に一度 function_body_length の新規が出たため、スタブを fileListing ヘルパーへ畳んで解消済み）
- 型グループ行数: SidebarNavigator が 611 → 615（+4、lastListing とその doc）。TASK-442 本体がこの型の分割を目的としているため、ここでは scripts/check-type-group-size.sh --update-baseline でベースラインを更新した
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの行の組み立てが 1 回の列挙で 2 回走っていた問題を、材料型 DirectoryListing の導入で解消した。DirectoryLister は行ではなく (parentEntry, rootChildren) の材料を返すようになり、畳み込みは DirectoryListing.rows の 1 箇所だけになった。applyRows が材料型を受けることで、kind == .parentNavigation による再分解と rebuildRows の depth == 0 復元は型レベルで不可能になっている。SidebarRowAssemblySingleSourceTests がソース走査で「畳み込み 1 箇所・setEntries 1 箇所」を数え、2 箇所目を足すと落ちることを実測で確認した。swift test 1401 件成功、swiftlint は HEAD 比で差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
