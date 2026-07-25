---
id: TASK-154
title: パス参照リンク機能のレビュー軽微指摘（規約・テストカバレッジ）をまとめて是正する
status: To Do
assignee: []
created_date: '2026-07-25 11:32'
labels:
  - path-reference
dependencies: []
priority: low
type: chore
ordinal: 230000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/document_path コードレビューの軽微指摘の一括是正。個別項目は受け入れ条件を参照。いずれも機能に影響しない規約・カバレッジの穴。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ReferenceResolver（ReferenceTarget / ReferenceResolver / resolve）、TrackedPathResolver.resolve、GitCommandRunner.run / runString に /// を補完する
- [ ] #2 SuffixPathIndex.init L68 の `pathComponents.filter { $0 != "/" }` 手組みを components(of:) 経由に一本化する
- [ ] #3 SuffixPathMatcher.hasComponentSuffix の `Array(suffix(_:)) ==` を elementsEqual のコピーなし比較にする
- [ ] #4 GitRepositoryTests にスペース入りファイル名の trackedFiles と相対 gitdir:（submodule 形式）のテストを追加する
- [ ] #5 viewer-main.js の const と coding_rule.md の「var を使用する」規約の乖離を解消する（規約更新か var 統一のどちらかを判断して記録）
- [ ] #6 _mmdIsLocalPathHref を viewer.js の純粋ロジック側へ移し module.exports して直接ユニットテストする
- [ ] #7 GitCommandFileIndex.rootByDir に上限を設けない判断・warm の多重呼び出し許容をコメントで明文化する（または in-flight 抑止を入れる）
- [ ] #8 SuffixPathMatcher と SuffixPathIndex の公開型 2 つ同居について、分離するか同居の判断を記録する
<!-- AC:END -->
