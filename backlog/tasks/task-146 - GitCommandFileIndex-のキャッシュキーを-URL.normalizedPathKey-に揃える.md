---
id: TASK-146
title: GitCommandFileIndex のキャッシュキーを URL.normalizedPathKey に揃える
status: Done
assignee: []
created_date: '2026-07-25 11:30'
updated_date: '2026-07-25 11:48'
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
- [x] #1 rootByDir / entryByRoot のキー生成が URL.normalizedPathKey 経由になっている
- [x] #2 symlink 経由パスと実パスが同一キャッシュエントリに集約されることをテストで確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitCommandFileIndex の dirKey を url.deletingLastPathComponent().normalizedPathKey にする
2. entryByRoot / rootsByRecency のキーを root.normalizedPathKey に揃える（GitRepositoryReading の契約は正規化を保証しないため）
3. TempDir に symlinkedDirectory ヘルパーを追加（テストファイル内での手組みは規約違反）
4. 実 FS の symlink 経由パスと実パスが同一エントリに集約される（列挙が 1 回で済む）ことをテストで固定
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
dirKey を normalizedPathKey へ、entryByRoot / rootsByRecency のキーを root.normalizedPathKey へ変更。root は rev-parse 由来で実質正規化済みだが、GitRepositoryReading の契約はそれを保証しないため揃えた（その理由をインラインコメントに明記）。
テストの手組み回避のため BefoldTestSupport.TempDir に symlinkedDirectory ヘルパーを追加（既存の symlinkedFile と同じ流儀）。
実効性の確認: GitCommandFileIndex.swift だけを git stash して同テストを実行し、rootCallCount / trackedCallCount がいずれも 2 になって落ちることを確認済み（修正後は 1）。
検証: swift test 629 tests 全パス、swift build（SwiftLint 込み）、swiftformat 差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitCommandFileIndex のキャッシュキー（rootByDir / entryByRoot / rootsByRecency）を規約の単一情報源である URL.normalizedPathKey に統一した。symlink 経由ディレクトリを実 FS で作る回帰テストを追加し、修正前は rev-parse・ls-files が各 2 回、修正後は各 1 回になることを stash 実験で確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
