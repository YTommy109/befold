---
id: TASK-325
title: GitDiffLoader をウィンドウ間で共有して git diff の二重起動を防ぐ
status: Done
assignee:
  - '@claude'
created_date: '2026-08-05 16:09'
updated_date: '2026-08-06 05:10'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: low
type: chore
ordinal: 512000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

GitDiffLoader はウィンドウごとに生成される（ViewerWindowController.swift:58 の lazy var diffLoader = Self.makeDiffLoader()、実体は ViewerWindowController+Diff.swift:11）。このため in-flight 合流はウィンドウ内でしか効かず、同じ変更ありファイルを 2 窓で開いているとファイル変更イベントで両窓のローダーが同時に git diff HEAD -- path を起動する。合流の doc コメントが防ぐと謳っている二重起動がウィンドウをまたぐと起きる。アプリ共有の GitStatusStore と対照的。

修正: GitStatusStore と同様にアプリ共有のインスタンスにする（ViewerWindowManager 経由で注入）。

関連: TASK-321（in-flight 合流が古い差分を返す問題）。同じ型の構造に触るため、まとめて実施すると効率的。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 同じファイルを 2 窓で開いた状態のファイル変更イベントで、git diff の起動が 1 回に合流する
- [x] #2 ウィンドウを閉じても他窓の差分取得に影響しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
0. 前提（設計レビュー結果）: ローダー共有だけでは AC#1 を満たさない。refreshDiff はルート解決の await を挟んでから GitDiffLoader.diff() 内でチケットを取るため、同一ファイル変更イベント由来の 2 窓の要求が「後から来た要求」と判定され合流しない（GitDiffLoader.swift:36 / ViewerWindowController+Diff.swift:34-43）。

1. GitDiffLoader.diff(forFileAt:in:requestedAt:) を追加し、チケットの取得を契機（refreshDiff の入口）へ移す。同一イベント由来の兄弟要求は合流し、保存後の新しい要求は従来どおり取り直す（TASK-321 の保証を維持）。
2. GitDiffLoader の生成責務を ViewerWindowController から ViewerWindowManager へ移す。ViewerWindowController.makeDiffLoader() を削除し、lazy var を注入 let（既定 nil = 差分を出さない縮退）にして自前生成の経路そのものを消す。
3. ViewerWindowManager が FeatureGate.isSourceDiffEnabled に応じて 1 個だけ let で保持し、openViewer で全コントローラへ渡す。テスト用に init 引数で差し替え可能にする。
4. ViewerWindowControllerFixture / MockedViewerWindowManager に diffLoader 注入口を追加し、既存テストの controller.diffLoader = ... を注入へ置き換える。
5. 回帰テスト:
   (a) 同一ファイルを 2 窓で開いた状態の refreshDiff で GitDiffReader の呼び出しが 1 回（AC#1。窓ごと生成／チケット取得位置が戻ると落ちる）
   (b) 1 窓を閉じた後も残る窓の差分取得が動く（AC#2）
   (c) openViewer が生成した全ウィンドウが同一 GitDiffLoader インスタンスを共有する（=== 比較。ゲート無効ビルドで nil === nil の空振りにならないよう、非 nil のスタブを manager 経由で注入する）
6. 修正を戻して (a) が落ちることを確認 → swift test → swiftformat/swiftlint ベースライン差分ゼロ。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
コードレビュー(2026-08-06, high)で CONFIRMED として再検出。ViewerWindowController.swift:58 の lazy var diffLoader が窓ごとに生成され、同一ファイルを 3 タブで開くと 1 回の保存で git diff HEAD -- <path> が 3 プロセス起動する。DiffDisplayPreference は同じ理由で共有化済み（TASK-319）。

実装完了。

設計レビュー(/review-design)で、ローダーを共有するだけでは AC#1 が満たせないことが判明した。refreshDiff はリポジトリルート解決の await を挟んでから GitDiffLoader.diff() 内で要求チケットを取っていたため、同じファイル変更イベントから出た 2 窓ぶんの要求が「先行取得の開始より後に来た要求」と判定され、TASK-321 の合流拒否ロジックに弾かれて git が 2 回起動していた。そこでチケットの取得を契機側(refreshDiff の入口)へ移し、diff(forFileAt:in:requestedAt:) で受け渡す形にした。TASK-321 の保証(保存後の要求には取り直した結果を返す)は維持している。

変更点:
- GitDiffLoader: Ticket 型と takeRequestTicket() を追加。diff() は requestedAt を必須引数で受ける
- ViewerWindowController: lazy var diffLoader(自前生成)を let の注入プロパティへ。makeDiffLoader() は削除し、生成点を ViewerWindowManager.makeDiffLoader() 一箇所に集約(窓ごと生成の経路自体を無くした)
- ViewerWindowManager: 共有の diffLoader を let で保持し openViewer で全コントローラへ渡す
- FeatureGate の露出点一覧を更新(FeatureGateEnumerationTests が一致を強制している)
- テスト: 差分テストのスタブを DiffTestSupport.swift へ切り出し、窓をまたぐ検証を ViewerWindowManagerDiffTests.swift へ分離(元ファイルが file_length / type_body_length の新規違反を出したため)

実測:
- swift test 全件 1166 tests / 173 suites パス
- 修正を戻して落ちることを確認: (a) openViewer が窓ごとにローダーを作る形へ戻すと 4 件失敗(共有・合流・閉窓独立・全窓トグル) (b) チケットを diff() 内で取る形へ戻すと合流テスト 2 件が失敗(GitDiffLoaderTests: reader.calls 2 != 1 / ViewerWindowManagerDiffTests: callCount 4 != 3)
- 差分スイート単体で 3 回連続パス(タイミング依存の flaky が無いことを確認)
- swiftlint: main とのベースライン差分は既存違反の行数変動のみ、新規違反カテゴリなし
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitDiffLoader をアプリ全体で 1 個の共有インスタンスにし(生成点は ViewerWindowManager.makeDiffLoader() のみ、ViewerWindowController は注入された let を持つだけ)、あわせて要求チケットの取得を契機側へ移して、同じファイル変更イベントから出た複数ウィンドウの要求が 1 回の git diff へ合流するようにした。swift test 全件(1166)パス、両方の修正を個別に戻して該当テストが落ちることを確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
