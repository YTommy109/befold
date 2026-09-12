---
id: TASK-613
title: スライド窓だけで開いているファイルを外から開くと、通常窓が開かず Open Recent にも載らない
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-09-11 08:58'
updated_date: '2026-09-11 12:52'
labels: []
dependencies: []
ordinal: 803000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ViewerWindowOpenPolicy.reusableController` は `.currentTab` のとき `candidates.first` を返し、窓の種別を見ない（コード参照: `BefoldApp/befold/App/ViewerWindowOpenPolicy.swift` の `switch disposition` / `case .currentTab`）。そのため、あるファイルをスライド窓だけで表示している状態で同じファイルを Finder のダブルクリック・Quick Open・CLI から開くと、`ViewerWindowManager.openViewer` は既存扱いでスライド窓を前面化して早期 return し、通常のビューア窓は開かない。

TASK-593.2 で「スライド窓は復元対象外・タブ合流なし」と決めたが、`.currentTab` の再利用候補からは外していなかった取りこぼし。TASK-610 でスライド窓を利用履歴から外したことで、この経路では Open Recent にも載らなくなり、利用者が明示的に開いたファイルが履歴に残らない形で目に見えるようになった（TASK-610 のコードレビュー指摘）。

前提（コード参照）: 早期 return の分岐（`openViewer` の `if let existing = ...`）は元々 `recentDocumentsStore.noteOpened` を呼ばない。再利用の候補を kind で絞れば新規生成の経路に落ちて履歴にも載るので、そちらで直すのが筋。`existing` の分岐で履歴を積む案は、通常窓の再前面化で履歴の順が動く別の振る舞い変更を伴う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ファイルがスライド窓だけで開いている状態で同じファイルを `.currentTab` で開くと、新しい通常のビューア窓が開く
- [x] #2 その通常窓が開いたとき Open Recent に記録される
- [x] #3 同じファイルが通常窓でも開いている場合は従来どおりその通常窓を前面化する（新しい窓を増やさない）
- [x] #4 `.newTab` の再利用判定（同じタブグループ内）でもスライド窓は候補にならない
- [x] #5 `ViewerWindowOpenPolicyTests` に kind で絞る判定のテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. `ViewerWindowKind` に述語 `acceptsReopen`（`self == .viewer`）を足す（呼び出し側で `kind == .slide` と書かない規約）。
2. `ViewerWindowOpenPolicy.reusableController` の先頭で候補を `acceptsReopen` で絞る。`.currentTab` と `.newTab` の両分岐が同じ絞り込みを通る。
3. テスト: `ViewerWindowOpenPolicyTests`（新規）で純粋な判定を 3 ケース、`ViewerWindowManagerTests` で実配線（スライド窓だけで開いているファイルを currentTab で開くと通常窓が開き履歴にも載る）。新規ファイルなので `xcodegen generate`。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: `swift test --skip Integration --skip FileWatcherTests` 1879 tests / 308 suites 全通過。
新規テスト 4 件（`ViewerWindowOpenPolicyTests` 3 件、`ViewerWindowManagerTests` 1 件）。`xcodegen generate` 実施済み。
AC #4 について: スライド窓は `joinsTabs == false` で起点のタブグループに入らないため実際には起こらないが、絞り込みを分岐の手前 1 箇所に置いたので `.newTab` 側も同じ判定を通る（テストで固定）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`.currentTab` / `.newTab` の再利用候補を `ViewerWindowKind.acceptsReopen` で絞り、スライド窓だけで開いているファイルを Finder / Quick Open から開くと通常窓が開き、利用履歴にも載るようにした。検証: swift test 1879 件全通過、純粋判定 3 件＋実配線 1 件のテストを追加。
<!-- SECTION:FINAL_SUMMARY:END -->
