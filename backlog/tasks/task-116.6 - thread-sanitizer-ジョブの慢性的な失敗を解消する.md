---
id: TASK-116.6
title: thread-sanitizer ジョブの慢性的な失敗を解消する
status: In Progress
assignee:
  - '@claude'
created_date: '2026-07-23 23:19'
updated_date: '2026-07-24 00:31'
labels:
  - test
  - ci
dependencies:
  - TASK-116.5
parent_task_id: TASK-116
priority: medium
ordinal: 30600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
thread-sanitizer ジョブが main push / nightly でほぼ毎回失敗しており、常時赤のためシグナルとして機能していない。

## 実測

直近の CI 失敗 8 件のうち 7 件が thread-sanitizer ジョブ(残り 1 件は build-and-test)。原因は毎回同一:

```
✘ Test deletingWatchedFileFiresOnFileGone() recorded an issue at
  ViewerStoreIntegrationTests.swift:20:6: Time limit was exceeded: 60.000 seconds
✘ Test run with 590 tests in 74 suites failed after 74.287 seconds with 1 issue
```

同じ run で `truncatedScript は failed=true を渡せる` という純粋ロジックのテストが 61 秒かかって pass しており、TSan 下で並列実行が極端に不均衡になっている(スイート全体は 74 秒で終わる)。単純なタイムアウト値の引き上げではなく、TSan 下で当該テストが何を待っているのかを先に切り分けること。

## 経緯

TASK-11(Done)で同種の TSan 失敗を `BEFOLD_TEST_TIMEOUT_SECONDS` の尊重漏れ修正により解消した実績がある。今回は別のテストでの再発であり、ワークフロー側は既に thread-sanitizer ジョブに `BEFOLD_TEST_TIMEOUT_SECONDS: 120` を設定済み(`.github/workflows/ci.yml`)。それでも `.timeLimit(.minutes(1))` の 60 秒上限に先に当たっているため、環境変数だけでは解決しない構造になっている点に注意。

## 判断してほしいこと

TSan を回し続ける価値があるか。常時赤を放置するくらいなら、対象テストを TSan 実行から除外して残りを緑に保つ方がシグナルとして有用な可能性がある。実装前にこの選択を明示的に検討し、判断理由を記録すること。

## 依存

TASK-116.5(ポーリングヘルパーの silent timeout 撲滅)を先に済ませると、TSan 下で「何が待たれているか」が失敗メッセージから直接分かるようになるため、切り分けが容易になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 thread-sanitizer ジョブが main push / nightly で安定して結果を返す(常時赤ではない)
- [x] #2 deletingWatchedFileFiresOnFileGone が TSan 下で時間超過しない、または対象から意図的に除外され理由が記録されている
- [x] #3 TSan を継続する/縮小する の判断理由がタスクに記録されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査結果(切り分け):

1. ローカル TSan は失敗を再現しない。BEFOLD_TEST_TIMEOUT_SECONDS=120 swift test --sanitize=thread が 593 tests / 77 suites を 37.968 秒で pass、データ競合の検出もゼロ。TASK-11 の実装ノートにある「ローカルでは TSan の実スローダウンが再現できない」と同じ状況。

2. タスク記載の「原因は毎回同じ 1 本」は不正確だった。CI ログを精査すると失敗テストは 2 本が交代で出ている:
   - deletingWatchedFileFiresOnFileGone (ViewerStoreIntegrationTests.swift:20)
   - detectsAtomicSave (FileWatcherIntegrationTests.swift:62)
   どちらも実 FS + 実 FileWatcher の直列スイートで、失敗理由は共通して Time limit was exceeded: 60.000 seconds。

3. 常時赤でもなかった。直近の push/schedule 17 件の thread-sanitizer ジョブは failure 10 / success 5 / cancelled 2 で、約 3 分の 2 の確率で落ちるフレーキー。

4. 根本原因(設定の矛盾): CI の thread-sanitizer ジョブは BEFOLD_TEST_TIMEOUT_SECONDS: 120 でポーリング予算を 120 秒へ延長しているのに、対象スイートは .timeLimit(.minutes(1)) = 60 秒のまま。延長した予算を使い切る前にテストが打ち切られるため、TSan のスローダウン下で 60 秒を超えた待機は必ず失敗する。CI の失敗メッセージ Time limit was exceeded: 60.000 seconds はこの打ち切りそのもの。TASK-11 で予算側だけを環境変数に追随させ、打ち切り側を追随させ忘れたのがドリフトの発端。

対応: BefoldTestSupport に testTimeLimit(pollingBudgetFallback:) を追加し、.timeLimit を同じ環境変数から導出するようにした(予算の 2 倍を分単位に切り上げ)。これにより CI 側で予算を変えても打ち切りが自動的に追随し、同じドリフトが再発しない。実測値: ローカル既定(15秒予算)→ 1 分、build-and-test(30秒)→ 1 分(いずれも従来と同じ)、thread-sanitizer(120秒)→ 4 分(従来 60 秒)。非 TSan 環境の挙動は変わらない。

AC#3(TSan を継続するか)の判断: 継続する。理由は (a) 失敗は 100% ではなく約 2/3 で、データ競合そのものを検出できていないわけではない(今回のローカル実行でも競合ゼロを確認できている) (b) 赤の原因が「競合検出」ではなく「打ち切り設定の矛盾」と特定でき、修正可能だったため、ジョブ自体を捨てる理由がない (c) TASK-116.5 により、待機が本当に成立しない場合は打ち切りではなく「どのヘルパーが何秒で条件を満たさなかったか」という具体的な失敗として報告されるようになり、今後は切り分けが容易になる。

検証: 修正後に BEFOLD_TEST_TIMEOUT_SECONDS=120 swift test --sanitize=thread を再実行し、593 tests / 77 suites が 34.365 秒で pass。通常の swift test も 593 tests が 15.212 秒で pass。

AC#1(CI で安定して結果を返す)は未チェック。ローカルでは元の失敗を再現できないため、main へマージ後の push トリガーと nightly(15:00 UTC)の thread-sanitizer ジョブを複数回観測して確認する必要がある。
<!-- SECTION:NOTES:END -->
