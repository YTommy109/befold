---
id: TASK-646
title: >-
  revealChangedFolders の「状態が同じなら何もしない」判定が SidebarGitStatus の全量比較で、組み直しの hot path
  で毎回走る
status: Done
assignee: []
created_date: '2026-09-27 07:24'
updated_date: '2026-09-27 08:12'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befold/Viewer/FileListModel.swift
  - BefoldApp/befold/App/SidebarGitStatus.swift
priority: low
ordinal: 846000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

TASK-638（commit 5f7d3c2b）で `revealChangedFolders` に `guard previous?.status != status else { return }` を置き、コメントで「状態が同じなら候補を数えもしない」とした。`/code-review high` が、その判定自体のコストを指摘した。

## 現状（検証済み）

- `SidebarGitStatus` は `files: [String: GitFileStatus]` と `folders: [String: GitFolderStatus]` を持つ Equatable な struct。`!=` は 2 つの辞書の全量比較で、変更ファイル数に比例する。
- `revealChangedFolders` は `applyRows` の末尾で毎回呼ばれる。`applyRows` は一覧の着地・子リスト着地のまとめ組み直し（`scheduleRebuild`）・畳み・フォーカス復帰の取り直しのすべてで走る。TASK-637 が 12ms → まとめて 1 回へ最適化した経路の中で、毎回この比較が走る。
- 一方 `FileListModel.gitStatus` の `didSet` は既に `guard gitStatus != oldValue` で同値を弾いている。同じ比較を presenter 側で繰り返している。

## 方向

まず実測する（数千件の変更を持つリポジトリで `applyRows` 1 回あたりの比較コストがどれだけか）。無視できるなら Notes に実測を残して見送る。効くなら、`FileListModel` が `gitStatus` の変化ごとに進める世代（Int）を持ち、`lastReveal` はそれを記録して Int 比較にする（等価性の判定を didSet 1 箇所へ寄せる）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `applyRows` 1 回あたりの `SidebarGitStatus` 比較コストが、数千件規模の git 状態で実測され Notes に残っている
- [x] #2 実測で無視できない場合、`revealChangedFolders` の同一判定が辞書の全量比較ではなく世代の比較になっている（無視できる場合は見送りの判断と根拠が Notes にある）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
実測で hot path の比較コストを確かめる → 同値の書き込みを弾いてストレージを保つ(世代の新設はしない)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測(swiftc -O、[String: enum] 辞書 + フォルダー集約の同形 struct、M 系 macOS):
- 同一ストレージ(COW 共有)の比較: n=1,000/5,000/20,000 のいずれも 0.1us 未満。Swift の Dictionary/Set の == はストレージ同一性で早期 return する。
- 同値だが別ストレージの比較: n=1,000 約 0.14ms / 5,000 約 0.25ms / 20,000 約 1.0ms。

判断: 本来 hot path は O(1) だが、FileListModel.setGitStatus が同値でも無条件に代入していた(didSet のガードは通知を止めるだけ)。取り直しで同値の新ストレージが入ると lastReveal.status と別ストレージになり、しかも同値なので lastReveal は更新されず、以後すべての applyRows で全量比較が続いていた。
単純化の検討: 世代(Int)を新設せず、setGitStatus で同値なら代入しないガードを置き、一覧着地時の昇格(promotePendingGitStatusIfNeeded)も setGitStatus 経由へ寄せた。これで同値の間は同一ストレージが保たれ、presenter の比較は O(1)。didSet 側の重複ガードは撤去(書き込み点が 1 本になったため)。
担保: SidebarIdenticalListingTests.identicalGitStatusKeepsStorage(ガードを外すと落ちることを確認済み)。swift test 全 2007 件 pass。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
setGitStatus で同値の git 状態を代入ごと弾き、昇格経路も同じ書き込み点へ寄せた。同値の間は辞書ストレージが共有されるため revealChangedFolders の比較は同一性の早期 return で O(1) になる(実測: 共有 <0.1us、別ストレージ 5,000 件 約 0.25ms)。世代カウンタは不要と判断。identicalGitStatusKeepsStorage で固定、swift test 全件 pass。
<!-- SECTION:FINAL_SUMMARY:END -->
