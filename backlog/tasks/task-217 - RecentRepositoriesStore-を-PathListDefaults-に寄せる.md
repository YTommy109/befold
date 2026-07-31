---
id: TASK-217
title: RecentRepositoriesStore を PathListDefaults に寄せる
status: To Do
assignee: []
created_date: '2026-07-31 07:43'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/befold/App/RecentRepositoriesStore.swift
  - BefoldApp/BefoldKit/PathListDefaults.swift
priority: low
ordinal: 297000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-210 で SessionStore / BookmarkStore / RecentDocumentsStore の UserDefaults パス配列ボイラープレートを BefoldKit の PathListDefaults に共通化したが、RecentRepositoriesStore は当時のスコープ外だったため旧来の「stringArray(forKey:) ?? [] → normalizedPathKey で操作 → set(_:forKey:)」を自前で持ったまま残っている。共通基盤が既にあるのに 1 ストアだけ外れている状態は、TASK-210 が防ごうとした「新ストア追加時の rename 反映漏れ」の余地をそのまま残す。PathListDefaults に寄せて 4 ストアすべてを同じプリミティブの合成に揃える。着手前に PR #356 (TASK-210) がマージ済みであることを確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 RecentRepositoriesStore が PathListDefaults を合成する形になり、パス配列の load/save/追加/rename の自前実装が消える
- [ ] #2 既存のドメイン API と挙動が変わらない（既存テストが通る）
<!-- AC:END -->
