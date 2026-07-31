---
id: TASK-226
title: GitCommandRunner を async 化し GitCommandFileIndex を actor 化する
status: To Do
assignee: []
created_date: '2026-07-31 09:14'
labels:
  - refactor
dependencies: []
priority: medium
type: task
ordinal: 330000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitCommandRunner.run (befold/App/GitCommandRunner.swift:133-165) は DispatchSemaphore.wait で subprocess 完了をブロック待ちし、GitCommandFileIndex (GitCommandFileIndex.swift) は NSLock を掴んだまま最大 15 秒待つ。呼び出し元は Task.detached だが Swift 6 協調スレッドプールをブロックするためプール枯渇を招きうる（クラス冒頭コメントが自認）。Process.terminationHandler + withCheckedContinuation で async 化し、GitCommandFileIndex は actor に置き換える。GitFileIndexing プロトコルの async 化は TrackedPathResolver / QuickOpenCandidates に波及するため設計判断が必要。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 git subprocess の待機がスレッドをブロックしない（semaphore・専用 Thread が撤去されている）
- [ ] #2 他リポジトリのウィンドウを巻き込むロック待ちが発生しない
- [ ] #3 タイムアウト・terminationGrace の挙動が維持されテストで検証されている
<!-- AC:END -->
