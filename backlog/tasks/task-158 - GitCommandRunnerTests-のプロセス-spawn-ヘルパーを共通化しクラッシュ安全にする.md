---
id: TASK-158
title: GitCommandRunnerTests のプロセス spawn ヘルパーを共通化しクラッシュ安全にする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-26 00:48'
updated_date: '2026-07-26 01:19'
labels:
  - test
  - review
dependencies: []
priority: medium
ordinal: 233000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #303 (TASK-155) のコードレビュー指摘(テストヘルパーの構造)。

1. クラッシュ安全性(最重要・CONFIRMED): killSleepers と processExists は try? process.run() の後に無条件で waitUntilExit() を呼ぶ。spawn が失敗(EMFILE 等 — fd リーク退行を検出すべき状況でこそ起きやすい)すると、未起動 NSTask への waitUntilExit()/terminationStatus が Swift で捕捉不能な NSInvalidArgumentException を投げ、テストプロセス全体がクラッシュする。defer の killSleepers 後始末もスキップされ、TERM 無視の sleeper が CI マシンに残る。再現検証済み。
2. 重複: killSleepers / processExists は rawGit と同じ Process spawn ボイラープレート(executableURL, arguments, nullDevice, try? run, waitUntilExit)の 3〜4 重複。spawn 規約の変更が 4 箇所に波及する。runTool(_:_:in:) 的な単一 private ヘルパーに集約する。
3. 隠れた副作用: makeSleeperScript が名前・doc コメントに現れない git init を実行している。rawGit(dir, ["init"]) をテスト本体に移すか、makeHangingRepo 等に改名して副作用を表出させる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 spawn 失敗時に waitUntilExit()/terminationStatus を呼ばず、テストが Issue として失敗する(プロセスクラッシュしない)
- [x] #2 Process spawn ボイラープレートが単一の共通ヘルパーに集約され、rawGit / killSleepers / processExists がそれを利用している
- [x] #3 makeSleeperScript の git init 副作用が呼び出し側に表出しているか、ヘルパー名が副作用を表している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Process spawn ボイラープレートを private helper runTool(_:_:in:) -> Int32? に集約する。spawn 失敗時は Issue.record して nil を返し、waitUntilExit()/terminationStatus を呼ばない(NSInvalidArgumentException によるプロセスクラッシュを回避)。
2. rawGit / killSleepers / processExists を runTool 経由に書き換える。
3. makeSleeperScript を makeHangingRepo(in:) へ改名し、git init という副作用が名前とドキュメントに現れるようにする。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: swift test 全体 697 tests green。runTool は try process.run() が投げた時点で Issue.record して nil を返し、waitUntilExit()/terminationStatus を一切呼ばない。processExists は Bool? を返すようにして『spawn 失敗』を『存在しない』へ潰さない。rawGit / killSleepers / processExists の 3 箇所がすべて runTool 経由。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
テストヘルパーの構造課題を解消した。Process spawn のボイラープレートを runTool(_:_:in:) へ集約し、spawn 失敗時は Issue として記録して nil を返す(未起動 NSTask への waitUntilExit()/terminationStatus は捕捉不能な NSInvalidArgumentException になりテストプロセスごと落ちるため)。rawGit / killSleepers / processExists がこれを利用する。makeSleeperScript は git init の副作用が名前に現れる makeHangingRepo へ改名した。
<!-- SECTION:FINAL_SUMMARY:END -->
