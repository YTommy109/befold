---
id: TASK-206
title: タブグループのスナップショット組み立てを単一情報源化する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 02:49'
updated_date: '2026-07-31 07:20'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/befold/App/ViewerWindowManager.swift
  - BefoldApp/befold/App/SessionRestorer.swift
priority: high
ordinal: 286000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
セッション保存用の TabGroup 組み立て(window.tabGroup?.windows ?? [window] → viewerPath で compactMap → 空なら nil → selectedWindow 決定 → SessionLayout.TabGroup 生成)が ViewerWindowManager.tabGroup(of:)(private)と SessionRestorer.currentSessionLayout() 内の appendGroup の 2 箇所に完全同一の 5 ステップで重複している。「終了時レイアウト」と「Recent Repositories のタブ構成」は同じ形式で保存・相互復元されるため、片方だけ仕様変更(例: selectedPath の決め方)するとサイレントに復元が壊れる。SessionRestorer 側の追加ロジック(seen-set・viewer 判定 guard)は前段に独立しており、組み立て本体の抽出は観測可能な差を生まない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 TabGroup スナップショットの組み立てロジックが 1 箇所に統合され、ViewerWindowManager と SessionRestorer の両方がそれを使う
- [x] #2 セッション保存・復元、Recent Repositories のタブ構成の記録・復元の既存動作が変わらない(既存テストが通る)
- [x] #3 共通化した組み立てロジックにユニットテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerWindowManager に純粋な組み立て関数 makeTabGroup(tabWindows:selectedWindow:viewerPath:) を static/generic で追加し、NSWindow 依存を排して単体テスト可能にする
2. tabWindows(of:) を static ヘルパーとして切り出し、tabGroup(of:) を internal 化して makeTabGroup へ委譲させる
3. SessionRestorer.currentSessionLayout の appendGroup を、ViewerWindowManager.tabWindows(of:) + windowManager.tabGroup(of:) の呼び出しへ置換(seen-set/viewer 判定 guard は据え置き)
4. ViewerWindowManagerTests に makeTabGroup のユニットテスト(空→nil / 単一 / 複数+選択タブ)を追加
5. swift build && swift test
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ViewerWindowManager に純粋関数 makeTabGroup(tabWindows:selectedWindow:viewerPath:) を追加し、NSWindow 非依存にしてユニットテスト可能にした。tabWindows(of:) を static ヘルパーに切り出し、tabGroup(of:) を internal 化して SessionRestorer.currentSessionLayout の appendGroup から呼ばせた(seen-set と viewer 判定 guard は前段に据え置き)。検証: swift build 成功、swift test 909 テストで本変更起因の失敗なし(DistributedAckWaiterIntegrationTests のタイムアウトは既存のフレーク、単独再実行で pass)。関連スイート ViewerWindowManagerTests/SessionRestorerTests/SessionLayoutTests/RecentRepositoriesStoreTests 63 テスト pass。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
タブグループのスナップショット組み立てを ViewerWindowManager.makeTabGroup に単一情報源化し、ViewerWindowManager.tabGroup(of:) と SessionRestorer.currentSessionLayout の双方がこれを使うようにした。makeTabGroup にユニットテスト4件(空/単独/タブ順+選択/非ビューアタブ除外)を追加。swift build と swift test(関連 63 テスト含む)で検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
