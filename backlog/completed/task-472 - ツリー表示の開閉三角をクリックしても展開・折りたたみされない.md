---
id: TASK-472
title: ツリー表示の開閉三角をクリックしても展開・折りたたみされない
status: Done
assignee:
  - '@claude'
created_date: '2026-08-13 08:25'
updated_date: '2026-08-13 10:07'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 693000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーのツリー表示(FeatureGate.isSidebarTreeEnabled 配下)で、フォルダー行の左に出る開閉三角(FileListEntryRow の disclosureIndicator, BefoldApp/befold/Viewer/FileListEntryRow.swift:42-)をクリックしても何も起きない。三角は Image を並べているだけで、タップを受け取る仕組みが無い。

Finder は開閉三角のシングルクリックでその場で展開・折りたたみを行い、行本体のクリック(選択)とは区別する。befold も同じ操作感に合わせたい。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ツリー表示でフォルダー行の開閉三角をシングルクリックすると、その場で展開・折りたたみが切り替わる
- [x] #2 三角のクリックは行本体のクリック(選択・フォルダーへの移動)を発火させない
- [x] #3 折りたたみ状態が .collapsed / .expanded / .loadingChildren / .expandedEmpty / .expandedFailed のいずれでも、クリック対象領域が三角の表示位置と一致している
- [x] #4 展開・折りたたみのトグルを担う処理がユニットテストで ON/OFF 両方向について押さえられている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarRowIndent に開閉三角の幅の定数 (disclosureWidth = 12) と、行内 x 座標が三角の領域かを返す純粋関数を足す。FileListEntryRow の .frame(width:) も同じ定数を参照させ、表示位置と当たり判定の知識を 1 箇所に閉じる（AC#3）。
2. SidebarKeyAction.disclosureToggleAction(target:) を足す。Target(entry:) の既存 isExpanded 導出をそのまま使い、展開判定を複製しない。展開済み→.collapse / 畳み済み→.expand（AC#4）。
3. FileListView に internal な純粋メソッドを置き、(entry, タップ位置 x) から動作を返す。**座標だけで決めず、entry.disclosure != nil を先に見る**（三角の出ない行=ドリルダウン表示・FolderListingView の左端クリックの誤爆を防ぐ）。handleKey と同じくテストから直接呼べる形にする。
4. 行のジェスチャを TapGesture → SpatialTapGesture へ差し替え、シングル・ダブルの**両方**に同じ領域判定を通す。三角上のシングルタップは開閉のみ（選択を動かさない = AC#2）、三角上のダブルタップは無視する（片方だけに足すと 1 操作で 3 回トグルされる）。entries を差し替える経路なので既存の DispatchQueue.main.async の遅延は維持する。
5. ユニットテスト: (a) 領域判定を depth 0/1/2 と境界値で、(b) disclosureToggleAction を全 disclosure ケースで ON/OFF 両方向、(c) FileListView のメソッドで「三角の無い行では左端でも開閉が起きない」「三角上では選択が動かない」を押さえる。
6. dev ビルドで実機確認（三角クリックでの開閉 / 行本体クリックの選択が従来どおり）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 判定を 2 つの純粋関数へ切り出し、行の 1 経路に集約した。
- SidebarRowIndent: disclosureWidth / rowHorizontalPadding の定数と isWithinDisclosure(offsetX:depth:)。FileListEntryRow の .frame(width:) も同じ定数を参照する（状態ごとに frame を書かず共通ラッパ 1 箇所に集約）。
- SidebarKeyAction.disclosureToggleAction(target:): Target(entry:) の既存 isExpanded 導出をそのまま使い、展開判定を複製しない。
- FileListView.disclosureAction(for:atX:): 座標の前に entry.disclosure != nil を見る。行の TapGesture を SpatialTapGesture へ差し替え、シングル・ダブルの両方に同じ領域判定を通した。三角上のシングルは開閉のみ（選択を動かさない）、三角上のダブルは無視（片方だけだと 1 操作で 3 回トグルされる）。

**子ビュー側にジェスチャを足す案は採らなかった。** 行の修飾は .simultaneousGesture なので、子が取っても行のタップが同時に発火して選択まで走る。

/review-design の結果、当初案から 3 点修正した（座標だけで決めない / ダブルクリック経路も同じ判定を通す / FileListEntryRow にクロージャを足さず FileListView の internal メソッドへ集約してテスト可能にする）。

検証:
- swift test 1384 件パス（210 suites）。
- テストが効いていることを確認: disclosureAction の disclosure nil ガードを外すと『三角の無い行では、三角の位置をクリックしても開閉しない』が 2 件の issue で落ちる。
- swiftlint: origin/main とのベースライン差分ゼロ（真の新規・解消ともに空）。
- 実機（Debug ビルド、CGEvent で実マウスクリックを送出、スクリーンショットで確認）: depth 0 の三角クリックで展開→再クリックで折りたたみ、選択は root.mmd のまま動かない。depth 1（alpha/deep）の三角も同様に展開でき、選択は動かない。三角の無いファイル行の同じ x 位置をクリックすると従来どおり選択＋表示切り替えが起きる。行本体のダブルクリック（beta）も従来どおり展開する。
- AC #3 の全 5 状態については、幅を与える箇所を 1 つに畳んだ構造と SidebarRowIndentTests / SidebarKeyActionTests で担保した（loadingChildren・expandedEmpty・expandedFailed の実機再現は行っていない）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ツリー表示の開閉三角をクリック可能にした。判定は SidebarRowIndent.isWithinDisclosure（三角の領域）と SidebarKeyAction.disclosureToggleAction（開閉の向き）の 2 つの純粋関数に置き、FileListView.disclosureAction(for:atX:) が行のシングル・ダブル両方のタップから同じ判定を通す。三角の上では選択を動かさず開閉だけを行う。swift test 1384 件パス、swiftlint は main とのベースライン差分ゼロ、実機で depth 0/1 の展開・折りたたみと三角以外のクリックの従来動作を確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
