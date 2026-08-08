---
id: TASK-375
title: dacb72e の (gate) スコープ漏れによる stable リリースノート混入を防ぐ
status: Done
assignee: []
created_date: '2026-08-08 11:23'
updated_date: '2026-08-08 13:31'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 636000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) 指摘。コミット dacb72e「feat: 表示モード切替を3セグメント＋レイアウトトグルにして cmd+1〜4 を割り当てる」は FeatureGate 配下のコード（diff セグメント、cmd+3 項目、cmd+4 レイアウト項目、gated な復元時降格）を変更しているが、件名に (gate) スコープが無い。/release-notes stable はコミット件名だけで機械的に除外判定するため、このままでは stable ビルドに存在しない cmd+3（差分）/ cmd+4（レイアウト）のショートカットがリリースノートに載る。

対応の選択肢: (a) 未 push またはマージ前なら gated 部分を (gate) スコープ付きコミットに分割 or 件名を非 gated の cmd+1〜2 に絞ってリワード、(b) それが不可なら次回 stable の /release-notes 生成時に手動除外し、その旨を記録する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 stable 向けリリースノートに cmd+3（差分）/ cmd+4（レイアウト）の記載が混入しない
- [x] #2 対応方法（コミット分割・リワード / リリースノート側での除外）を決めて実施した記録が残る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
対応方法: 選択肢 (a) のうち「コミット全体を (gate) 扱いにする reword」を採用（ユーザー承認済み）。

判断根拠:
- dacb72e はどのタグにも入っておらず main 未マージ（`git tag --contains dacb72e` が空、`git branch -r --contains` は origin/feat/preview_mode のみ）。main は merge commit 運用のため、マージ前に件名を直せば /release-notes stable の件名判定を通せる。
- 当該コミットはゲート内外の混在。stable でも見える部分がある（MainMenuBuilder.addDisplayModeItems による cmd+1 / cmd+2 のメニュー項目）。分割せず全体を (gate) にする方針は scripts/check-gate-commit-scope.sh:61-62 が定めた解（「分けられない場合はコミット全体を (gate) として扱い、ノートから漏れる方を防ぐ」）に合流させたもの。代償として cmd+1 / cmd+2 のメニュー項目追加も stable ノートに載らないが、これはフックが選んでいる安全側。
- リリースノート側に除外リストを持つ案（選択肢 b）は、判定経路を「件名だけ」から「件名＋別ファイル」に増やすため採らなかった。

実施内容:
- `git rebase -i` の reword で dacb72e の件名を `feat: …` → `feat(gate): …` に変更し、子孫 15 コミットを rebase（本文・差分は無変更）。新ハッシュは 0588d15。
- 検証: rebase 前後の HEAD ツリーが一致（いずれも 09173e109814e1478784c71cfdc6ca0de6127d3b）＝内容変更なし。
- `git push --force-with-lease origin feat/preview_mode` 済み（a545b98...23440be forced update）。
- PR #447 のタイトルも同じ件名へ更新（gh pr edit）。
- check-gate-commit-scope.sh と同じ判定を origin/main..HEAD の全コミットに手で適用し、残存するスコープ漏れが 0 件であることを確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
dacb72e の件名を feat(gate): へ reword し（新ハッシュ 0588d15）、force-push と PR #447 のタイトル更新まで実施。/release-notes stable は件名の (gate) だけで除外判定するため、cmd+3（差分）/ cmd+4（レイアウト）は stable ノートに載らない。rebase 前後の HEAD ツリー一致（09173e10）で内容無変更を確認し、check-gate-commit-scope.sh と同じ判定を origin/main..HEAD 全コミットへ適用してスコープ漏れ 0 件を確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
