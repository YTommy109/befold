---
id: TASK-150
title: git 実行の一時失敗をキャッシュに固定しない・タイムアウト時のプロセス残留を解消する
status: In Progress
assignee: []
created_date: '2026-07-25 11:31'
updated_date: '2026-07-25 12:15'
labels:
  - path-reference
dependencies: []
priority: medium
type: task
ordinal: 226000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
パフォーマンスレビュー指摘（低×2）+ コアレビュー指摘。(1) GitCommandFileIndex.swift L46-51, L59-62: rev-parse のタイムアウト等で nil が返ると「git 管理外」としてアプリ再起動まで固定され、ls-files タイムアウト時は空リストが fingerprint 付きでキャッシュされ次の commit までリンク化が全停止する（性能保護機構の副作用による機能劣化）。(2) GitCommandRunner.swift L54-64: terminate() は SIGTERM のみで、読み取りスレッドが readDataToEndOfFile() でブロックしたまま残留しうる。応答しない NFS リポジトリ等で漏れが蓄積する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 失敗（nil / 空）結果はキャッシュせず次回リトライする、または短い TTL 付きネガティブキャッシュにする
- [ ] #2 terminate() 後に pipe.fileHandleForReading を close して読み取りスレッドを EOF で解放する（SIGKILL フォールバックも検討する）
- [ ] #3 失敗→リトライの挙動をテストで固定する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
単純化の検討: TTL 付きネガティブキャッシュ（新しい時刻依存の状態）を足す代わりに、「git が動いて出した答え」と「git を動かせなかった」を型で区別し、前者だけをキャッシュする。
1. GitCommandRunner.run の戻りを Data? から GitCommandOutcome（output / rejected / unavailable）に変える。runString は唯一の呼び出し元へ畳んで削除
2. GitRepositoryReading: root(forFileAt:) -> GitRootLookup（root / notARepository / undetermined）、trackedFiles(at:) -> [URL]?（nil = 実行不能）
3. GitCommandFileIndex: undetermined と nil はキャッシュせず次回リトライ。ls-files 失敗時に既存エントリがあれば stale な索引を返してリンクを維持する（fingerprint は更新しないので次回再取得）
4. rootByDir の [String: URL?] 二重オプショナルを [String: GitRootLookup] に置き換える
5. タイムアウト時に pipe の read 端を close して読み取りスレッドを解放する（ブロック中 close が例外を投げずスレッドを解放することは実機実験で確認済み）
6. テスト: rev-parse 実行不能→次回リトライ、ls-files 実行不能→空をキャッシュしない、失敗時に既存索引を返す
<!-- SECTION:PLAN:END -->
