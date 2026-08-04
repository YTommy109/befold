---
id: TASK-154
title: パス参照リンク機能のレビュー軽微指摘（規約・テストカバレッジ）をまとめて是正する
status: Done
assignee: []
created_date: '2026-07-25 11:32'
updated_date: '2026-07-25 13:02'
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
- [x] #1 ReferenceResolver（ReferenceTarget / ReferenceResolver / resolve）、TrackedPathResolver.resolve、GitCommandRunner.run / runString に /// を補完する
- [x] #2 SuffixPathIndex.init L68 の `pathComponents.filter { $0 != "/" }` 手組みを components(of:) 経由に一本化する
- [x] #3 SuffixPathMatcher.hasComponentSuffix の `Array(suffix(_:)) ==` を elementsEqual のコピーなし比較にする
- [x] #4 GitRepositoryTests にスペース入りファイル名の trackedFiles と相対 gitdir:（submodule 形式）のテストを追加する
- [x] #5 viewer-main.js の const と coding_rule.md の「var を使用する」規約の乖離を解消する（規約更新か var 統一のどちらかを判断して記録）
- [x] #6 _mmdIsLocalPathHref を viewer.js の純粋ロジック側へ移し module.exports して直接ユニットテストする
- [x] #7 GitCommandFileIndex.rootByDir に上限を設けない判断・warm の多重呼び出し許容をコメントで明文化する（または in-flight 抑止を入れる）
- [x] #8 SuffixPathMatcher と SuffixPathIndex の公開型 2 つ同居について、分離するか同居の判断を記録する
- [x] #9 CLAUDE.md と docs/dev/coding_rule.md のプロジェクト構成ツリー（BefoldKit の一覧）に SuffixPathMatcher / TrackedPathResolver を追記し、パス参照リンク機能で追加した型と実体を一致させる
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

各項目の対応:
#1 ReferenceTarget / ReferenceResolver / resolve と TrackedPathResolver.resolve に /// を補完。GitCommandRunner.run は TASK-150 で /// を付与済み、runString は同タスクで削除済み。
#2 SuffixPathIndex.init の手組みを解消。ただし components(of:) をそのまま呼ぶと standardizedFileURL（FS に触る正規化）が二重に走るため、正規化済み URL を受ける components(ofStandardized:) を新設し、両者がそこへ委譲する形にした。
#3 hasComponentSuffix を haystack[...].elementsEqual(needle) のコピーなし比較へ。
#4 GitRepositoryTests に (a) スペース・引用符・日本語を含むファイル名が ls-files -z で欠けずに列挙される、(b) submodule 形式の相対 gitdir を辿って index を見る、の 2 テストを追加。
#5 想定と逆の結論。同梱 JS の実測は var 243 対 const 6（const は viewer-main.js のブリッジ定数のみ）で var が実態だったため、その 6 件を var に統一。規約側は「WKWebView の互換性のため」という古い根拠を、「macOS 14+ では技術的制約ではなく、同梱 JS 全体が var で書かれているための一貫性ルール」へ是正した。あわせて Swift 側の突き合わせテスト（ViewerBridgeContractTests）が const 決め打ちで JS を parse していたため var/let/const を受けるよう修正（この取りこぼしは swift test が検知した）。
#6 _mmdIsLocalPathHref を viewer.js へ isLocalPathHref として移設し module.exports に追加。Jest で 6 ケース（相対/絶対パス、行番号付き、ドットなしスキーム除外、アンカー、空・nullish、スキーム形でないコロン）を直接検証。
#7 rootByDir に上限を設けない理由と、warm の多重呼び出しを抑止しない理由をコメント化。
#8 SuffixPathMatcher と SuffixPathIndex を同居させる判断（照合規則を共有する 1 つの関心の 2 つの面であり、片方だけ読んでも意味を成さない）を型の /// に記録。
#9 CLAUDE.md と coding_rule.md の構成ツリーに TrackedPathResolver / SuffixPathMatcher（BefoldKit）と ReferenceResolutionCoordinator / GitRepository（befold/App）を追記。
検証: swift test 692 tests（Integration 含む）全パス、npx jest 304 passed、swift build（SwiftLint 込み）、swiftformat 適用済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
レビューの軽微指摘 9 項目を一括是正した。/// 補完・判定式の一本化・コピーなし比較・テスト追加（スペース入りファイル名、相対 gitdir）・純粋述語の viewer.js 移設と直接テスト・設計判断のコメント化・構成ツリーへの新規型反映。JS の宣言子は実測（var 243 対 const 6）に基づき var へ統一し、規約側の古い根拠記述を是正、あわせて const 決め打ちだった突き合わせテストも実態に合わせた。swift test 692 件・jest 304 件が全パス。
<!-- SECTION:FINAL_SUMMARY:END -->
