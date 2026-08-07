---
id: TASK-346
title: git diff の合流が壁時計の重なりに依存しているのを構造で塞ぐ
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-07 00:53'
updated_date: '2026-08-07 02:39'
labels:
  - test
  - flaky
  - ci
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/actions/runs/31080059382'
priority: high
type: bug
ordinal: 505000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 症状

main の CI（run 31080059382, 2026-08-06 push）の ThreadSanitizer ジョブで、ViewerWindowManagerDiffTests「同じファイルを 2 窓で開いても git diff は 1 回に合流する」が失敗した。1171 テスト中この 1 件のみ。`ViewerWindowManagerDiffTests.swift:152` で `Expectation failed: (reader.callCount → 3) == (before + 1 → 2)`。当該テストは TSan 下で 125.074 秒（ローカル単独実行は 1.348 秒）。

## 原因（実測とコード参照で確定）

**テストの問題ではなく、本番の合流が壁時計の重なりに依存している。**

- `GitDiffLoader.swift:60-68`: `inFlight[key]` が空なら、チケットの新旧に関係なく即座に `start()` する。合流できるのは「走行中の取得が存在する間に到着した要求」だけで、既に完了して忘れられた取得には相乗りできない（結果をキャッシュしない設計のため構造上そうなる）。
- `ViewerWindowController+Diff.swift:32-42`: チケットは契機の時点で取るが、その後 `index.repositoryRoot` の解決を await してから `loader.diff(...)` を呼ぶ。**要求の登録は await の後**。
- したがって窓 A の継続が先に走って取得を完走し、窓 B の継続がその後に MainActor へ戻ると、B は空の inFlight を見て自分の取得を始める。callCount = 3 の内訳はセットアップ 1 + 合流し損ねた 2。
- TASK-327 の実測: full suite 実行中はメインアクターが 5.1〜8.3 秒到達不能、失敗回は 15 秒予算内に一度も到達しなかった。TSan ジョブは全体実行なので B の継続が A の完走を跨ぐ条件が揃う。

含意: 負荷時には 1 回のファイル変更で窓の数だけ `git diff` が起動する。TASK-325 が防ごうとした事象が条件付きで残っている。

起票時に書いた「セットアップの後追い再取得が `before` 採取後に着弾する」という見立ては**実測で否定した**（DIFF_PROBE を仕込んだローカル実行でセットアップの取得は 1 回のみ、後追いなし。取得を即答にした 3 回の実行でも合流は成立）。

## 方針

合流の根拠を「時間的に重なったか」から「同じ契機のターンで登録されたか」へ移す。要求の登録を契機の同期ターン（await より前）で行い、走行中バッチが**その契機のターンの間だけ開いている**ようにする。時間依存が消え、テストから `Task.sleep` による待機が不要になる。

同型 3 件目にあたるため個別修正はしない（CLAUDE.md「同型のバグが 2 回目に出たら個別修正をやめて構造で塞ぐ」）。TASK-327 は壁時計ポーリング依存のテストを CLI 側 2 件で個別修正している。

## 保たなければならない既存の契約

- `GitDiffLoaderTests.laterRequestGetsFreshResult`: 取得が始まった**後**に生まれた要求は、相乗りせず取り直した新しい結果を受け取る（TASK-321）。同期登録にすると素朴には相乗りしてしまうため、バッチの開閉で区別すること。
- `GitDiffLoaderTests.doesNotCacheResults`: 結果をキャッシュしない。
- `ViewerWindowManagerDiffTests.openViewerSharesDiffLoader`: ローダーはアプリ全体で 1 個。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 当該テストが ThreadSanitizer 付きの CI で 10 回連続して失敗しない
- [x] #2 GitDiffLoader が「同じ契機で登録された兄弟要求は、実行順に関係なく取得 1 回に合流する」ことをテストで固定している（要求を逐次 await しても 1 回）
- [x] #3 合流の可否が壁時計の重なりではなく、契機の同期ターンで登録されたかどうかで決まっている
- [x] #4 取得が始まった後に生まれた要求は相乗りせず取り直す、という既存契約（TASK-321）が保たれている
- [x] #5 ViewerWindowManagerDiffTests の当該テストから Task.sleep による待機と reader の delay 依存が無くなっている
- [x] #6 設計変更を戻すと新しい回帰テストが落ちることを確認している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. **赤テストを先に書く**（TDD）。`GitDiffLoaderTests` に「同じ契機で取った 2 つの要求を逐次 await しても取得は 1 回」を追加する。現行設計では 1 件目の完了後に inFlight が空になり 2 件目が再取得するため 2 回になり、決定的に落ちる。これが CI の失敗（callCount 3）と同じ機序。

2. **GitDiffLoader を同期登録へ作り替える**。
   - `diff(forFileAt:resolvingRootWith:) -> Task<GitFileDiff?, Never>` を**同期**メソッドにする。呼び出した瞬間に `inFlight[fileKey]` を見て、開いているバッチがあればその Task を返し、無ければ新しいバッチを作る。
   - バッチは**生成ターンの間だけ開いている**。閉じるのは取得タスク本体の先頭、`Task.detached` で reader を呼ぶ**前**。`Task { @MainActor ... }` の本体は次のターンで走るため、同じ契機の兄弟は必ず開いている間に登録され、後続の契機は必ず閉じた後になる。時間ではなく順序で決まる。
   - root 解決をローダー内へ移す（呼び出し側は `() -> URL?` のクロージャを渡す）。解決は取得タスク内の detached で行い、MainActor 上の syscall を増やさない（TASK-322 の制約を維持）。root が nil なら nil を返す。
   - `Ticket` / `takeRequestTicket()` / `while let running` ループ / チケット比較を撤去する。合流の判定がバッチの開閉に一本化されるため不要になる。
   - キーは file のみ（root を外す）。実測: root は `url.deletingLastPathComponent()` の純粋関数で、`GitCommandFileIndex.rootByDir` が無効化されないキャッシュを持つため同一 file に異なる root は渡らない（GitCommandFileIndex.swift:96-112）。呼び出し元もプロダクションでは 1 箇所（ViewerWindowController+Diff.swift:42）。この不変条件を doc コメントで呼び出し側の契約として明記する。

3. **走行中の取得への後続要求の扱いを維持する**。閉じたバッチが走行中なら、その完了を待ってから取り直す（現行の while ループと同じ振る舞い）。`laterRequestGetsFreshResult`（TASK-321）が回帰検知として効き続けることを確認する。

4. **refreshDiff を同期登録へ書き換える**。`ViewerWindowController+Diff.swift` で、Task を作る**前**に `loader.diff(forFileAt:resolvingRootWith:)` を呼んで Task を受け取り、その後 `Task { await task.value; ... }` で結果を書き戻す。着地時の `fileURL == url` と `diffDisplayPreference.isEnabled` の再確認は現状どおり残す（TASK-317 / 項目 8）。

5. **ViewerWindowManagerDiffTests の当該テストを決定的にする**。`Task.sleep(600ms)` と `RecordingDiffReader(delay: 0.2)` への依存を外す。セットアップの静止も、壁時計ではなく取得回数の観測で判定する形に置き換える。

6. **検証**。
   - 新テストが設計変更を戻すと落ちることを実測で確認する（AC#6。通っただけでは何も検証していない）。
   - `swift test` の全体実行を複数回。
   - swiftformat を fix モードで回し、swiftlint は origin/main とのベースライン差分ゼロを `/swiftlint-baseline` の手順で確認する。
   - 新規ファイルは追加しない想定なので `xcodegen generate` は不要。追加した場合は必ず実行する。

7. **TSan での確認**。ローカルで TSan を有効にして当該テストを繰り返し実行し、失敗ゼロを確認する。AC#1 の「CI で 10 回連続」は PR 後の CI 実行で確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-07 実測: 起票時の見立て（セットアップの後追い再取得が before 採取後に着弾する）を否定した。DIFF_PROBE を仕込んだローカル実行でセットアップの取得は 1 回のみ・後追いなし。取得を即答（delay 0）にした 3 回の実行でも合流は成立した。

確定した機序: `GitDiffLoader` の合流は「走行中の取得が存在するか」で決まる（旧 GitDiffLoader.swift:60-68）。要求の登録は `refreshDiff` がルート解決を await した後に行われていた（旧 ViewerWindowController+Diff.swift:32-42）。そのため窓 A の継続が先に完走し窓 B の継続が後から戻ると、B は空の inFlight を見て自分の取得を始める。ticket は「自分より後に始まった取得か」の判定にしか使われず、既に終わって忘れられた取得には相乗りできない。

実装: 合流の根拠を時間から順序へ移した。
- `diff(forFileAt:resolvingRootWith:)` を同期メソッドにし、呼んだその場でバッチへ登録する。バッチを閉じるのは取得タスク本体の先頭（ツリーを読み始める直前）で、これは登録したターンより後になることが保証される。
- `Ticket` / `takeRequestTicket()` / while ループ / チケット比較を撤去した。合流判定がバッチの開閉に一本化され、正味 13 行減った。
- ルート解決をローダー内（detached）へ移し、呼び出し側は `() -> URL?` を渡すだけにした。TASK-322 の「メインアクター上で同期の git rev-parse を呼ばない」は維持。
- キーは file の正規化パスのみ。root を外す根拠は調査済み（GitCommandFileIndex.rootByDir は無効化されないキャッシュ、root は url.deletingLastPathComponent() の純粋関数、プロダクションの呼び出し元は 1 箇所）。この不変条件を doc コメントで呼び出し側の契約として明記した。

検証（すべて実測）:
- 赤の確認: 新テスト「同じ契機の要求は、逐次に処理されても 1 回の取得に合流する」は旧設計で `callCount → 2` == 1 で落ちた（0.001 秒、TSan なしで決定的に再現）。
- AC#6: バッチを登録時点で閉じる（isAcceptingRequests: false）ように戻すと 3 件が落ちる。GitDiffLoaderTests 2 件（callCount 2/1, 3/1）と ViewerWindowManagerDiffTests 1 件（calls 6 vs 5）。戻すと 15 件が 1.219 秒で通る。
- 全体実行: 1182 tests passed（21.2 秒）。
- TSan: 差分関連 15 件を 3 回連続 pass。CI と同じ `BEFOLD_TEST_TIMEOUT_SECONDS=120` で全体実行 → 1182 tests passed（69.8 秒）、データ競合の報告なし。なお 120 を指定しないと ViewerStoreFileGoneTests 4 件が 60 秒の予算切れで落ちる（CI はジョブ env で 120 を設定済み、ci.yml:93）。
- swiftlint: origin/main とのベースライン差分ゼロ（両者 78 件）。
- swiftformat: fix モードで 1 ファイル整形済み。新規ファイルなしのため xcodegen は不要。

テスト側の変更: 当該テストから `Task.sleep(600ms)` と `RecordingDiffReader(delay: 0.2)` を撤去した。取得のたびに違う本文を返す `SequenceDiffReader` を DiffTestSupport へ移して共有し、「2 窓が同じ本文を受け取ったか」で合流を判定する。合流に失敗すると本文が食い違うため、実行順がどうずれても結論が変わらない。実行時間は 15.5 秒から 1.2 秒になった。

2026-08-07: この変更で取得までの await のホップ数が減り、既存の flaky テスト ViewerWindowControllerDiffTests「ファイル切替直後の取得契機でも切替先の種別でゲートする」（:241）の失敗率が上がって CI build-and-test が落ちた。origin/main でも単体実行 5 回中 4 回落ちる（実測）ため不安定さ自体は先行するが、CI を通らなくした責任は本変更にある。TASK-347 として起票し、同じ PR #427 の中で対処する。

2026-08-07（2 回目の CI 失敗）: マネージャ側テストが CI で `reader.calls → 3` == `before + 1 → 2` で落ちた。セットアップ由来の取得が何回走るかは契機の重なり方で変わり、「静止した」と言える瞬間が無いため、`before + 1` の算術そのものが実行順に左右されていた（ローカルでは再現せず CI でのみ出た）。

回数の算術をやめ、「2 窓が同じ本文へ着地したか」で判定する形に変えた。取得のたびに違う本文を返す `SequenceDiffReader` に 20 件用意し（末尾に張り付くと別々の取得が同じ本文になって食い違いを見逃す）、まず両窓が取り直しの結果を受け取るまで待ってから `texts[0] == texts[1]` を assert する。

途中、待機条件の中に一致判定を混ぜた版を作ったが、合流を壊しても pass=3/3 で通ってしまい検知能力を失っていた（実測で気付いた）。待機と判定を分けたところ、合流を壊すと `"取得5" == "取得6"` で 14.8 秒で落ちるようになった。

検証: 修正あり 10/10 pass、合流を壊すと明示のアサートで失敗。全体実行 1182 件通過（21.4 秒）、TSan 全体実行 1182 件通過（58.6 秒）。

2026-08-07（マージ後の main CI = run 31141164942）:
- **thread-sanitizer ジョブで当該テスト「同じファイルを 2 窓で開いても git diff は 1 回に合流する」は通過した**（AC#1 の対象は解消）。同ジョブは無関係の GitRepositoryIntegrationTests 1 件で落ちており、TASK-350 として起票した。
- build-and-test は「ソース表示へ切り替えたら差分を取り直す」（callCount → 2 == 1）で落ちた。本変更でターンをまたぐ契機が合流しなくなった結果であり、テスト側は TASK-348 で修正、合流の網羅が狭まった件は TASK-349 として起票した。
<!-- SECTION:NOTES:END -->
