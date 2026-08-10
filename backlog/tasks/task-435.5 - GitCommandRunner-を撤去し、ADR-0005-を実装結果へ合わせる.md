---
id: TASK-435.5
title: GitCommandRunner を撤去し、ADR 0005 を実装結果へ合わせる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 15:03'
updated_date: '2026-08-10 21:36'
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
- [x] #1 プロダクトコードから /usr/bin/git の Process 実行が消えている（GitCommandRunner.swift が削除され、rg で確認できる）（AC #2）
- [x] #2 外部プロセス起因の手当て（fsmonitor/hooksPath 遮断・環境変数遮断・プロセスグループ kill・タイムアウト待ち）が撤去されている（AC #6）
- [x] #3 GitCommandRunnerTests が撤去され、swift test 全体が通る。撤去前後のスイート実行時間が計測されて Implementation Notes に記録されている
- [x] #4 docs/adr/0005-git-integration-via-libgit2.md が上記 4 点で更新されている
- [x] #5 TASK-226 の扱い（クローズ or 前提書き換え）が決まり、当該タスクへ反映されている
- [x] #6 移行の混在期間に生じる不整合が解消していることを確認する。TASK-435.2 の時点では GitRepository だけが libgit2 で GitStatusReader / GitDiffReader は外部 git のままのため、libgit2 は開けないが git は開けるリポジトリ（partial clone 等）で「ルート解決だけ .undetermined に落ちるがステータスと差分は動く」中間状態が生じる。全実装が libgit2 に揃った時点で、開けないリポジトリでは git 機能が一律に無効化されることをテストで担保する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装結果（2026-08-11）

### 撤去したもの

- `BefoldApp/befold/App/GitCommandRunner.swift`（`GitCommandOutcome` / `GitCommandRunning` /
  `hardeningOptions` / `processEnvironment` / プロセスグループ kill / `DispatchSemaphore` 待ち）
- `BefoldApp/befoldTests/GitCommandRunnerTests.swift`（`@Test` 10 本、2 スイート）
- `.swiftlint.yml` の `unbounded_semaphore_wait` から、削除した테스트ファイルを指す
  stale な `excluded` エントリ（ユーザー承認のうえ実施）

`rg 'GitCommandRunn|GitCommandOutcome'` の一致は 0 件。プロダクトコードから
`/usr/bin/git` の `Process` 実行が消えた。

### GitTestRepo の待機方法（撤去ではなく見直し）

`GitTestRepo.run` の上限なし `waitUntilExit()` に予算を付けた。
`testTimeoutSeconds(fallback: 30)` を過ぎたら `terminate()` してから待つ。
`waitUntilExit()` は呼び出しスレッドを塞ぎ、Swift Testing のテストは協調スレッドプール上で
動くため、git が 1 つハングするとプール幅（コア数）ぶんでテストプロセス全体が止まりうる
（TASK-424 で `DispatchSemaphore.wait()` が少コアの CI を実際に停止させたのと同じ形）。
GitTestRepo 自体は、libgit2 の実装が**実 git の生成物**を読めるかを確かめるフィクスチャ生成に
引き続き必要なため残す（フィクスチャまで libgit2 で作ると同じ実装で書いて同じ実装で読むことになる）。

### AC #3: スイート実行時間

| | 件数 | 時間 |
|---|---|---|
| 撤去前 `GitCommandRunnerTests` 単独 | 10 tests / 2 suites | **8.060 秒** |
| うち `GitCommandRunnerResourceLeakTests` | 7 本 | 8.060 秒のほぼ全部（猶予の満了待ち） |
| 撤去前の全体（非 renderer） | 1348 tests | 16.99 秒 |
| 撤去後の全体（非 renderer） | 1340 tests | 16.56 秒 |

**全体の壁時計はほぼ変わらない。** 8 秒のスイートは他のスイートと並列に走っており、
全体の所要時間は WKWebView 系が律速しているため。撤去の効果は「単独で 8 秒かかる直列スイートが
1 枠を占有しなくなった」ことであり、壁時計の短縮としては現れない。数字を正直に記録する。

### AC #6: 混在期間の不整合の解消

`GitUnusableRepositoryTests` を新設した（実 git を起動しないフィクスチャ）。
partial clone / reftable / 未知の `extensions.*` の 3 パターンで、
`GitRepository.root`（`.undetermined`）・`trackedFiles`（nil）・`worktrees`（空）・
`GitStatusReader.status`（nil）・`GitDiffReader.diff`（nil）・
`GitComparisonBaseResolver.comparisonBase`（nil）が**そろって**縮退することを固定した。
いずれもキャッシュ可能な確定値（`.notARepository` や空スナップショット）を返さない。
繰り返し読んでもクラッシュしないことも押さえた。

### AC #4: ADR 0005 の更新（4 点）

1. 配布形態を static XCFramework + `.binaryTarget` から SPM ソースターゲットへ変更した旨を追記し、
   Consequences の「XCFramework のビルドと更新を自前で回す」を取り消し線で解消済みにした
2. global config を無効化しない判断（`core.excludesFile` が効かなくなるため）を追記した
3. 無効化の目的が「決定性の確保」であって「任意コマンド実行の遮断」ではない旨を明記した
   （libgit2 はフックも textconv も外部 diff driver も実行しない）
4. reftable が libgit2 の main へマージ済みだが未リリースである旨を追記した

あわせて「実装前に潰すべき未確認事項」4 点のうち解消したのは 1 点だけであること、
残る 3 点は App Sandbox を有効にして初めて確かめられるもので TASK-397 が引き取ることを明記した
（解消していないものを解消したように書かない）。

### AC #5: TASK-226 の扱い

**前提を書き換えて Done にした。** 対象であった `GitCommandRunner` が消えたため、
AC #1「git subprocess の待機がスレッドをブロックしない」は async 化ではなく撤去によって
満たされている。旧 AC #2（タイムアウト・terminationGrace の維持）は守る対象が消えたため差し替えた。
残る `GitCommandFileIndex` の actor 化は、待つ相手が 67.2ms の subprocess から 0.263ms の
ライブラリ呼び出しへ変わり上限時間の概念も消えたため、実害が観測されるまで行わない旨を記録した。

### 検証

- `swift test --skip ViewerRenderer`: **1340 tests / 195 suites passed**（16.6s）
- `swift test --filter ViewerRenderer`: **51 tests / 9 suites passed**（0.6s）
- swiftlint: 新規違反ゼロ。削除したファイルの `file_length` 違反 1 件が解消
- swiftformat: 全 9 ターゲットで整形差分なし
- `markdownlint-cli2`: 69 ファイル 0 issues
- `scripts/check-doc-symbols.sh`: exit 0
- `xcodegen generate`: ファイル削除・追加のたびに実行済み
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
外部プロセス方式の残骸を撤去した。GitCommandRunner.swift（300 行）とその 10 本のテストを削除し、rg で GitCommandRunner / GitCommandOutcome の一致が 0 件であることを確認した。.swiftlint.yml の stale な excluded エントリもユーザー承認のうえ除いた。GitTestRepo は libgit2 実装が実 git の生成物を読めるか確かめるフィクスチャ生成に必要なため残し、上限なしの waitUntilExit にだけ予算と terminate を足した。AC #6（混在期間の不整合）は GitUnusableRepositoryTests を新設し、開けないリポジトリで 6 つの読み手がそろって不明・縮退へ落ちることを固定した。ADR 0005 は 4 点を更新し、あわせて「実装前に潰すべき未確認事項」のうち解消したのは 1 点だけである旨も明記した。TASK-226 は対象が消えたため前提を書き換えて Done にした。撤去前後のスイート時間は Implementation Notes に記録（単独 8.060 秒のスイートが消えたが、並列実行のため全体の壁時計は 16.99→16.56 秒でほぼ変わらない）。
<!-- SECTION:FINAL_SUMMARY:END -->
