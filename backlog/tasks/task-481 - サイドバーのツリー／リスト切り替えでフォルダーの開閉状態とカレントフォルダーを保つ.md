---
id: TASK-481
title: サイドバーのツリー／リスト切り替えでフォルダーの開閉状態とカレントフォルダーを保つ
status: To Do
assignee: []
created_date: '2026-08-14 10:46'
updated_date: '2026-08-14 13:22'
labels: []
milestone: m-2
dependencies: []
priority: medium
type: feature
ordinal: 698000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーのツリー表示とリスト（ドリルダウン）表示を行き来したときの状態の引き継ぎを決める。

## 現状（実装の裏取り済み）

- ツリーのルートとリストのカレントフォルダーは同じ 1 変数（`BefoldApp/befold/Viewer/FileListModel.swift:11` の `currentDirectory`）。ツリー専用のルート変数は無い。
- モード切り替えでは `currentDirectory` は変わらない（`BefoldApp/befold/App/GlobalDisplayBroadcaster.swift:55-67`）。
- ツリー→リストで展開状態を全破棄している（同 :59-61 → `SidebarExpansion.invalidateAll()`）。さらに `moveCurrentDirectory`（`BefoldApp/befold/App/SidebarNavigator+FolderNavigation.swift:44-50`）がモードを問わずフォルダー移動のたびに展開状態を破棄する。
- 展開状態はウィンドウ単位・メモリのみで永続化は無い（`BefoldApp/befold/App/SidebarExpansion.swift` 冒頭コメント）。

このため「ツリー→リスト→ツリー」と戻すと開閉状態が失われ、またツリーで深い階層のファイルを見ていてもリストへ切り替えるとルートのままになる。

## 決めた仕様

ツリー用のルート変数を新設せず、`SidebarExpansion` が保持する展開集合に「そのときのルート URL」を添えたスナップショットを 1 つ持つ形で実現する（常駐状態と経路を増やさない）。

1. ツリー → リスト: 展開状態を破棄せず `(root: currentDirectory, expandedKeys)` をスナップショット保存し、`currentDirectory` を選択中ファイルの親フォルダーへ移す（未選択ならルートのまま）。
2. リスト → ツリー: 移動先がスナップショット root の配下（または root 自身）なら、root を `currentDirectory` に戻して展開集合を復元し、さらに現在の選択位置までの経路を追加展開してスクロールする。root の外へ出ていた場合はスナップショットを捨て、今の `currentDirectory` を新しいルートとする（元の場所へ引き戻さない）。
3. リストモード中のフォルダー移動では展開状態を破棄しない（`moveCurrentDirectory` の破棄はツリーモード時のみに限定）。ツリーモード中にルート自体が変わった場合は従来どおり破棄する。
4. 永続化はしない（ウィンドウ単位・メモリのみ、現状の設計を踏襲）。

## 関連

- TASK-480 系がサイドバー表示設定を窓ごとのライブ値へ移す作業を含むため、`GlobalDisplayBroadcaster` まわりの実装が競合しうる。着手時に TASK-480.2 / 480.3 の進捗を確認すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ツリーでフォルダーをいくつか開いた状態からリストへ切り替え、再びツリーへ戻すと、開閉状態が切り替え前と同一に復元される
- [ ] #2 ツリーで深い階層のファイルを選択した状態でリストへ切り替えると、そのファイルの親フォルダーがカレントフォルダーになる（ファイル未選択のときはルートのまま）
- [ ] #3 リストでスナップショット root の配下へ移動してからツリーへ戻すと、ルートはスナップショットの root に戻り、保存済みの開閉状態に加えて現在の選択位置までの経路が展開され、選択行が可視になる
- [ ] #4 リストでスナップショット root の外（配下でない場所）へ移動してからツリーへ戻すと、その移動先が新しいルートになり、元の root へ引き戻されない
- [ ] #5 リストモード中にフォルダーを移動しても、保存済みの展開スナップショットは破棄されない
- [ ] #6 ツリーモード中にルート自体が変わったときは展開状態が破棄される（従来どおり）
- [ ] #7 上記の状態遷移をユニットテストで担保し、修正を戻すと落ちることを確認する
- [ ] #8 展開状態が UserDefaults 等へ永続化されていないこと（ウィンドウを閉じると失われる現状の設計）が変わっていない
<!-- AC:END -->
