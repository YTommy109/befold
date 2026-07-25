---
id: TASK-147
title: SuffixPathIndex を fingerprint キャッシュに載せてバッチごとの再構築をなくす
status: To Do
assignee: []
created_date: '2026-07-25 11:30'
labels:
  - path-reference
  - performance
dependencies: []
priority: medium
type: enhancement
ordinal: 223000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitCommandFileIndex がキャッシュするのは [URL] のみで、LazySuffixIndex.value()（TrackedPathResolver.swift L35-42, 79-85）は git フォールバックが必要なバッチ（＝再レンダリング）のたびに SuffixPathIndex(candidates:) を O(N) でフル再構築する（SuffixPathMatcher.swift L64-79。候補 1 件あたり standardizedFileURL 2 回 + pathComponents 配列 2 本）。数万〜10 万ファイルのモノレポで未解決参照を含む文書を編集し続けると、保存のたびに数百 ms〜秒オーダーの再構築と大量アロケーションが走り、リンク化の反映が保存頻度に追いつかなくなる（パフォーマンスレビュー指摘・中）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GitCommandFileIndex のエントリを (fingerprint, files, suffixIndex) に拡張し、fingerprint が同じ間は構築済み SuffixPathIndex を返す
- [ ] #2 同一 fingerprint での連続バッチで SuffixPathIndex が再構築されないことをテストで確認する
- [ ] #3 fingerprint 無効化・LRU 追い出し時に索引も一緒に破棄される
<!-- AC:END -->
