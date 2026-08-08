---
id: TASK-372
title: 旧 SourceDiffEnabled 設定を DisplayModeStore の .diff へ移行し stale キーを削除する
status: To Do
assignee: []
created_date: '2026-08-08 11:23'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/DisplayModeStore.swift
  - BefoldApp/befold/App/DiffDisplayPreference.swift
priority: low
type: bug
ordinal: 633000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) 指摘。FeatureGate 配下（dev ビルド限定のため影響は小さいが、永続化済みユーザー設定の暗黙の喪失）。DisplayModeStore.migrateLegacySourceModesIfNeeded は per-file の旧 source Bool を .source/.rendered にしか写さず、app-global の UserDefaults キー SourceDiffEnabled（旧 DiffDisplayPreference.isEnabled）は読み手が消えたまま放置される。旧状態で「diff ON + per-file source=true」だったファイルが .diff として移行されず、更新後は diff 無しの plain source で開く。stale キーも defaults に残り続ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 旧 SourceDiffEnabled=true かつ per-file source=true だったファイルが .diff として移行される
- [ ] #2 移行後に SourceDiffEnabled キーが defaults から削除される
- [ ] #3 移行ロジックをユニットテストで担保する
<!-- AC:END -->
