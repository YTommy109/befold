---
id: TASK-654
title: >-
  レビュー表示の applyRows ごとに revealChangedFolders が normalizedPathKey を 2 回計算し、O(1)
  の同一判定の手前で lstat を払っている
status: To Do
assignee: []
created_date: '2026-09-27 08:37'
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
- [ ] #1 レビュー表示で `applyRows` 1 回あたりの `normalizedPathKey` の呼び出しコストが実測され、Notes に残っている
- [ ] #2 実測で効く場合、ディレクトリと git 状態が変わらない `applyRows` では `resolvingSymlinksInPath` が呼ばれない
<!-- AC:END -->
