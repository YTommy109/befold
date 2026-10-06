---
id: TASK-670
title: worktree-reset の完了判定が、後続 PR が同じファイルを触ると squash merge 済みでも未マージと誤判定する
status: To Do
assignee: []
created_date: '2026-10-06 01:20'
labels:
  - chore
dependencies: []
references:
  - scripts/worktree-reset.sh
ordinal: 855000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
scripts/worktree-reset.sh は squash merge 済みかを「旧ブランチが変更したファイルがすべて origin/main の現在の内容と一致するか」で判定する。このため、PR #703 のマージ後に別の PR #708 が同じファイル（BefoldApp/befoldTests/ViewerBridgeContractTests.swift）を変更すると、ブランチ側に失う作業が無くても「未マージです」で止まる（2026-10-06 に実測。実際は #703 が MERGED で、差分は main が先に進んだ分だけだった）。--force を付ければ進めるが、--force は本当に未マージの作業も捨てるため、誤判定のたびに人が git log と diff で確かめ直す必要がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 旧ブランチの全コミットが squash 済みの PR に含まれるとき（後続 PR が同じファイルを変更していても）、--force なしで切り直せる
- [ ] #2 本当に未マージのコミットが残っているブランチは従来どおり --force なしで中断する
- [ ] #3 上の 2 ケースをスクリプトのテストまたは再現手順で確認している
<!-- AC:END -->
