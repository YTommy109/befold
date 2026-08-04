---
id: TASK-281
title: allEntriesSorted がソート済みの 2 配列を再度フルソートしている
status: To Do
assignee: []
created_date: '2026-08-04 02:01'
labels:
  - review-finding
dependencies: []
priority: low
type: chore
ordinal: 471000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DirectoryLister.allEntriesSorted（DirectoryLister.swift:84）は (folders + files) に対して sortedByFileName() をかけ直しているが、DirectoryEnumeration.sortedContents は既に同じ比較子（lastPathComponent の localizedStandardCompare）で各半分をソート済みで返している。ロケール依存の重い比較子で O(n log n) を丸ごと払い直しており、しかも TASK-273 でこの行には要素ごとの nativeBackedFileURL 再構築も乗った。Quick Open の候補列挙経路にあたる。

ソート済み 2 配列の線形マージ、または未ソートの結合に対して 1 回だけソートすれば、同じ結果を O(n) 回の比較で得られる。指摘自体は TASK-273 以前からある既存の無駄だが、当該行が今回の差分で変更されているためここで直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 大きなフォルダーで allEntriesSorted の比較回数が減っている（マージまたは単一ソートに置き換わっている）
- [ ] #2 フォルダー先頭・ファイル後続の並び順と、ファイル名比較の順序が従来と一致することをテストで確認する
<!-- AC:END -->
