---
id: TASK-613
title: スライド窓だけで開いているファイルを外から開くと、通常窓が開かず Open Recent にも載らない
status: To Do
assignee: []
created_date: '2026-09-11 08:58'
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
- [ ] #1 ファイルがスライド窓だけで開いている状態で同じファイルを `.currentTab` で開くと、新しい通常のビューア窓が開く
- [ ] #2 その通常窓が開いたとき Open Recent に記録される
- [ ] #3 同じファイルが通常窓でも開いている場合は従来どおりその通常窓を前面化する（新しい窓を増やさない）
- [ ] #4 `.newTab` の再利用判定（同じタブグループ内）でもスライド窓は候補にならない
- [ ] #5 `ViewerWindowOpenPolicyTests` に kind で絞る判定のテストがある
<!-- AC:END -->
