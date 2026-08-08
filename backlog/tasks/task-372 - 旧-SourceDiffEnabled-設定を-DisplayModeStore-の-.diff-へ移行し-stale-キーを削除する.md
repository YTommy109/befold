---
id: TASK-372
title: 旧 SourceDiffEnabled 設定を DisplayModeStore の .diff へ移行し stale キーを削除する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 11:23'
updated_date: '2026-08-08 12:57'
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
- [x] #1 旧 SourceDiffEnabled=true かつ per-file source=true だったファイルが .diff として移行される
- [x] #2 移行後に SourceDiffEnabled キーが defaults から削除される
- [x] #3 移行ロジックをユニットテストで担保する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. migrateLegacySourceModesIfNeeded に旧 app-global キー SourceDiffEnabled の読み取りを足し、true なら per-file source=true を .diff へ写す（false は従来どおり .source）
2. 移行の実行有無にかかわらず SourceDiffEnabled を defaults から削除する（defer で早期 return 経路も通す）
3. DisplayModeStoreTests に (a) diff ON + source=true → .diff、(b) diff OFF → .source、(c) 新キー既存でも stale キーが消えることを追加
4. swift test / swiftformat / swiftlint 差分ゼロを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: migrateLegacySourceModesIfNeeded に旧 app-global キー SourceDiffEnabled の読み取りを合流させ、per-file source=true を差分 ON なら .diff、OFF なら .source として写す。移行経路を 2 本に増やさず既存の 1 度きり移行へ畳んだ。stale キーの削除は defer で行い、新キー既存（移行スキップ）の経路でも必ず消える。
検証: swift test で DisplayModeStoreTests 10 件（新規 2 件・各 2 引数）を含む全 1217 件成功。swiftlint は変更 2 ファイルで 0 件、swiftformat は 0/10 files formatted（無変更）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
旧 app-global キー SourceDiffEnabled を DisplayModeStore の 1 度きり移行へ取り込み、旧「差分 ON + per-file source=true」だったファイルを .diff として引き継ぐようにした。あわせて読み手の居なくなった同キーを defer で必ず defaults から削除する（移行がスキップされる経路も含む）。移行の両分岐と stale キー削除の両経路をユニットテストで担保し、swift test 全 1217 件成功・変更ファイルの swiftlint 0 件を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
