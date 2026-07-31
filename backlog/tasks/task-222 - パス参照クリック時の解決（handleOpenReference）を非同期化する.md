---
id: TASK-222
title: パス参照クリック時の解決（handleOpenReference）を非同期化する
status: To Do
assignee: []
created_date: '2026-07-31 09:13'
labels:
  - refactor
  - performance
dependencies: []
priority: high
type: task
ordinal: 120000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ReferenceResolutionCoordinator.handleOpenReference (befold/App/ReferenceResolutionCoordinator.swift:53-69) が TrackedPathResolver.resolve を MainActor 上で同期実行している。キャッシュ未命中時は共有ロック + git ls-files subprocess + SuffixPathIndex 構築を待つ。同ファイル :75-77 に「MainActor 上では走らせない」と明記されているのに resolveReferences だけ Task.detached で、クリック経路は同期のまま。warm 完了前のクリックや別リポジトリのウィンドウがロック保持中の場合に UI が停止する。resolveReferences と同じ形（解決を Task.detached、openReference / presentReferenceNotFound は MainActor に戻す）に揃える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 参照クリック時に MainActor 上で git subprocess・ロック待ちが発生しない
- [ ] #2 解決成功時のオープン・失敗時の not found 表示が従来どおり動作する
- [ ] #3 非同期化後の解決経路にユニットテストがある
<!-- AC:END -->
