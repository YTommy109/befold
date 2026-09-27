---
id: TASK-654
title: >-
  レビュー表示の applyRows ごとに revealChangedFolders が normalizedPathKey を 2 回計算し、O(1)
  の同一判定の手前で lstat を払っている
status: Done
assignee: []
created_date: '2026-09-27 08:37'
updated_date: '2026-09-27 09:42'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
priority: low
ordinal: 854000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

`/code-review high`（2026-09-27）の指摘。TASK-646 で `previous?.status != status` の比較を同一ストレージの早期 return で O(1) にしたが、その手前で `fileListModel.entriesDirectory.normalizedPathKey` と `currentDirectory.normalizedPathKey` を毎回計算している。

## 現状（検証済み）

- `normalizedPathKey` は `resolvingSymlinksInPath()` で、パス成分ごとに lstat を呼ぶ。
- `revealChangedFolders` は `applyRows` の末尾で毎回呼ばれる（子リスト着地のまとめ組み直し・畳み・フォーカス復帰の取り直し）。レビュー表示ではメインアクターで毎回 2 本の解決が走ってから状態比較に入る。

## 方向

まず実測する（深いパスでの `applyRows` 1 回あたりのコスト）。無視できるなら Notes に残して見送る。効くなら、`Reveal` に計算元の `entriesDirectory` / `currentDirectory` の URL を持たせて `==` で先に比較し、URL が変わったときだけキーを計算する。または status の同一判定を先に置く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 レビュー表示で `applyRows` 1 回あたりの `normalizedPathKey` の呼び出しコストが実測され、Notes に残っている
- [x] #2 実測で効かない場合、見送りの判断と根拠が Notes に残っている（効く場合は、ディレクトリと git 状態が変わらない applyRows で resolvingSymlinksInPath が呼ばれない）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
実測して判断する。無視できれば見送り、効けば Reveal に URL を持たせて先に比較する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測（2026-09-27、swiftc -O の単体スクリプトで resolvingSymlinksInPath().path を 20,000 回、ローカル APFS）:
- リポジトリルート（/Users/.../wt/feature、7 成分）: 2.67 µs/回 → revealChangedFolders の 2 本で 5.3 µs
- 10 段深いディレクトリ: 5.09 µs/回 → 10.2 µs
- 同じ 10 段を symlink 経由: 5.63 µs/回 → 11.3 µs
比較対象: applyRows の組み直し 1 回は 700 行で約 12 ms（SidebarTreePresenter.scheduleRebuild の doc の実測）。2 本の解決はその約 0.1%。さらに applyRows の通常経路自体が同じディレクトリの normalizedPathKey を FileListModel で複数回解決しており（previewTarget の isListingCurrent、applyGitStatus / 一覧着地の entriesDirectoryKey、選択キー）、ここだけキャッシュしても同種の解決は残る。
判断: 見送り。状態（Reveal への URL 保持）を増やす価値が無い。遅いネットワークボリュームで効くなら、revealChangedFolders 単独ではなく FileListModel 側の解決と合わせて扱うべき。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
revealChangedFolders の normalizedPathKey 2 本のコストを実測した（5〜11 µs / applyRows、組み直し 12 ms の約 0.1%）。applyRows の通常経路も同じ解決を複数回行っているため、ここだけキャッシュする価値は無いと判断し、コード変更なしで見送った。
<!-- SECTION:FINAL_SUMMARY:END -->
