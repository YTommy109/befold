---
id: TASK-156
title: GitCommandRunner タイムアウト処理の残課題(フォールバック経路のリークと pgid 再利用窓)を解消する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-26 00:47'
updated_date: '2026-07-26 01:18'
labels:
  - bug
  - review
dependencies: []
priority: medium
ordinal: 231000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #303 (TASK-155) のコードレビューで確認されたプロダクション側の残課題 2 件。

1. terminableProcessGroup が nil を返すフォールバック経路 (GitCommandRunner.swift:171 付近) は process.terminate() で git 単体に SIGTERM を送るだけで、SIGTERM を無視する孫プロセスがパイプ書き込み端を握り続けるとリーダースレッドと pipe fd がリークする。TASK-155 が解消したはずのリークがこの経路にだけ残っており、旧実装にあった reader.stackSize = 64KB の緩和も削除済みのためスレッドあたりの常駐スタックはむしろ増えている。テストは pgid==pid 経路しか通らずカバレッジもゼロ。加えて 110-111 行付近のコメント「スレッドは必ず終了する」はこの経路では成立しない。
2. kill(-processGroup, SIGKILL) (174 行付近) は起動時に捕捉した pgid を kill 時に再検証しないため、タイムアウト境界ぎりぎりで git が終了して Foundation が回収した直後に pgid が別プロセスグループへ再利用されると、無関係なプロセスグループを SIGKILL する窓がある(旧実装は単一 pid への SIGTERM で影響が限定的だった)。

いずれもレビュー判定は PLAUSIBLE(エッジ環境依存)だが、ユーザープロセスへの影響がありうるため対応しておく。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フォールバック経路(processGroup 取得失敗時)でも打ち切り後にリーダースレッドと pipe fd が残留しない、またはリークしない設計に変更されている
- [x] #2 kill 時点で pgid の有効性(process.isRunning 等)を再確認し、プロセス終了後に群 SIGKILL を送らない
- [x] #3 GitCommandRunner.swift のコメントが実際の挙動(フォールバック時の限界を含む)と一致している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 読み取りスレッドを「期限付き読み取り」に変える: readDataToEndOfFile を poll(2)+read(2) のループに置き換え、run の timeout と同じ期限で自ら読み取りを打ち切る。これにより「スレッドと fd が解放されるかどうか」がシグナル到達(プロセスグループ kill)の成否に依存しなくなり、フォールバック経路でもリークしない。
2. EOF に達したときだけ waitUntilExit/terminationStatus を採り、done を signal する。期限切れで諦めた場合は signal しない(呼び出し元が terminate 経路へ確実に入るため)。
3. terminate(_:fallingBackTo:) に process.isRunning チェックを入れ、Foundation が reap 済みのときは群 SIGKILL を送らない(pgid 再利用窓を塞ぐ)。
4. コメントを実挙動へ合わせる(「スレッドは必ず終了する」の根拠を期限付き読み取りへ差し替え、フォールバック時に孫が残りうる限界を明記)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: 新規テスト releasesResourcesWhenWriteEndSurvivesTermination(setsid で自前セッションへ抜けた孫が標準出力を握り、プロセスグループへの SIGKILL が届かない形)で、pipe fd とリーダースレッドが基準線へ戻ることを確認。7.15 秒(予算 2 秒 + 猶予 5 秒)で解放されており、EOF を待たずに期限で抜けていることが実測で裏付けられている。terminationGrace を 100_000 秒へ変えるミューテーションでは同テストが 60 秒の時間制限超過で赤になり、検出力があることも確認済み。swift test 全体 697 tests green。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
読み取りスレッドの終了条件を『EOF が来ること』から『EOF または自前の期限』へ変えた。readDataToEndOfFile を poll(2)+read(2) の期限付きループへ置き換え、期限は呼び出し元の予算 + terminationGrace(5 秒)。これで打ち切り時の資源解放がプロセスグループ kill の成否から独立し、グループを特定できないフォールバック経路でもスレッドと pipe fd が残らない。あわせて群 SIGKILL の直前に process.isRunning を確認し、reap 済みで pgid が再利用された場合に無関係なグループを殺さないようにした。コメントもフォールバック時の限界(孫は残りうる)を含めて実挙動へ合わせた。
<!-- SECTION:FINAL_SUMMARY:END -->
