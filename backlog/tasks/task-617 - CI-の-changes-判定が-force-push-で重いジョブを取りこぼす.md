---
id: TASK-617
title: CI の changes 判定が force-push で重いジョブを取りこぼす
status: Done
assignee:
  - '@claude'
created_date: '2026-09-12 12:23'
updated_date: '2026-09-12 12:56'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 807000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`.github/workflows/ci.yml` の `changes` ジョブは、PR への push で重いジョブ（`build-and-test` / `js-test` / `type-group-size`）を回すかどうかを `gh api repos/.../compare/${before}...${after}` の結果で決めている。この比較は**3 点比較**なので、force-push だと before と after のマージベース（＝書き換え前後で共通の祖先）からの差分になり、実際に PR が触っているファイルではなく「今回の書き換えで増減した分」しか見えない。

実測（2026-09-12、PR #654）: TASK-535 のブランチから別作業のコミット 1 つを `git rebase --onto` で落として force-push したところ、before(`2b20b5f1`) と after(`1d813060`) のマージベースが自分の直前のコミット `c0788d3a` になり、compare が返したのは backlog のタスクファイル 1 件だけだった。PR 全体では Swift 12 ファイルを変更しているのに `app=false` と判定され、`build-and-test` / `js-test` / `type-group-size` の 3 つが揃って skipping になった。PR を close→reopen して `action != synchronize` の分岐へ倒すことで回避したが、気づかなければ macOS のビルドとテストを通さないままマージできてしまう。

**既存の保険は効かない。** スクリプトには「差分を取得できなかったため(force-push 等)、すべてのジョブを走らせる」というフォールバックがあり、コメントも「判定できないときも走らせる側へ倒す」と書いている。しかし force-push でも compare API 自体は**成功する**ため、この分岐には入らない。想定していた失敗の形（API が落ちる）と、実際に起きる失敗の形（API が成功して誤った答えを返す）がずれている。

手当ての候補（着手時に選ぶ）:
- 3 点比較（`...`）を 2 点比較（`..`）に変える。ただし force-push 後は before がブランチから外れているため、2 点比較でも期待どおりになるか要確認
- force-push を検出して `app=true` へ倒す（`github.event.forced` が使える）
- そもそも push 単位の差分ではなく PR のベース（`github.event.pull_request.base.sha`）との差分で判定する。この場合 backlog だけを足した push でも毎回フルで回るため、ジョブ節約という当初の目的（ジョブ冒頭のコメントに記載）とのトレードオフになる
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PR のブランチへ force-push した後でも、その PR が BefoldApp 配下を変更している限り build-and-test / js-test / type-group-size が実行される
- [x] #2 判定方式を変えた理由と、3 点比較で取りこぼした実例がワークフロー内のコメントに残っている
- [x] #3 実際に force-push を行い、重いジョブが skipping にならないことを CI の実行結果で確認した記録が Implementation Notes にある
- [x] #4 backlog だけを触る push で重いジョブがスキップされる既存の振る舞いは維持されている（維持しない判断をした場合はその理由が記録されている）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. compare API のレスポンスから .status を読み、fast-forward('ahead')のときだけ差分ベースのスキップ判定を信用する
2. status が ahead 以外（force-push で diverged / behind になるケース）は app=true へ倒す
3. 3 点比較で取りこぼした実例（PR #654: 2b20b5f1...1d813060 が status=diverged / files=backlog 1 件）をコメントに残す
4. github.event.forced は push イベント専用で pull_request(synchronize) には無いことを確認済み。採らない理由もコメントに残す
5. 本ブランチで実際に force-push し、CI の changes ジョブが app=true になることを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
compare API の実測（2026-09-12）:
- force-push の実例 2b20b5f1...1d813060 は status=diverged / files=backlog 1 件（＝ 3 点比較が PR の変更を見落とす形）
- 通常 push aa50ba34...c9388d95 は status=ahead
- backlog のみの通常 push 03b19edb...c9388d95 は status=ahead / app=false（既存のスキップは維持）

github.event.forced は push イベントのペイロード専用で pull_request(synchronize) には無いため採らなかった（GitHub の webhook payload ドキュメントで確認）。2 点比較も force-push 後は「落としたコミットの差分」しか見えないため解決しない。

CI での live 検証（PR #657 / ブランチ wt/feature、2026-09-12）:
- backlog のみの通常 push（78dfa92f, run 34694434076）: changes が 'この push は BefoldApp を触っていないため、ビルドとテストをスキップする' を出力し、build-and-test / js-test / type-group-size が skipped。既存のスキップ挙動は維持されている（AC4）
- 上のコミットを amend して force-push（87da3422, run 34694470340）: changes が 'before が after の祖先ではない(status=diverged, force-push 等)ため、すべてのジョブを走らせる' を出力し、type-group-size / js-test / build-and-test が実行された。3 点比較の files は backlog 1 件だけなので、修正前ならこの push は app=false でスキップされていた形（AC1 / AC3）

採った方式: compare のレスポンスから .status を読み、fast-forward('ahead')のときだけ差分ベースのスキップを信用する。それ以外（diverged / behind / identical）は app=true。ワークフローのコメントに取りこぼしの実例（PR #654, 2b20b5f1...1d813060）と、github.event.forced を採らなかった理由を残した（AC2）。

force-push 後の run 34694470340 は全ジョブ green（changes 3s / type-group-size 7s / js-test 23s / build-and-test 11m14s、thread-sanitizer は nightly 専用で skip）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
changes ジョブの compare 結果を 3 点比較のまま使い続けると force-push でマージベースからの差分になり、PR が触っている BefoldApp の変更を見落として重いジョブが揃ってスキップされていた（compare API は成功するため既存のフォールバックも効かない）。compare のレスポンスから .status を読み、before が after の祖先である fast-forward('ahead')のときだけ差分ベースのスキップを信用する形に変更。実 API（PR #654 の 2b20b5f1...1d813060 が status=diverged）と CI の live 検証（run 34694434076 で backlog のみ push → skip 維持、run 34694470340 で force-push → status=diverged で全ジョブ実行・全緑）で確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
