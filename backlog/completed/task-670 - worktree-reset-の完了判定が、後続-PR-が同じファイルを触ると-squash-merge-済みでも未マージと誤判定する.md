---
id: TASK-670
title: worktree-reset の完了判定が、後続 PR が同じファイルを触ると squash merge 済みでも未マージと誤判定する
status: Done
assignee:
  - '@claude'
created_date: '2026-10-06 01:20'
updated_date: '2026-10-06 01:40'
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
- [x] #1 旧ブランチの全コミットが squash 済みの PR に含まれるとき（後続 PR が同じファイルを変更していても）、--force なしで切り直せる
- [x] #2 本当に未マージのコミットが残っているブランチは従来どおり --force なしで中断する
- [x] #3 上の 2 ケースをスクリプトのテストまたは再現手順で確認している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 完了判定に「旧ブランチの先端 SHA が、GitHub 上でマージ済みの同名ブランチの PR の headRefOid と一致する」を最初の梯子として足す（gh pr list --head <branch> --state merged）。先端が PR head と同一なら、PR に含まれない作業は無い。後続 PR が同じファイルを変更しても影響されない（根拠: PR #703 の headRefOid = 旧ブランチ先端 50abd503 を 2026-10-06 に実測）
2. gh が無い・--no-fetch（オフライン）・SHA 不一致の場合は従来のファイル内容照合へ落ちる。TASK-528 の「squash 後に未プッシュコミットを積んだブランチ」は SHA が不一致になるため、従来どおり保護される
3. worktree-reset.sh --self-test を足す（check-*.sh の慣習）。一時の bare origin + linked worktree + 偽 gh で (a) squash 済み + 後続 PR が同ファイルを変更 + SHA 一致 → --force なしで切り直せる (b) SHA 不一致（未プッシュコミットあり）→ 未マージで中断 を検証する
4. ci.yml の self-test 群へ組み込む
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証（2026-10-06）: scripts/worktree-reset.sh --self-test（一時 bare origin + linked worktree + 偽 gh で本スクリプトを実行）。(a) squash 済み + 後続 PR が同じ f.txt を変更 + 先端 = PR head → --force なしで切り直せる。(b) squash 後に未プッシュコミットを積み先端 != PR head → 未マージで中断。判定の gh 梯子を外したコピーでは (a) が本件と同じ「ブランチ feature は未マージです」で落ちることを確認（修正を戻して落ちる）。前提の実測: PR #703 の headRefOid = 旧ブランチ先端 50abd503。CI: ci.yml の on.paths 2 か所と changes のフィルタへ scripts/worktree-reset.sh を足し、self-test の step を追加（actionlint 通過）。未確認: 実 GitHub 上での gh pr list --head の挙動は、先端一致の実測（上記 PR #703）までで、スクリプト経由の通し実行は次に切り直すときに初めて確かめられる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
worktree-reset の完了判定に「先端 SHA がマージ済み PR の headRefOid と一致」を最初の梯子として追加し、後続 PR が同じファイルを変更しても squash 済みブランチを誤って未マージと判定しないようにした。gh が無い・--no-fetch・不一致は従来のファイル内容照合へ落ちるため、TASK-528 の保護は維持。--self-test（偽 gh）で 2 ケースを検証し、CI に組み込んだ。
<!-- SECTION:FINAL_SUMMARY:END -->
