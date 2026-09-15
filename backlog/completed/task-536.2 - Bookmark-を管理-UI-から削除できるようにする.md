---
id: TASK-536.2
title: Bookmark を管理 UI から削除できるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-21 07:27'
updated_date: '2026-09-12 13:59'
labels: []
milestone: m-9
dependencies:
  - TASK-536.1
parent_task_id: TASK-536
priority: medium
type: feature
ordinal: 778000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在、存在するファイルのブックマークを外す手段は、そのファイルを開いてツールバー／View メニューでトグルするか、ファイルが見つからない場合に「Remove from Bookmarks」（`FileNotFoundUI.swift:16-42`）や一括の Missing Bookmarks 削除（`MissingBookmarksPruner.swift`、`MissingBookmarksAlerts.swift`）を使うかに限られる。ブックマーク一覧（管理 UI）側から、対象ファイルを開かずに個々のブックマークを直接削除できる導線が無い。

ブックマーク一覧・管理 UI 上で、個々のブックマークを選択して削除できるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 管理パネル（Bookmarks > Edit Bookmarks…）から、対象ファイルを開かずに個々のブックマークを削除できる（行の右クリック「Remove Bookmark」と、選択中の行への Delete キー）
- [x] #2 削除は BookmarkStore 経由で即座に永続化され、開いている全ウィンドウのツールバー（ブックマークボタン）が追随する
- [x] #3 既存の Missing Bookmarks 系の削除導線（MissingBookmarksPruner／FileNotFoundUI）と重複せず整合する（パネルは stat をせず欠落判定を持たない。それらの経路で消えた分はパネルが key になったときに取り直す）
- [x] #4 モデルの削除操作（ストアから消える・一覧が更新される・onChange が 1 回呼ばれる）をユニットテストで担保する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BookmarkManagerModel に onChange（全窓ツールバー再同期）を必須引数で足し、remove(_:) を追加（store.remove → refresh → onChange）
2. HostedPanelPresenter.makeBookmarksController で onChange に windowManager?.display.refreshAllToolbars() を配線
3. BookmarkManagerView: List(selection:) で単一選択、右クリックに「Remove Bookmark」（既存キー menu.bookmarks.remove を再利用）、.onDeleteCommand で選択行を削除、削除後は選択を解除
4. BookmarkManagerModelTests（新規）: remove でストアから消える / entries が更新される / onChange が 1 回 / 未登録パスの remove は onChange を呼ばない。xcodegen generate
5. 検証: swift test、swiftformat、swiftlint ベースライン、xcodebuild、実機で右クリック削除 → ツールバーの追随

## /review-design（チェックリスト）
- 1 真実の源: 削除は正規化パスをキーにストアへ委ねる。選択 id は BookmarkEntry.path（一意）
- 2 不変条件: 単一 writer は不変（パネルも AppStores の同じインスタンス）。窓側の追随は GlobalDisplayBroadcaster.refreshAllToolbars（CLI 追加と同じ経路）
- 3 消費経路: メニューは表示直前に読み直す / ツールバーは refreshAllToolbars / Quick Open は開くたびに読む / Pruner は独立。兄弟: FileNotFoundUI の削除はツールバーを再同期しないが、その窓は開けていないので対象外
- 4 表示: 0 件は既存の空状態。削除後は選択を nil に戻す
- 5/6/8: ライフサイクル・高頻度経路・非同期の変更なし
- 7 測るもの: モデルのテストがストアの中身と onChange 回数を直接見る
- 9 粒度: onChange は既定値なし（渡し忘れがコンパイルエラー）
- 10 行数: BookmarkManagerModel 35 → 約 50、BookmarkManagerView 83 → 約 110、HostedPanelPresenter +3。モデルの注入クロージャは open + onChange の 2
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-09-12）

BookmarkManagerModel に remove(_:)（store.remove → refresh → onChange）と onChange（必須引数。HostedPanelPresenter が GlobalDisplayBroadcaster.refreshAllToolbars を配線）を足した。ビューは List(selection:) の単一選択、右クリック「Remove Bookmark」（既存キー menu.bookmarks.remove を再利用）、.onDeleteCommand で選択行を削除。確認ダイアログは挟まない（⌘D で付け直せる）。別名変更は集合を変えないので onChange を呼ばない。

副産物: 表示順の比較を localizedStandardCompare（Finder と同じ、大文字小文字を区別しない）に変えた。素の < だと別名 "Zulu" が "diagram.mmd" より前に来る（BookmarkManagerModelTests で実測して判明）。

検証（実測）:
- swift test --skip Integration --skip FileWatcherTests: 1911 tests / 311 suites 通過（新規 BookmarkManagerModelTests 4）
- swiftlint ベースライン差分: main 48 / HEAD 48、新規 0・解消 0。swiftformat 0 files。型グループ閾値以内（BookmarkManagerView 100 / Model 53）
- xcodebuild build -scheme befold: 成功
- 実機（Debug、実 defaults）: 文書窓で Bookmark → パネルで右クリック → Remove Bookmark → defaults から消え、文書窓の Bookmarks メニューのトグル文言が「Remove Bookmark」から「Bookmark」へ戻った（＝ isBookmarked の再同期が届いている）。ツールバーアイコンそのもののスクリーンショットは取れなかった（別アプリの窓を撮ってしまった）が、同じ refreshUIState を通る
- native-app-design.md: BookmarkManagerModel の行は 536.1 で追加済みで、削除の追加は行の記述（各操作はストアへ書いてから取り直す）に含まれるため更新不要
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
管理パネルから個々のブックマークを削除できるようにした（右クリック「Remove Bookmark」/ 選択行への Delete キー）。削除は BookmarkStore 経由で即時永続化し、onChange → refreshAllToolbars で開いている全窓のブックマーク状態を追随させる。パネルは stat をせず、Missing Bookmarks 系の経路とは独立（それらで消えた分は key になったときに取り直す）。検証: swift test 1911 件通過、swiftlint 差分 0、xcodebuild 成功、実機で削除後に文書窓のトグルが「Bookmark」へ戻ることを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
