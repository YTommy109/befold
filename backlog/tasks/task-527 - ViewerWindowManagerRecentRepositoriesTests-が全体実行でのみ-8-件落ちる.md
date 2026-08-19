---
id: TASK-527
title: ViewerWindowManagerRecentRepositoriesTests が全体実行でのみ 8 件落ちる
status: Done
assignee: []
created_date: '2026-08-19 04:25'
updated_date: '2026-08-19 04:46'
labels:
  - bug
dependencies: []
priority: medium
ordinal: 769000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 事象

`swift test --skip Integration --skip FileWatcherTests` の全体実行で ViewerWindowManagerRecentRepositoriesTests の 8 件が落ちる。単体実行(`--filter ViewerWindowManagerRecentRepositoriesTests`)では 8 件とも pass する。

## 実測(2026-08-19、TASK-526 の作業中)

- 作業ツリー: 1548 tests / 14 issues、失敗はすべて ViewerWindowManagerRecentRepositoriesTests
- origin/main を `git archive` で別ディレクトリへ展開した pristine ツリー: 1540 tests / 14 issues、**同じ 8 件**が同じように落ちる → TASK-526 の変更とは無関係な既存の問題
- 単体実行: 8 tests pass(1.4 秒)。全体実行では各テストが 18〜25 秒かかっており、並列実行下でのみ壊れる

失敗の形は `fixture.store.entries()` が空・`controller.repositoryRoot` が nil で、リポジトリルート解決が着地しないまま判定している疑い。

## 着手条件

TASK-526 の作業では原因調査まで行っていない。実測ログは $CLAUDE_JOB_DIR に残っていないため、再現から取り直す必要がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 全体実行でも 8 件が安定して pass する
- [x] #2 落ちていた原因(タイムアウト・共有状態・並列度のいずれか)を実測で特定し Notes に残す
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 原因(実測)

全体実行を 4 回回して 2 回再現。失敗はすべて同型で、**ポーリング待機の 10 秒予算切れ**。

```
✘ waitUntilOnMainActor が 10.0 seconds 以内に条件を満たさなかった (:140 :160 :189 :205 :228 :247)
✘ waitUntil が 10.0 seconds 以内に条件を満たさなかった            (:177 :284)
```

予算切れの後は `entries() == []` / `repositoryRoot == nil` が続くだけで、これらは
待機失敗の派生。共有状態でも並列度でもない。

待っていたのは「解決にかかる時間」ではなく**メインアクターの順番待ち**である。
記録は `RecentRepositoryRecorder.recordIfNeeded` が MainActor 上で起こす `Task` から
始まる(解決自体は `withBlockingWork` の専用スレッドなので協調プールの飢餓ではない)。
全体実行では 241 スイートの多くが `@MainActor` でメインアクターを直列に占有するため、
Task が走り出すまでに 10 秒を超える。単体実行で 1.4 秒なのはこのためで、
BefoldTestSupport/Waiting.swift が TASK-335 / TASK-354 で既に文書化している型と同じ。

## 対応

同ファイルの反映待ちを**壁時計予算を持たない待機**へ統一した。

- `openAndAwaitRecording`: `waitUntilOnMainActor` → `waitForDeliveryOnMainActor`
- `waitUntil` 2 箇所 → `waitForMainActorDelivery`
- スイートへ `testTimeLimit()` を付与(戻らない回帰の打ち切りはこちらが担う)
- `switchingFileBeforeResolutionLandsRecordsNothing` の固定 `sleep(100ms)` を撤去。
  混雑時に「まだ着地していないだけ」の空を成功と誤認するため、堰き止めない
  対照ファイル(/repoB/c.md)の記録が着地したことをバリアにし、判定も
  `entries().isEmpty` から `entries() == [/repoB]` へ強めた。

## 検証(実測)

- 修正前: 全体実行 4 回中 2 回赤(8 件すべて)
- 修正後: 全体実行 6 回すべて緑(1548 tests、27.9〜29.0 秒)
- 回帰を捕まえることの確認: `RecentRepositoryRecorder.apply` へ到達しないよう
  ガードを壊して `--filter` 実行 → 8 件中 7 件が赤(BEFOLD_TEST_TIME_LIMIT_MINUTES=1 で
  `.timeLimit` が打ち切って報告)。残る 1 件は「記録されない」ことを見るテストで、
  緑のままが正しい。
- swiftlint: 変更ファイルの指摘は既存の type_name 1 件のみで増減なし
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
全体実行でのみ落ちていたのは 10 秒のポーリング予算切れで、待っていたのは解決時間ではなくメインアクターの順番待ちだった。反映待ちを予算なしの waitForDeliveryOnMainActor / waitForMainActorDelivery へ統一し、スイートへ testTimeLimit() を付与。切替テストの固定 sleep も対照ファイルによるバリアへ置き換えた。全体実行 6 回連続で緑(修正前は 4 回中 2 回赤)、実装を壊すと 7 件が赤になることも確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
