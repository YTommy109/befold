---
id: TASK-151
title: パス参照解決の関心を ViewerWindowController から分離し DI シームを整える
status: Done
assignee: []
created_date: '2026-07-25 11:31'
updated_date: '2026-07-25 12:44'
labels:
  - path-reference
  - refactor
dependencies: []
priority: medium
type: task
ordinal: 227000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UI 層レビュー指摘。(1) ViewerWindowController.swift が 703 行（warning 閾値 400 行超過、本機能で +43 行悪化）。パス参照解決の関心一式（gitFileIndex / pathResolver / handleOpenReference / resolveReferences / warm 呼び出し×2）は SidebarNavigator の流儀で ReferenceResolutionCoordinator 等へ切り出せるまとまり。(2) init が具象 GitCommandFileIndex を受ける（warm がプロトコル GitFileIndexing 外にあるため）。注入省略時の unit テストでも init 時の warm 経由で実 git サブプロセスが背景起動し、Unit/Integration 分離規約と摩擦。(3) ViewerWindowManager.swift L26 の `private let gitFileIndex = GitCommandFileIndex()` は注入シームがなく、規約「新しい外部依存はデフォルト引数付きイニシャライザ注入」に違反。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 パス参照解決の関心一式が凝集単位として ViewerWindowController から分離されている
- [x] #2 GitFileIndexing プロトコルに warm を収載し、コントローラ側の依存を any GitFileIndexing にする
- [x] #3 ViewerWindowManager の gitFileIndex がデフォルト引数付きイニシャライザ注入になっている
- [x] #4 unit テストで実 git サブプロセスが起動しない（スタブ注入経路がある）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitFileIndexing に warm(forFileAt:) を追加（既定は no-op 拡張。warm は最適化ヒントで必須挙動ではないため）
2. ReferenceResolutionHost（weak 参照プロトコル）+ ReferenceResolutionCoordinator を新設し、SidebarNavigator / SidebarNavigatorHost の流儀に揃える。移す責務: gitIndex 保持・resolver・warm・handleOpenReference・resolveReferences
3. ViewerWindowController の依存を any GitFileIndexing に変え、既定は git を起動しない DisabledGitFileIndex にする（現行の既定 GitCommandFileIndex() は、注入忘れ時に共有されない実索引が静かに生まれる＝規約が禁じる形でもある）
4. ViewerWindowManager の gitFileIndex をデフォルト引数付きイニシャライザ注入にする
5. 「Manager が生成するコントローラへ共有索引を注入している」ことをテストで固定し、既定を no-op にしたことで本番の配線が黙って外れないようにする
6. 既存テスト（controller.pathResolver 差し替え 3 件）をコーディネータ経由へ追従
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ReferenceResolutionCoordinator + ReferenceResolutionHost を新設し、SidebarNavigator / SidebarNavigatorHost の流儀（weak host 参照 + 〜Host プロトコルで逆方向依存を切る）に揃えた。移した責務は索引の先読み・クリック時のオープン・表示時の一括解決。ViewerWindowController には薄い委譲メソッドと Host 実装（referenceBaseURL / openReference / presentReferenceNotFound）だけが残る。
GitFileIndexing に warm(forFileAt:) を追加。既定実装を no-op にしたのは、warm が解決の前提ではなく最適化ヒントであり、フェイクに実装を強制する意味がないため。
コントローラの既定を GitCommandFileIndex() から DisabledGitFileIndex() に変更した。従来の既定は、注入を書き忘れると「共有されない実索引」が静かに生まれてウィンドウごとに git ls-files を重複実行する形であり、規約が禁じる形でもあった。既定を no-op にすると本番の配線が外れたとき静かに機能が消えるため、ViewerWindowManager が共有索引を注入していることを固定するテストを追加してその穴を塞いだ（注入行を削除すると warmedPaths が空になって落ちることを確認済み）。
テストフィクスチャ MockedViewerWindowManager も RecordingGitFileIndex を注入するようにしたので、unit テストのウィンドウ生成で実 git subprocess は起動しない。
ファイル行数は 703 → 692 行。SwiftLint の 400 行閾値超過は本タスク前からの状態であり、パス解決以外の関心（ツールバー・ウィンドウ・メニュー）の分割は本タスクの範囲外。
検証: swift test 690 tests（Integration 含む）全パス、swift build（SwiftLint 込み）、swiftformat 適用済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
パス参照解決の関心を ReferenceResolutionCoordinator へ切り出し（SidebarNavigator と同じ weak host + 〜Host プロトコルの流儀）、索引の依存を any GitFileIndexing に抽象化した。コントローラの既定を git を起動しない DisabledGitFileIndex にして unit テストが実 subprocess を踏まないようにし、代わりに ViewerWindowManager が共有索引を注入していることを回帰テストで固定（注入を外すと落ちることを確認済み）。swift test 690 件全パス。
<!-- SECTION:FINAL_SUMMARY:END -->
