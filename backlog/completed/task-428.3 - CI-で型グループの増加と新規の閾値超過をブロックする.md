---
id: TASK-428.3
title: CI で型グループの増加と新規の閾値超過をブロックする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 12:34'
updated_date: '2026-08-11 04:54'
labels: []
dependencies: []
parent_task_id: TASK-428
priority: medium
type: chore
ordinal: 104300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ラチェット判定を CI のステップとして追加し、PR 単位で確実にブロックする。手元では警告どまり（TASK-428.2）、外に出る手前で止める、という段階分けの後段。

## 配線先

`.github/workflows/ci.yml`。現状このワークフローには行数チェックに相当するステップが無い。既存ステップは `swift build`（98-99 行、SwiftLint はビルドツールプラグインとして走る）/ `swift package plugin ... swiftformat -- --lint`（101-102 行）/ `swift test`（104-105 行）。SwiftLint を strict で回すステップは無い。

## 決めること

- **どのジョブに置くか**: swiftformat の lint と同列（macOS ランナー、ビルド後）に置くか、Swift のビルドを待たない軽量な独立ジョブにするか。集計はファイルを読むだけなのでビルド不要であり、独立ジョブなら失敗が早く返る。
- **TASK-425 で入れた paths フィルタとの整合**: backlog のみの push で macOS CI が再実行されないようにする条件が既にある。行数チェックは Swift ファイルの変更でのみ意味を持つ点を踏まえて、どのトリガ条件に載せるかを決める。

## 注意

CI をブロックにする前に、その時点のベースラインが最新であること（`main` で判定を回して緑になること）を確認すること。ベースラインが古いまま有効化すると、無関係な PR が全部落ちる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CI に型グループのラチェット判定ステップが追加されている
- [x] #2 ベースラインを超えて増加した型グループがある PR で CI が失敗する
- [x] #3 新規の型グループが閾値を超えている PR で CI が失敗する
- [x] #4 有効化時点の main でこの判定が緑であることを確認した記録が Implementation Notes にある
- [x] #5 失敗時のログから、どのグループが何行増えたかと対処方法（責務分割 / ベースライン更新）が読み取れる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ubuntu の独立ジョブ type-group-size を ci.yml へ追加する（self-test + --check）
2. on.paths と changes ジョブの grep へ スクリプト/ベースラインのパスを追加する
3. 終了コード 2（減少）はブロックせず ::warning:: に落とす
4. 増加・新規超過・減少・現行の 4 ケースで CI ステップ本体の終了コードを実測する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決定事項（TASK-428.3）

- **macOS の build-and-test とは別の ubuntu 独立ジョブにした**。集計はファイルを読むだけでビルドが不要なので、Xcode のセットアップと SPM ビルド（通常 4 分）を待たせる理由がない。失敗が数十秒で返る。
- **トリガは TASK-425 の paths フィルタへ相乗り**。on.paths と changes ジョブの grep の両方へ scripts/check-type-group-size.sh と scripts/type-group-baseline.txt を追加した（ci.yml のコメントが「片方だけ変えるとテストが黙って走らなくなる」と警告している箇所）。判定ロジックやベースライン自体を壊す変更が CI を素通りするのを防ぐ。
- **終了コード 2（減少 = ベースラインが古い）は CI でもブロックしない**。::warning:: を出すだけ。TASK-428.2 で決めた方針と揃える。
- **CI ステップの終了コード伝播は `|| status=$?` の形で書いた**。`if cmd; then exit 0; fi; status=$?` は `fi` を跨いだ時点で $? が当てにならず、実測で減少ケースが 1 になった（本来 2）。書き方を直して 4 ケースとも期待どおりになることを確認済み。
- **self-test を CI の別ステップとして先に回す**。判定が壊れた状態でグリーンになるのを防ぐ。GNU mktemp が `-t 名前` に XXXXXX を要求するため、テンプレートを明示する形へ直した（ubuntu で走らせるための修正）。

## 有効化時点で main が緑であることの確認（AC #4）

- `git diff --stat origin/main -- 'BefoldApp/**/*.swift'` の出力が 0 行。本ブランチは Swift ファイルを一切変更していないため、集計結果は origin/main と同一。
- その状態で `scripts/check-type-group-size.sh --check` が終了コード 0（「型グループの行数はベースライン以内です」）。ベースラインは同ブランチで origin/main の実測値から生成したもの。

## CI ステップ本体の実測（AC #2 / #3 / #5）

ci.yml の run 本体をそのままローカルで実行した結果:

| ケース | ベースライン | 終了コード |
|---|---|---|
| 増加 | ViewerStore を 100 行と偽装 | 1 |
| 新規の閾値超過 | 数値行なし（空） | 1 |
| 減少 | 全 12 グループを +50 行 | 0（::warning::） |
| 現行 | リポジトリのベースライン | 0 |

失敗時のログには『増加: BefoldApp/befold/Viewer/ViewerStore が 100 行 → 492 行（+392）』のようにグループ名・前後の行数・差分が出る。加えて対処方法（責務を分けて別の型へ切り出す / 意図的な場合は --update-baseline）が本文として表示される。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ci.yml へ ubuntu の独立ジョブ type-group-size を追加し、self-test と --check をブロックとして回すようにした。on.paths と changes ジョブの grep にもスクリプト/ベースラインのパスを足し、判定側を壊す変更が CI を素通りしないようにした。

検証: CI ステップの run 本体をそのままローカルで実行し、増加=1 / 新規の閾値超過=1 / 減少=0（::warning::）/ 現行=0 の 4 ケースを実測。actionlint も OK。有効化時点で main が緑であることは、本ブランチが Swift を一切変更していない（git diff --stat origin/main -- '*.swift' が 0 行）状態で --check が終了コード 0 になることで確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
