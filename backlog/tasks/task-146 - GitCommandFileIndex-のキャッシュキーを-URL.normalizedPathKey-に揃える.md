---
id: TASK-146
title: GitCommandFileIndex のキャッシュキーを URL.normalizedPathKey に揃える
status: In Progress
assignee: []
created_date: '2026-07-25 11:30'
updated_date: '2026-07-25 11:44'
labels:
  - path-reference
dependencies: []
priority: medium
type: bug
ordinal: 222000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitCommandFileIndex.swift L41 が dirKey に `url.deletingLastPathComponent().standardizedFileURL.path` を使用。coding_rule.md の単一情報源テーブルは「パスの同一性キー（symlink 解決込み）は URL.normalizedPathKey。ディレクトリ同一性比較も standardizedFileURL.path ではなくこちらを使う」と明記しており明文規約違反。symlink 経由と実パスで同じディレクトリを開くと rootByDir に別キーで重複し rev-parse が余計に走る。entryByRoot のキー root.path（L55, L60, L73）も GitRepositoryReading の契約は正規化を保証しないため normalizedPathKey へ揃えるのが安全（feat/document_path のコードレビュー指摘・重大）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 rootByDir / entryByRoot のキー生成が URL.normalizedPathKey 経由になっている
- [ ] #2 symlink 経由パスと実パスが同一キャッシュエントリに集約されることをテストで確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitCommandFileIndex の dirKey を url.deletingLastPathComponent().normalizedPathKey にする
2. entryByRoot / rootsByRecency のキーを root.normalizedPathKey に揃える（GitRepositoryReading の契約は正規化を保証しないため）
3. TempDir に symlinkedDirectory ヘルパーを追加（テストファイル内での手組みは規約違反）
4. 実 FS の symlink 経由パスと実パスが同一エントリに集約される（列挙が 1 回で済む）ことをテストで固定
<!-- SECTION:PLAN:END -->
