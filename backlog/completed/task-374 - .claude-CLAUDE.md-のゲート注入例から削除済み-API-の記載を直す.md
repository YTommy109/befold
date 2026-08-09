---
id: TASK-374
title: .claude/CLAUDE.md のゲート注入例から削除済み API の記載を直す
status: Done
assignee: []
created_date: '2026-08-08 11:23'
updated_date: '2026-08-08 13:11'
labels: []
dependencies: []
references:
  - .claude/CLAUDE.md
  - BefoldApp/befold/App/BookmarkShortcut.swift
priority: low
type: docs
ordinal: 635000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) 指摘。a545b98 で追加したフィーチャーゲート OFF 側検証方針の節が、模範例として `BookmarkShortcut.keyEquivalent(isSourceDiffEnabled:)` を挙げているが、同ブランチの先行コミット dacb72e がこの関数を削除済み（現在は `static let keyEquivalent = "d"` のみ）。将来のセッションがこの例を grep して見つからず、doc が誤りと結論するか非準拠な形を選ぶ恐れがある。現存する API（ModeSegments.modes(isSourceDiffEnabled:) / MainMenuBuilder.addDisplayModeItems(to:isSourceDiffEnabled:) 等）だけを指すよう修正する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 .claude/CLAUDE.md のゲート注入方針の例示が、現存する API のみを指している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手時点で既に解消済み。15b2851（シンボル実在チェックの導入）が同時に .claude/CLAUDE.md から BookmarkShortcut.keyEquivalent(isSourceDiffEnabled:) の記載を削除していた。検証: rg 'BookmarkShortcut|keyEquivalent' .claude/CLAUDE.md で該当なし、scripts/check-doc-symbols.sh が exit 0（残る例示 ModeSegments.modes(isSourceDiffEnabled:) / MainMenuBuilder.addDisplayModeItems(to:isSourceDiffEnabled:) は実在を確認）。コード変更なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
15b2851 で先行して解消済みであることを確認した。.claude/CLAUDE.md のゲート OFF 側検証方針の例示は現存する 2 つの API のみを指しており、scripts/check-doc-symbols.sh が exit 0 で通る。追加のコード変更なし。
<!-- SECTION:FINAL_SUMMARY:END -->
