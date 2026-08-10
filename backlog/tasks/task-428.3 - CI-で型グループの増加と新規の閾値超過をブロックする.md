---
id: TASK-428.3
title: CI で型グループの増加と新規の閾値超過をブロックする
status: To Do
assignee: []
created_date: '2026-08-10 12:34'
labels: []
dependencies: []
parent_task_id: TASK-428
priority: medium
type: chore
ordinal: 670000
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
- [ ] #1 CI に型グループのラチェット判定ステップが追加されている
- [ ] #2 ベースラインを超えて増加した型グループがある PR で CI が失敗する
- [ ] #3 新規の型グループが閾値を超えている PR で CI が失敗する
- [ ] #4 有効化時点の main でこの判定が緑であることを確認した記録が Implementation Notes にある
- [ ] #5 失敗時のログから、どのグループが何行増えたかと対処方法（責務分割 / ベースライン更新）が読み取れる
<!-- AC:END -->
