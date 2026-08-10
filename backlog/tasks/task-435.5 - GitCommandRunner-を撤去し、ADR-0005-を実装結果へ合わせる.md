---
id: TASK-435.5
title: GitCommandRunner を撤去し、ADR 0005 を実装結果へ合わせる
status: To Do
assignee: []
created_date: '2026-08-10 15:03'
updated_date: '2026-08-10 15:46'
labels:
  - refactor
dependencies:
  - TASK-435.2
  - TASK-435.3
  - TASK-435.4
parent_task_id: TASK-435
priority: high
type: task
ordinal: 670000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-435 の仕上げサブタスク。すべての呼び出しが libgit2 実装へ移った後に、外部プロセス方式の残骸を撤去する。

## 撤去対象

- `BefoldApp/befold/App/GitCommandRunner.swift`（300 行）一式。`GitCommandOutcome` / `GitCommandRunning` / `hardeningOptions` / `processEnvironment` / タイムアウト時のプロセスグループ kill と fd 回収 / `DispatchSemaphore` によるブロック待ち（AC #6）
- `BefoldApp/befoldTests/GitCommandRunnerTests.swift`（507 行、`@Test` 10 本）。うち `GitCommandRunnerResourceLeakTests` 7 本（:285-506、スイート実測 8.245 秒のうち約 7.2 秒が猶予の満了待ち）は検証対象が消えるため丸ごと不要になる
- `BefoldApp/BefoldTestSupport/GitTestRepo.swift:25` の上限なし `waitUntilExit()`（TASK-424 の Notes が「未対処、記録のみ」と明記）。ただし GitTestRepo 自体はフィクスチャ作成に引き続き必要なため、撤去ではなく待機方法の見直しになる

## ADR 0005 の更新点（親タスクの実測結果を反映する）

1. 配布形態を「static XCFramework + `.binaryTarget`」から「`ibrahimcetin/libgit2` の SPM ソースターゲット」へ変更し、「XCFramework のビルドと更新を自前で回す」コストを Consequences から外す
2. `core.excludesFile` が効かなくなることを Consequences へ追記する（実測: libgit2 は .gitignore / .git/info/exclude / core.excludesFile の 3 経路すべてを見るが、AC #7 のグローバル config 無効化で 3 番目が落ちる。現行の subprocess 実装は HOME を意図的に残しており効いている）
3. グローバル config 無効化の目的が「任意コマンド実行の遮断」ではなく「決定性の確保」である旨を明記する（libgit2 はフックも textconv も外部 diff driver も実行しない）
4. reftable 対応が 2026-08 に libgit2 の main へマージされたが未リリースであることを Fallback 節へ追記する

## 関連タスクへの申し送り

TASK-226（GitCommandRunner の async 化）は対象そのものが消えるため、このサブタスクの完了時にクローズまたは前提の書き換えを行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 プロダクトコードから /usr/bin/git の Process 実行が消えている（GitCommandRunner.swift が削除され、rg で確認できる）（AC #2）
- [ ] #2 外部プロセス起因の手当て（fsmonitor/hooksPath 遮断・環境変数遮断・プロセスグループ kill・タイムアウト待ち）が撤去されている（AC #6）
- [ ] #3 GitCommandRunnerTests が撤去され、swift test 全体が通る。撤去前後のスイート実行時間が計測されて Implementation Notes に記録されている
- [ ] #4 docs/adr/0005-git-integration-via-libgit2.md が上記 4 点で更新されている
- [ ] #5 TASK-226 の扱い（クローズ or 前提書き換え）が決まり、当該タスクへ反映されている
- [ ] #6 移行の混在期間に生じる不整合が解消していることを確認する。TASK-435.2 の時点では GitRepository だけが libgit2 で GitStatusReader / GitDiffReader は外部 git のままのため、libgit2 は開けないが git は開けるリポジトリ（partial clone 等）で「ルート解決だけ .undetermined に落ちるがステータスと差分は動く」中間状態が生じる。全実装が libgit2 に揃った時点で、開けないリポジトリでは git 機能が一律に無効化されることをテストで担保する
<!-- AC:END -->
