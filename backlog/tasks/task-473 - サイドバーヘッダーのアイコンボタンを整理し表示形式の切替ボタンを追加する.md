---
id: TASK-473
title: サイドバーヘッダーのアイコンボタンを整理し表示形式の切替ボタンを追加する
status: To Do
assignee: []
created_date: '2026-08-13 11:17'
updated_date: '2026-08-13 11:18'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 694000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーヘッダー(BefoldApp/befold/Viewer/SidebarHeaderView.swift:65-77)には現在 4 つのアイコンボタン(ソート順・不可視ファイル・変更のみ・名前フィルター)が横一列に並んでおり、TASK-409 で ⌃⌘T を割り当てた表示形式(ツリー/ドリルダウン)の切替をボタン化すると 5 個になる。幅の狭いサイドバーで窮屈であることに加え、「一覧の形」と「絞り込み」という性質の違う操作が同列に並んでいて系統が読み取れない。

操作行を左右に分割し、常設 3 + オーバーフロー 1 の計 4 コントロールへ再構成する。左＝表示形式(一覧の形)、右＝変更のみ・名前フィルター(絞り込み)＋ ⋯(ソート順・不可視ファイルを畳む)。

設計: docs/superpowers/specs/2026-08-13-sidebar-header-controls-design.md
実装計画: docs/superpowers/plans/2026-08-13-sidebar-header-controls.md (4 タスクに分解済み)

FeatureGate.isSidebarTreeEnabled 配下を含むため、コミット件名に (gate) スコープを付ける。ソート順の永続化はスコープ外(別途起票する)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ヘッダーが左群(表示形式)／右群(変更のみ・フィルター・⋯)に分かれ、ソート順と不可視ファイルが ⋯ 内に移っている
- [ ] #2 表示形式ボタンは ⌃⌘T と同じ経路(GlobalDisplayBroadcaster.toggleSidebarLayoutMode)を通り、切替結果が全ウィンドウ・再起動後も一致する
- [ ] #3 ゲート OFF で表示形式ボタンと変更のみボタンがヘッダーから消える
- [ ] #4 不可視ファイル表示が ON のとき、かつそのときだけ ⋯ がアクセント色になる
- [ ] #5 上記が SidebarHeaderControlsModel のユニットテストで担保され、swift test が全通過する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
実装計画の全文は docs/superpowers/plans/2026-08-13-sidebar-header-controls.md（コード片・テスト全文つき）。要約:
1. SidebarHeaderControlsModel（表示判定の純粋な値型）を新設し、左右の群・並び・アイコン・アクセント・⋯ の項目をユニットテスト 11 件で固定する
2. 表示形式トグルを配線する。ViewerWindowControllerDelegate に viewerWindowDidToggleSidebarTreeLayout を足し、ViewerWindowAssembler.makeSidebarTreeLayoutToggle（makeChangedFilesOnlyToggle と同型のゲート付き optional クロージャ）で露出する。切替の実体は ⌃⌘T と同じ GlobalDisplayBroadcaster.toggleSidebarLayoutMode で、ボタン専用の経路は作らない
3. SidebarHeaderControls ビューを新設してヘッダーを左右分割へ差し替え、ソート順・不可視ファイルを ⋯ メニューへ畳む。l10n キー 5 件を追加し、使われなくなった 4 件を削除する。実機確認 6 項目あり
4. docs/dev/native-app-design.md の追従とソート順永続化のフォローアップ起票
<!-- SECTION:PLAN:END -->
