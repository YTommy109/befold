---
id: TASK-154
title: パス参照リンク機能のレビュー軽微指摘（規約・テストカバレッジ）をまとめて是正する
status: In Progress
assignee: []
created_date: '2026-07-25 11:32'
updated_date: '2026-07-25 12:53'
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
- [ ] #9 CLAUDE.md と docs/dev/coding_rule.md のプロジェクト構成ツリー（BefoldKit の一覧）に SuffixPathMatcher / TrackedPathResolver を追記し、パス参照リンク機能で追加した型と実体を一致させる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
AC 9 項目を性質ごとに片付ける。
1. /// 補完（ReferenceResolver / TrackedPathResolver.resolve / GitCommandRunner.run。runString は TASK-150 で削除済み）
2. SuffixPathIndex.init の components 手組みを components(of:) へ一本化
3. hasComponentSuffix を elementsEqual のコピーなし比較へ
4. GitRepositoryTests にスペース入りファイル名・相対 gitdir のテストを追加
5. viewer.js の const/var 規約乖離を解消（実態に合わせて規約側を更新する方向で検討）
6. _mmdIsLocalPathHref を viewer.js へ移して直接テスト
7. rootByDir の上限なし・warm 多重呼び出しの判断をコメント化
8. SuffixPathMatcher / SuffixPathIndex 同居の判断を記録
9. CLAUDE.md / coding_rule.md の構成ツリーへ新規型を追記
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-147 の作業中に発見: TASK-122 でパス参照リンク機能の型（SuffixPathMatcher / TrackedPathResolver）を BefoldKit へ追加した際、CLAUDE.md・coding_rule.md の「プロジェクト構成」ツリーへの反映が漏れていた（規約「型・ファイルの削除・追加・リネームはアーキテクチャ図とプロジェクト構成ツリーへの波及を必ず確認する」の未履行）。GitCommandFileIndex / GitCommandRunner / GitRepository（befold/App/ 配下）についても同様に記載の要否を確認すること。
<!-- SECTION:NOTES:END -->
