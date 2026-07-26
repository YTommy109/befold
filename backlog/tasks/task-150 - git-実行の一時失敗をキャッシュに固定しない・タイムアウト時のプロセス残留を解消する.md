---
id: TASK-150
title: git 実行の一時失敗をキャッシュに固定しない・タイムアウト時のプロセス残留を解消する
status: Done
assignee: []
created_date: '2026-07-25 11:31'
updated_date: '2026-07-25 12:25'
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
- [x] #1 失敗（nil / 空）結果はキャッシュせず次回リトライする、または短い TTL 付きネガティブキャッシュにする
- [x] #2 terminate() 後に pipe.fileHandleForReading を close して読み取りスレッドを EOF で解放する（SIGKILL フォールバックも検討する）
- [x] #3 失敗→リトライの挙動をテストで固定する
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化を優先し、TTL 付きネガティブキャッシュ（時刻依存の新しい状態）ではなく型で区別する方針を採った。GitCommandRunner.run は Data? から GitCommandOutcome（output / rejected / unavailable）へ、GitRepositoryReading は root -> GitRootLookup（root / notARepository / undetermined）と trackedFiles -> [URL]?（nil = 実行不能）へ変更。これで「キャッシュしてよいのは確定した答えだけ」がコード上明示され、rootByDir の [String: URL?] 二重オプショナルも解消した。runString は唯一の呼び出し元へ畳んで削除。
ls-files 失敗時は、前回の索引が残っていればそれを返す（fingerprint は更新しないので次回再取得）。リンクが一時的に全滅するより stale でも生かす方が損失が小さいため。
close() の安全性: スクラッチで実験（孫プロセスが標準出力を握ったまま親が terminate → close）し、readDataToEndOfFile がブロック中に read 端を close しても例外を投げず 0 バイトで復帰してスレッドが解放されることを確認した。SIGKILL フォールバックは入れていない。読み取りスレッドの解放という実害はこの close で解消し、対象の 2 コマンドは builtin で SIGTERM を無視しないため。
実効性の確認: GitCommandFileIndex を一時的に旧挙動（判定不能もキャッシュ / 列挙失敗を空リスト扱い）へ書き換えて実行し、追加した 2 テストが 4 つの Expectation で落ちることを確認済み。復元後は全パス。
検証: swift test 689 tests（Integration 含む）全パス、swift build（SwiftLint 込み）、swiftformat 差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
git 実行結果を「答え」と「実行不能」に型で分け、実行不能な結果をキャッシュしないようにした。タイムアウト 1 回でリポジトリが恒久的に「git 管理外」扱いになる問題と、ls-files 失敗時に空の索引が次の commit まで固定される問題を解消。列挙失敗時は前回の索引を返してリンクを維持する。タイムアウト時は pipe の読み取り端を閉じて読み取りスレッドを解放（安全性は実験で確認）。旧挙動を再現して新テストが落ちることを確認済み、swift test 689 件全パス。
<!-- SECTION:FINAL_SUMMARY:END -->
