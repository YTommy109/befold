---
id: TASK-481
title: サイドバーのツリー／リスト切り替えでフォルダーの開閉状態とカレントフォルダーを保つ
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-08-14 10:46'
updated_date: '2026-08-15 07:24'
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
- [x] #1 ツリーでフォルダーをいくつか開いた状態からリストへ切り替え、再びツリーへ戻すと、開閉状態が切り替え前と同一に復元される
- [x] #2 ツリーで深い階層のファイルを選択した状態でリストへ切り替えると、そのファイルの親フォルダーがカレントフォルダーになる（ファイル未選択のときはルートのまま）
- [x] #3 リストでスナップショット root の配下へ移動してからツリーへ戻すと、ルートはスナップショットの root に戻り、保存済みの開閉状態に加えて現在の選択位置までの経路が展開され、選択行が可視になる
- [x] #4 リストでスナップショット root の外（配下でない場所）へ移動してからツリーへ戻すと、その移動先が新しいルートになり、元の root へ引き戻されない
- [x] #5 リストモード中にフォルダーを移動しても、保存済みの展開スナップショットは破棄されない
- [x] #6 ツリーモード中にルート自体が変わったときは展開状態が破棄される（従来どおり）
- [x] #7 上記の状態遷移をユニットテストで担保し、修正を戻すと落ちることを確認する
- [x] #8 展開状態が UserDefaults 等へ永続化されていないこと（ウィンドウを閉じると失われる現状の設計）が変わっていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
【/review-design 実施済み・反映版】

前提の訂正: タスク記述の GlobalDisplayBroadcaster.swift:55-67 は TASK-480.3 で削除済み。切り替えの現在地は SidebarListingCoordinator.applyDisplayChange の .toggleLayoutMode（SidebarListingCoordinator.swift:93-100）。全 UI 経路は SidebarNavigator.applyDisplayChange（SidebarNavigator.swift:137-139）に合流済み（rg で確認、直呼びは無し）。

単純化の採用（裏取り済み）: スナップショット構造体は作らない。applyRows は既にドリルダウンで展開材料を無視する（SidebarTreePresenter.swift:66-72「展開状態が残っていても行は 1 階層ぶんに戻る」）ため、ツリー→リストで invalidateAll() を呼ぶのをやめて生きた展開集合を残し、SidebarExpansion に snapshot root URL（Optional）1 個だけを足す。

設計レビューの主要指摘と対応:
- (項目3/6) reloadExpandedChildren は performListing の頭で毎回走る（SidebarListingCoordinator.swift:169）。drillDown で展開を残すと不可視サブツリーを refresh のたびに再列挙する → presenter 側で layoutMode == .tree ゲート（applyRows と同じ読み方）。
- (項目5) 復元時の refresh で invalidateChildren が走ると、TASK-451 のガード（現在の一覧に行が無いキーは再読込しない）により子が .loading で固まる。→ 復元では保存済み子リストで即描画し、子の再読込は次回の通常 refresh に任せる。実現は isTree ゲート + 発行順（復元の move と refresh 発行を layoutMode 更新前=drillDown のうちに行う等）。stuck .loading を再現するテストを先に書く。
- (項目5) 順序: →drillDown は snapshot 記録 → モード更新 → 選択ファイルの親へ moveCurrentDirectory（破棄されない）→ refresh。→tree は配下判定 → 配下なら drillDown のうちに moveCurrentDirectory(root) → モード更新 → refresh → 選択の祖先を expandFolder で追加展開。配下外なら discardExpansion → モード更新 → refresh。
- (項目2) 不変条件の維持: currentDirectory の書き換えは moveCurrentDirectory 経由のまま（TASK-465）。reveal は expandFolder の既存経路のみ（SidebarRowAssemblySingleSourceTests が数える setEntries/rows 呼び出し箇所を増やさない）。presenter は選択・currentDirectory を書かない契約を維持。
- (項目10・実測) 閾値 400 に対し SidebarNavigator 群 384 / FileListModel 群 396。→ 受け皿: 切替の前後処理（snapshot 保存・復元判定・move・reveal 起動）は新協力型（例: SidebarLayoutTransition、SidebarNavigator.init 内でのみ生成、moveCurrentDirectory へは attach の weak 参照。責務=モード切替の遷移方針で、行数回避の extension 分割ではない）。スクロール再要求は SidebarTableFocuser に「行が現れるまで保持する pending スクロール」として置く（FileListModel は setEntries からの retry 呼び出し数行のみ。選択復元時の追従改善にもなる既存意図の延長）。
- (項目8) reveal の子リスト着地は既存の epoch/世代ガードに乗る。pending スクロールは新規 scrollIntoView 要求で上書き・成功で消える一回性。選択 nil のときは retry しない。
- (項目9) snapshot は SidebarExpansion.invalidateAll 内で必ず nil（構造的担保）+ そのテスト。配下判定は既存 3 例（DirectoryLister.isWithinHome / SidebarGitStatus.covers / SidebarExpansion.collapse）と同じ「== か hasPrefix(key + \"/\")」規則。
- (項目1) 復元可否は snapshot root の Optional で判定（expandedKeys の空とは独立。展開ゼロでも root は戻す）。
- 選択の保持は既存経路で成立: matchingEntryURL は不一致なら元 URL を返す（FileListEntryIndex.swift:72）ため復元直後も選択は消えない。ハイライトは子リスト着地で自然に出る。スクロールのみ pending 機構で再要求。

実装手順（TDD）:
1. SidebarExpansion: snapshotRoot 追加 + invalidateAll で nil + 配下判定ヘルパー共通化（テスト先行: SidebarExpansionTests）
2. SidebarTreePresenter: reloadExpandedChildren の isTree ゲート + snapshot API の薄い委譲
3. SidebarTableFocuser: pending スクロール（行が現れるまで保持）+ FileListModel.setEntries からの retry
4. 新協力型で切替遷移を実装、SidebarNavigator.applyDisplayChange から toggle だけ委譲。coordinator の invalidateExpansion 行を撤去
5. moveCurrentDirectory の discardExpansion を layoutMode == .tree 限定に（doc 更新）
6. 状態遷移テスト AC#1-#6（実 temp dir 使用、makeIsolatedDefaults / SidebarNavigatorStubHost / AsyncGate / awaitSettled）。SidebarPostSwitchSyncTests :116-130 / :154-170 は前提モードを tree に明示し、drillDown で破棄されない対のテストを追加
7. 実装時確認: SidebarKeyAction が drillDown で expand を呼ばないこと / テストが listing.applyDisplayChange を直叩きしていないこと / AC#8 は rg で UserDefaults 参照なしを確認し Notes へ
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。採用した方針と検証:

【単純化】起票時仕様の「(root, expandedKeys) スナップショット構造体」は作らず、ツリー→リストで invalidateAll() を呼ぶのをやめて生きた SidebarExpansion を温存し、SidebarExpansion に snapshotRoot(URL?) 1 個だけを追加した。成立根拠: applyRows がドリルダウンで展開材料を渡さない(SidebarTreePresenter.applyRows)ため、温存しても表示に出ない。復元は moveCurrentDirectory(root) + 選択までの経路の expandFolder で、状態のコピー/復元は発生しない。

【構成】切り替えの前後処理(記録・復元判定・カレント移動・経路展開)は新協力型 SidebarLayoutTransition(navigator.init 内でのみ生成、weak navigator + attach)。ライブ値更新・既定値書き戻しは従来どおり SidebarListingCoordinator.applyDisplayChange の 1 本を通る。切り替え時の二重 refresh は performListing の世代ガードが古い方を捨てる(同一同期区間で発行するため決定的)。スクロールは SidebarTableFocuser の pending スクロール(行が現れるまで保持、setEntries から retry)で既存経路に乗せた。reloadExpandedChildren はドリルダウン中スキップ(不可視サブツリーの再列挙防止)。子リストの鮮度はツリー復帰後の次回 refresh で追いつく(トグル直後は温存した子で即描画)。

【検証】全 1554 テスト成功(swift test)。xcodebuild build 成功。swiftlint は origin/main ベースライン比で新規ゼロ(一度 opening_brace 1 件が出たが多行 if 条件を変数抽出で解消)・解消もゼロ。型グループは SidebarNavigator 399 / FileListModel 399(いずれも上限 400 まで残り 1 行。次にこのグループへ触るタスクの冒頭で分割を検討すること)。「修正を戻すと落ちる」実測 3 点: (1) トグルの遷移委譲を listing 直呼びへ戻す → 遷移テスト 4 件失敗 (2) moveCurrentDirectory の破棄を無条件へ戻す → AC#5 テスト含む 2 件失敗 (3) setEntries の retryPendingScroll を消す → スクロール再試行テスト失敗。いずれも復元後に全件成功。

【責務レビュー】responsibility-reviewer 実施。重大 1 件(discardExpansion の doc が旧設計のまま) → 同タスク内で修正済み。軽微: SidebarTreePresenter ヘッダに snapshot 中継の 1 文を追記済み / 型グループ残り 1 行の件は上記のとおり記録。SidebarLayoutTransition は独立した責務・依存の向きは既存パターン(attach)と整合、との評価。

【AC#8 の根拠】SidebarExpansion / SidebarLayoutTransition / SidebarTreePresenter に UserDefaults 参照なし(rg で 0 件)。snapshotRoot は invalidateAll で展開集合と同時に消える(構造的担保 + テスト invalidateAllClearsSnapshotRoot)。

native-app-design.md のサイドバー節に切り替え時の引き継ぎ仕様と SidebarLayoutTransition を追記済み(markdownlint 0 件)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ツリー⇄リスト切り替えで開閉状態とカレントフォルダーを引き継ぐようにした。展開集合はコピーせず温存し、SidebarExpansion に snapshotRoot を 1 個追加。遷移方針は新協力型 SidebarLayoutTransition に置き、moveCurrentDirectory の展開破棄をツリー表示時のみに限定、選択までの経路展開と pending スクロール(SidebarTableFocuser)で選択行を可視化。検証: 新規テスト 12 件(遷移 6・SidebarExpansion 4・スクロール 2)を含む全 1554 テスト成功、swiftlint 新規ゼロ、修正を戻すと落ちることを 3 点で実測。
<!-- SECTION:FINAL_SUMMARY:END -->
