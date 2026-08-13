---
id: TASK-438.3
title: ADR の Fallback 節を確定させ、ADR 番号の衝突を解消する
status: To Do
assignee: []
created_date: '2026-08-13 14:00'
labels:
  - docs
dependencies:
  - TASK-438.1
  - TASK-438.2
parent_task_id: TASK-438
priority: medium
ordinal: 101300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-438 の決定を ADR へ反映し、あわせて番号の衝突を直す。実装（438.1 / 438.2）の結果を書くため最後に行う。

## 1. Fallback 節の確定

現在の記述は伝え方を「実装時に決める」と未決のまま残している（docs/adr/0005-git-integration-via-libgit2.md:205-207）。これを確定した記述へ更新する。

- 伝えるのは BaseDirectoryIndicator の 1 箇所のみ。バナー・注記行・モーダルは取らない
- 失敗理由の種別は出さない（OpenFailure が .unusable の 1 値へ畳んでいるため、出すと型が持たない情報を騙る）
- .git の読み取り権限なしは .notARepository へ落ちるため「git 管理外」と区別できない（同 ADR の 2026-08-11 実測追記と整合させる）

## 2. ADR 0003 への誤った参照を正す

同 ADR:207 は「ADR 0003 の Context にある「原因不明の無反応」」を参照しているが、**docs/adr/0003-git-status-guard-in-file-list-model.md にこの語句は存在しない**（grep -rn '原因不明' docs/ backlog/ の一致はこの 1 行とその引用のみ）。ADR 0003 の Context が述べているのは、反映可否の判定が 3 状態に分散して順序回帰が 5 回続いたという内部設計の話で、ユーザーへの伝え方は扱っていない。引用の体裁をやめ、参照するなら何を指しているのかを自分の言葉で書く。

## 3. 番号の衝突を解消する

0005 が 2 本ある。

- docs/adr/0005-bundle-viewer-js-with-esbuild.md（backlog decision-5）→ 0005 のまま
- docs/adr/0005-git-integration-via-libgit2.md（backlog decision-6）→ **0006 へ振り直す**

decision 番号に合わせる。参照している箇所を追随させること（backlog タスク・他 ADR・docs 配下・CLAUDE.md 等）。参照元は rg で全列挙してから直す。

## 注意

Markdown を編集したら markdownlint-cli2 を流す。ドキュメント間の依存はディレクティブコメント（constrained-by / derived-from 等）で表す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fallback 節が「実装時に決める」から確定した記述へ更新され、実装（438.1 / 438.2）の結果と一致している
- [ ] #2 ADR 0003 への誤った参照が正されている
- [ ] #3 libgit2 の ADR が 0006 へ振り直され、0005 の重複が解消している
- [ ] #4 振り直しに伴う参照箇所がすべて追随している（rg で旧ファイル名・旧番号の残存がゼロ）
- [ ] #5 markdownlint-cli2 が通る
<!-- AC:END -->
