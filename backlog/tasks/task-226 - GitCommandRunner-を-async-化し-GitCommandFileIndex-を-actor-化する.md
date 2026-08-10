---
id: TASK-226
title: GitCommandRunner を async 化し GitCommandFileIndex を actor 化する
status: To Do
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:14'
updated_date: '2026-08-10 13:57'
labels:
  - refactor
dependencies:
  - TASK-435
priority: medium
type: task
ordinal: 114000
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

## 再評価(2026-08-10): 保留継続。着手条件 1 を書き換える

TASK-186.2 が Done になったため上記「着手条件 1」に照らして再評価した。結論は保留継続。条件 1 が想定していた前提が、186.2 の設計変更で成立しなくなっているため、条件 1 の文言を差し替える。

### 条件 1 は形式的には成立、実質は不成立

- 186.2 は 2026-08-02 の見直しでポーリングを撤回し FileWatcher 起点のイベント駆動 + デバウンスになった(ドキュメント参照: backlog/completed/task-186.2 の Notes、理由は task-186.md — .git/index の mtime は素の作業ツリー編集では動かず、git status 自身が index を refresh して mtime を動かすためポーリング単独では自己励振する)
- 実装にもタイマーは無い(コード参照: GitIndexWatch.swift:35-42、FileWatcher.swift:12,46-56 の DispatchSource + 0.2 秒デバウンス)
- fingerprint は定期 stat ではなくイベント受信後の門番として 1 回だけ使う(GitStatusStore.swift:91-105 → GitRepository.swift:107-109 は stat のみで subprocess 無し)
- 増えた git 実行は index 書き込みイベント起点の 1 本のみ。さらに fingerprint 一致でスキップ / 同一ルートの in-flight 相乗り(GitStatusStore.swift:110) / --no-optional-locks(GitStatusReader.swift:62-68) の 3 段で抑制される
- 同一リポジトリを N ウィンドウ開いても watcher は N 個だが、実 subprocess は共有ストアで 1 本に畳まれる

つまり git 実行頻度は「ユーザーが index を動かす操作 + 表示中ファイルの保存」の回数に留まり、条件 1 の趣旨である『定期実行によるワーカー占有の頻度増加』は起きていない。

### 条件 2 も不成立

gh issue list --state open は 0 件(実測)。ネットワークマウント・巨大リポジトリでの UI 硬直の報告は無い。

### 保留の根拠の変化

- 軽くなった: 186.2 が新設した status 更新経路は GitCommandFileIndex の NSLock を通らない(GitStatusStore.swift:31-34 に明記)。ロックを掴むのは repositoryRoot / trackedFileIndex の 2 経路のみ(GitCommandFileIndex.swift:52,56)
- 重くなった: git を待つ Task.detached 箇所は上記見積もりの 6 箇所から増えている(GitStatusStore.swift:70/113、GitDiffLoader.swift:97、WorktreeCatalog.swift:36、ViewerWindowManager.swift:337、ViewerWindowController.swift:230、ReferenceResolutionCoordinator.swift:66/93/122)。一括着地のコストは当初見積もりより増加方向
- timeout/grace は当時のまま(GitCommandRunner.swift:69 の timeout: 10 / terminationGrace: 5、最悪 15 秒占有)

### 着手条件(改訂。上記「着手条件」節の 1 を置き換える)

1. git 実行が『ユーザー操作のたび』から『定期実行』に変わる設計を採用するとき(旧: TASK-186.2 に着手するとき。186.2 はイベント駆動で着地したため該当しない)
2. ネットワークマウント(NFS/SMB)上のリポジトリや巨大リポジトリで実際に UI が固まる報告が出たとき(変更なし。現時点で主たるトリガー)

## 優先順位の整理(2026-08-10)

TASK-435(libgit2 移行)を上位へ置いたため、本タスクは 435 の後段に依存する形へ変更した(--dep に TASK-435 を追加)。435 が着地すれば subprocess 待ちそのものが消えるため、本タスクは「不要になった」として Done ではなく取り下げになる見込み。**435 より先に着手しないこと**(撤去予定のコードへ 18 ファイル規模の改修を投じることになる)。
<!-- SECTION:NOTES:END -->
