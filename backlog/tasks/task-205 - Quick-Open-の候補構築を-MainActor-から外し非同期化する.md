---
id: TASK-205
title: Quick Open の候補構築を MainActor から外し非同期化する
status: To Do
assignee: []
created_date: '2026-07-31 02:48'
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
- [ ] #1 Quick Open パネル表示時、git サブプロセス実行・ディレクトリ再帰走査・normalizedPathKey 計算がメインスレッドで実行されない
- [ ] #2 パネルは即時表示され、候補集合の到着後に表示が差し替わる(遅延到着時も入力・履歴表示が先に機能する)
- [ ] #3 パスモードのディレクトリ列挙がキーストロークごとにメインスレッドをブロックしない
- [ ] #4 QuickOpenCandidates の重複除去で normalizedPathKey の計算が候補ごとに 1 回になる
- [ ] #5 既存の QuickOpen 系テストが通り、非同期化した収集ロジックにテストがある
<!-- AC:END -->
