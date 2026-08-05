---
id: TASK-226
title: GitCommandRunner を async 化し GitCommandFileIndex を actor 化する
status: To Do
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:14'
updated_date: '2026-08-01 10:40'
labels:
  - refactor
dependencies:
  - TASK-241
priority: medium
type: task
ordinal: 506500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitCommandRunner.run (befold/App/GitCommandRunner.swift:133-165) は DispatchSemaphore.wait で subprocess 完了をブロック待ちし、GitCommandFileIndex (GitCommandFileIndex.swift) は NSLock を掴んだまま最大 15 秒待つ。呼び出し元は Task.detached だが Swift 6 協調スレッドプールをブロックするためプール枯渇を招きうる（クラス冒頭コメントが自認）。Process.terminationHandler + withCheckedContinuation で async 化し、GitCommandFileIndex は actor に置き換える。GitFileIndexing プロトコルの async 化は TrackedPathResolver / QuickOpenCandidates に波及するため設計判断が必要。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 git subprocess の待機がスレッドをブロックしない（semaphore・専用 Thread が撤去されている）
- [ ] #2 タイムアウト・terminationGrace の挙動が維持されテストで検証されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査・設計案は作成済み(Plan サブエージェントによる詳細プランあり)。ただしユーザーと協議の結果、このリスクは実際に発生したインシデントではなく予防的な懸念であり、呼び出し元は既に Task.detached でラップ済みで MainActor は現状ブロックされない一方、改修コストが大きいため保留と判断した。

## 保留の根拠(2026-08-01 再評価)

実害として最大だった「他リポジトリのウィンドウを巻き込むロック待ち」は async 化なしで解消できると判明したため、TASK-241 として切り出した(本タスクの AC からも削除済み)。本タスクに残るのは協調スレッドプールのワーカー占有(最悪 15 秒 = timeout 10s + grace 5s)のみで、これは git 自体が遅い環境でしか顕在化しない。

改修コスト:
- 分割着地不可。NSLock を跨いで await できないため Runner→GitRepositoryReading→GitFileIndexing→全呼び出し元まで一括で着地させるしかない
- プロダクト 8 ファイル(TrackedPathResolver, QuickOpenCandidates, GitCommandFileIndex, ReferenceResolutionCoordinator, ViewerWindowManager, ViewerWindowController, AppQuickOpenEnvironment, AppDelegate) + テスト 10 ファイル
- BefoldKit の公開 API 破壊 2 ファイル(TrackedPathResolver.swift, QuickOpenCandidates.swift)。TrackedPathResolver.resolveAll は inout の mutating struct をループで回す構造のためループごと書き換え
- WorktreeCatalog.swift:20 と ViewerWindowManager.swift:75 の @Sendable (URL) -> T クロージャも async 化が必要
- continuation の二重 resume 防止が新規 correctness-critical コードになる(現状は DispatchSemaphore + OutputBox(NSLock) が担保)
- GitCommandRunnerTests のリーク検査 6 本がスレッド名 'GitCommandRunner.read' と semaphore 前提に依存しており全面書き直し。TASK-150/155/156/157 で積み上げた回帰検出資産を一時的に失う
- ThreadRecordingGitIndex 系(AppQuickOpenEnvironmentTests, ViewerWindowControllerTests)の「MainActor 上で呼ばれていない」検証が意味を失うため別の担保が必要

得られるもの:
- Task.detached を 6 箇所(ViewerWindowManager L292, ViewerWindowController L167, ReferenceResolutionCoordinator L66/L93/L122, AppQuickOpenEnvironment L55/L68)剥がせる。detached は優先度を継承せずキャンセルも伝播しないため、async 化すれば優先度継承とキャンセル対応が自然に得られる
- 走り出した git をウィンドウクローズ時に打ち切れるようになる(現状は不可能)

## 着手条件(どちらかが成立したら再評価する)

1. TASK-186.2(.git/index fingerprint ポーリングで自動更新)に着手するとき。git 実行が「ユーザー操作のたび」から「定期的」に変わりワーカー占有の頻度が上がるため
2. ネットワークマウント(NFS/SMB)上のリポジトリや巨大リポジトリで実際に UI が固まる報告が出たとき
<!-- SECTION:NOTES:END -->
