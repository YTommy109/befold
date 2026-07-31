---
id: TASK-205
title: Quick Open の候補構築を MainActor から外し非同期化する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 02:48'
updated_date: '2026-07-31 07:32'
labels:
  - refactoring
  - performance
dependencies: []
references:
  - BefoldApp/befold/App/QuickOpenModel.swift
  - BefoldApp/befold/App/AppQuickOpenEnvironment.swift
  - BefoldApp/BefoldKit/QuickOpenCandidates.swift
  - BefoldApp/befold/App/ReferenceResolutionCoordinator.swift
priority: high
ordinal: 285000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
⌘P 押下時、QuickOpenModel.init が @MainActor 上で AppQuickOpenEnvironment.candidateSet() を同期呼び出しし、git rev-parse / git ls-files サブプロセス待ち(GitCommandRunner のタイムアウトは 10 秒)、DirectoryFileScanner の再帰走査(最大 10,000 件)、候補ごとの normalizedPathKey 計算(FS I/O)がすべてメインスレッドで走る。応答しない NFS リポジトリでは UI が最大 10 秒フリーズしうる。GitCommandFileIndex のコメントは「呼び出し元が MainActor 外で解決する」前提を書いているが、この経路ではその前提が破れている。ReferenceResolutionCoordinator.resolveReferences と同型の「Task.detached + 世代番号」パターンの横展開で解消できる。パスモード(QuickOpenModel.swift:166)のキーストロークごとの同期ディレクトリ列挙も同様。また QuickOpenCandidates.swift:127-131 は where 節と本体で normalizedPathKey を 2 回計算しており、コメント(一度だけ計算)と実装が乖離している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Quick Open パネル表示時、git サブプロセス実行・ディレクトリ再帰走査・normalizedPathKey 計算がメインスレッドで実行されない
- [x] #2 パネルは即時表示され、候補集合の到着後に表示が差し替わる(遅延到着時も入力・履歴表示が先に機能する)
- [x] #3 パスモードのディレクトリ列挙がキーストロークごとにメインスレッドをブロックしない
- [x] #4 QuickOpenCandidates の重複除去で normalizedPathKey の計算が候補ごとに 1 回になる
- [x] #5 既存の QuickOpen 系テストが通り、非同期化した収集ロジックにテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. QuickOpenEnvironment の candidateSet() / directoryEntries(in:) を async 化する。
2. AppQuickOpenEnvironment は MainActor 上で Sendable な入力(gitIndex/recentURLs/bookmarkedURLs/hidden 設定/root 解決に必要な URL)を捕捉し、ReferenceResolutionCoordinator.resolveReferences と同じ Task.detached(priority: .userInitiated) で候補収集・ディレクトリ列挙を実行する。
3. QuickOpenModel の init は同期のまま(パネルは即時表示)。candidateSet を空で初期化し、loadTask で非同期取得 → 到着後に refresh() で差し替える。
4. refresh() は世代番号で管理する。empty/fuzzy はメモリ上の同期処理のまま、path モードのみ非同期タスクにし、世代が最新のときだけ candidates に反映する。
5. QuickOpenCandidates.collect の重複除去ループで normalizedPathKey を候補ごとに 1 回だけ計算する。
6. テスト: QuickOpenModelTests を await 対応(waitForPendingWork シーム)、候補集合の遅延到着でも履歴・入力が先に機能することのテストを追加。QuickOpenCandidatesTests は既存を維持。
7. swift build && swift test
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証:
- AC1: befoldTests/AppQuickOpenEnvironmentTests.swift の candidateSetIsBuiltOffTheMainThread。GitFileIndexing スタブが記録した Thread.isMainThread がすべて false。git 解決・DirectoryFileScanner 走査・normalizedPathKey 計算は同じ Task.detached 内の後段にあるため、この観測で収集全体のスレッドが確定する。
- AC2: QuickOpenModelTests の modelIsUsableBeforeCandidateSetArrives / laterQueryWinsOverArrivingCandidateSet。候補集合を関門で止めたまま init が返り、その状態で入力を受け付け、到着後に絞り込み結果へ差し替わることを確認。
- AC3: QuickOpenModelTests の pathModeEnumerationDoesNotRunInline(queryText の setter から戻った時点では列挙結果が未反映)と AppQuickOpenEnvironmentTests の directoryEntriesAreEnumeratedAsynchronously。
- AC4: QuickOpenCandidates.collect の重複除去ループを where 節から guard へ組み替え、normalizedPathKey を候補ごとに 1 回だけ計算する形にした。既存 QuickOpenCandidatesTests / GitCommandFileIndexTests は通過。
- AC5: swift build 成功、swift test で 910 tests / 126 suites すべて通過(QuickOpen 系 5 スイート含む)。

設計メモ: QuickOpenModel.init は同期のまま(パネル即時表示)。candidateSet は空で始め loadTask で差し替える。絞り込みは世代番号で管理し、空入力・fuzzy はメモリ上の純粋計算なので同期、パスモードのみタスクへ逃がす。@MainActor クラスのため deinit からタスクを cancel できず、タスク側は weak self + 世代チェックで打ち切る。
project.yml / Package.swift は変更不要(どちらもディレクトリ単位でソースを拾うため、新規テストファイルの追加だけで済む)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Quick Open の候補構築をメインスレッドから外した。QuickOpenEnvironment の candidateSet() / directoryEntries(in:) を async 化し、AppQuickOpenEnvironment 側で ReferenceResolutionCoordinator.resolveReferences と同じ Task.detached(priority: .userInitiated) に載せた。QuickOpenModel の init は同期のまま(パネル即時表示)で、候補集合は非同期に到着してから表示を差し替える。絞り込みは世代番号で管理し、パスモードのディレクトリ列挙のみタスクへ逃がした。QuickOpenCandidates.collect の重複除去は normalizedPathKey を候補ごとに 1 回だけ計算する形へ直した。検証は AppQuickOpenEnvironmentTests(スレッド観測)・QuickOpenModelTests(遅延到着・世代優先・パスモード非同期)の新規テストと swift test 全 910 件通過。
<!-- SECTION:FINAL_SUMMARY:END -->
