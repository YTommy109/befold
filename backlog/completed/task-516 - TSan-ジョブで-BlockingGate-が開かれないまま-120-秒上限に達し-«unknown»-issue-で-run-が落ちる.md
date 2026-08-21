---
id: TASK-516
title: TSan ジョブで BlockingGate が開かれないまま 120 秒上限に達し «unknown» issue で run が落ちる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-18 11:25'
updated_date: '2026-08-19 02:18'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 756000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
thread-sanitizer ジョブが、全スイート pass でありながら 2 件の «unknown» issue で exit 1 になる。

## 事実（実測）

- run [32025054306](https://github.com/YTommy109/befold/actions/runs/32025054306)（main / commit c6b76b66）の thread-sanitizer ジョブ。
  `✘ Test «unknown» recorded an issue at GitStatusStoreTests.swift:73:38: Issue recorded` が 2 件。
  `✘ Test run with 1607 tests in 255 suites failed after 258.892 seconds with 2 issues.`
- 他ジョブ（build-and-test / js-test / type-group-size）はすべて成功しており、TSan ジョブ限定。
- `GitStatusStoreTests.swift:73` は `FakeReader.status` 内の `block.wait("FakeReader.status")`。
  `BlockingGate.wait` は `BEFOLD_TEST_TIMEOUT_SECONDS`（TSan ジョブでは 120）で上限に達すると
  `Issue.record` する（BlockingWait.swift:34-40）。つまりゲートが **open() されないまま 120 秒経過**した。
- このゲートを使う唯一のテストは `foldsConcurrentRequestsForSameRoot`（GitStatusStoreTests.swift:210-239）。
  `release.open()` は `await secondRootResolved.wait()` の後にしか実行されない（:233-234）。
- `BlockingGate` は TASK-427 で「テスト終了後の余分な呼び出しが永久に詰まらないよう」開閉フラグ方式に
  したもので、doc コメント（BlockingWait.swift:44-54）が本件とまったく同じ現れ方
  （全 pass でも «unknown» 1 件で run が落ちる / PR #468 の run 31386949217）を記録している。
  今回は同じ症状が別のゲートで再発している。

## 構造上の問題（推測を含む）

`release.wait()` は **Swift concurrency の協調スレッドを同期的に塞ぐ**。塞いだまま、
解放に必要な `secondRootResolved.open()` を別タスクの前進に依存しているため、
TSan（5〜15 倍のスローダウン）と 1600 件超の並列実行で協調スレッドが枯渇すると
前進保証が壊れ、`release.open()` に到達しない。

**未確認**: この推測は実測していない。`swift test --sanitize=thread --filter GitStatusStoreTests` を
反復しても単独では再現しない見込みで（並列度が足りない）、全件実行の反復か、
協調スレッド数を絞った実行（`LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` 等）で確かめる必要がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 TSan 相当（swift test --sanitize=thread）の全件実行を反復し、«unknown» issue が出ないことを実測する
- [x] #2 foldsConcurrentRequestsForSameRoot が協調スレッドを同期的に塞がない形になっている、または塞いでも前進が保証される根拠が示されている
- [x] #3 同じ形（同期ブロック + 別タスクの前進に依存した解放）が他のテストに無いことを確認し、あれば併せて直すか別タスクへ申し送っている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 再現手順を確立する（完了）: LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 + BEFOLD_TEST_TIMEOUT_SECONDS=8 で swift test を回すと、GitStatusStoreTests / GitCommandFileIndexConcurrencyTests / ViewerRendererContentUpdateIntegrationTests の 3 スイートで «unknown» issue が出る。CI TSan の症状と同型。
2. 構造で塞ぐ: 同期的に長く塞ぐ処理（git subprocess・ファイル読み込み）を協調スレッドプールの外へ出す共有ヘルパー（DispatchQueue + withCheckedContinuation）を BefoldKit に追加する。
3. 上記 3 スイートが叩く本番の seam（GitStatusStore の Task.detached 3 箇所ほか）をヘルパー経由へ差し替える。
4. STRICT=1 での全件実行と、swift test --sanitize=thread の全件実行を反復して «unknown» issue が出ないことを実測する。
5. 可能なら CI に STRICT=1 の常設ジョブを足し、同型の再発を決定的に落とす（全件が STRICT=1 で現実的な時間内に通る場合のみ）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 原因（実測で確定）

推測どおり「同期ブロックが Swift 並行の協調スレッドプールを塞ぎ、解放に必要な別タスクの前進が止まる」形だった。単独スイートでも `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`（プール幅 1）を与えると決定的に再現する。

- `BEFOLD_TEST_TIMEOUT_SECONDS=8 LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 swift test --filter GitStatusStoreTests` → CI と同じ `Test «unknown» recorded an issue at GitStatusStoreTests.swift:73` が出て、続けて `(reader.callCount → 2) == 1` も落ちる。1 本目が上限（8 秒）で戻ってから 2 本目が走るため in-flight の畳み込みが成立しない。
- 同じ形が **GitStatusStoreTests だけではなかった**。同条件で `GitCommandFileIndexConcurrencyTests.swift:45`（BlockingRepository.trackedFiles）と `ViewerRendererContentUpdateIntegrationTests.swift:359`（SlowFileReader.readData）でも «unknown» issue が出た。
- «unknown» になる理由も確定: 足止めしているフェイクは `Task.detached` の中で走っており、detached は task-local を継承しないため `Issue.record` が現在のテストへ紐づかない。

## 対処（構造で塞ぐ）

同型の 3 度目（TASK-424 → TASK-427 → 本件）なので、テスト個別の手当てではなく置き場そのものを変えた。

1. `BefoldApp/BefoldKit/BlockingWork.swift` に `withBlockingWork(qos:_:)` を新設。呼び出しごとに専用スレッド（`Thread`）で実行し、結果を `withCheckedContinuation` で返す。
   - 当初 `DispatchQueue`（並行キュー）で実装したが**不十分だった**。libdispatch の非 overcommit ワーカープールもコア数で頭打ちになるため、全件実行で `ViewerWindowManagerRecentRepositoriesTests` の 6 テストが待機上限に達した（STRICT=1 は通るのに通常実行が落ちる、という形で表面化）。専用スレッド方式に変えて解消。
2. 本番コードの `Task.detached` **21 箇所すべて**を `withBlockingWork` へ置換。サブエージェントによる棚卸しで、21 箇所は全て git サブプロセス起動 / ファイル I/O / AppleScript 実行のいずれかで、純 CPU 処理は 1 つも無いことを確認したため、選別せず一律に置き換えた。
3. テスト側の `Task.detached` 3 箇所（GitCommandFileIndexConcurrencyTests）も同様に置換。
4. 破れない担保を 2 つ用意した。
   - `scripts/check-no-detached-blocking.sh`（`--self-test` 付き）が Swift の `Task.detached` を機械的に弾く。pre-commit（setup-git-hooks.sh）と CI（type-group-size ジョブ）の両方で実行。
   - CI の build-and-test に `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` での全件実行を追加。1 本でも協調スレッドを塞げば決定的に落ちる。
   - `BefoldApp/befoldTests/BlockingWorkTests.swift`: コア数 × 4 を同時に塞いでも全呼び出しが開始されることを固定。実装を `Task.detached` へ戻すと 32 issues で落ちることを実測で確認済み。
5. `docs/dev/native-app-design.md` のアーキテクチャ節に「MainActor の外へ逃がす処理は withBlockingWork を通す」を追記。

## 検証（すべて手元実測）

| 実行 | 結果 |
| --- | --- |
| `swift build` | エラー・警告ゼロ |
| `swift test`（通常） | 1649 tests / 264 suites passed（36.4 秒） |
| `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 swift test` × 3 | すべて passed（40.3 / 39.4 / 41.9 秒） |
| `swift test --sanitize=thread` × 4 | 3 回 passed（126〜144 秒）。1 回のみ **別件**でクラッシュ（下記） |
| swiftlint（main とのベースライン差分） | 真の新規ゼロ・解消ゼロ・生 diff もゼロ |
| swiftformat --lint | 差分なし |
| markdownlint-cli2 | 0 issues |

TSan 4 回中 1 回の失敗は本件と無関係だった。テストは全 pass のまま AppKit 内部（`-[NSMenu dealloc]` → `NSPointerArray removePointerAtIndex:` 範囲外）で abort したもので、«unknown» issue は出ていない。TASK-525 として別途起票した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
同期ブロックが Swift 並行の協調スレッドプールを塞ぎ、解放に必要な別タスクの前進が止まっていた。LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 で決定的に再現し、同型が 3 スイートにあることを確認。同型 3 度目（TASK-424 / 427 / 516）のため個別の手当てではなく置き場を変え、専用スレッドで実行する withBlockingWork を BefoldKit に新設して本番 21 箇所・テスト 3 箇所の Task.detached を全廃した。担保は scripts/check-no-detached-blocking.sh（pre-commit + CI）、CI の STRICT=1 全件実行、BlockingWorkTests の 3 本立て。検証: 通常テスト 1649 件 pass、STRICT=1 で 3 回 pass、TSan 4 回中 3 回 pass（残り 1 回は AppKit の NSMenu dealloc クラッシュで別件・TASK-525 起票）、swiftlint ベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
