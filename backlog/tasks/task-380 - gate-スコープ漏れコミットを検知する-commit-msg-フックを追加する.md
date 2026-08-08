---
id: TASK-380
title: (gate) スコープ漏れコミットを検知する commit-msg フックを追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 11:49'
updated_date: '2026-08-08 13:03'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 640000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) の振り返りから。(gate) スコープ規約は .claude/CLAUDE.md に明文化済み（過去に grep 見逃しで stable リリースノートへ混入した実例も記載済み）だが、dacb72e で再び漏れた（TASK-375）。明文化は 2 回目の対処として数えない、の原則どおり機械的に強制する。

内容: commit-msg（または pre-commit）フックで、ステージされた差分が FeatureGate 配下のコード（`FeatureGate` への参照を含む行の追加・変更、および FeatureGate.swift 由来の別名ゲート computed property の参照）に触れているのに件名に `(gate)` スコープが無い場合に警告またはブロックする。混在コミット（ゲート内外を両方触る）の扱い方針もフックのメッセージで案内する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 FeatureGate 関連の差分を含み件名に (gate) が無いコミットがフックで検知される
- [x] #2 ゲートに触れないコミットは影響を受けない
- [x] #3 フックの導入方法（配置場所・有効化手順）がリポジトリ内に文書化されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. scripts/check-gate-commit-scope.sh を追加。commit-msg フック本体（$1 = メッセージファイル、$2 = ソース）。
   - 検知: ステージ済み .swift のうち Tests/ ・TestSupport/ 配下を除いたもので、追加/削除行に `FeatureGate.` を含む、または FeatureGate.swift 自体の変更
   - 件名（先頭の非コメント行）に (gate) が無ければ exit 1。混在コミットの分割案内と ALLOW_MISSING_GATE_SCOPE=1 の逃げ道をメッセージに出す
   - merge/fixup!/squash! はスキップ
2. scripts/setup-git-hooks.sh の install_hook が引数を転送するようにし（commit-msg は $1 が必須）、commit-msg フックを登録する
3. docs/dev/development.md に配置場所・有効化手順・検知範囲の限界（ゲート参照を含まない実装だけの差分は検知できない）を追記
4. 検証: 一時リポジトリで (a) ゲート差分+スコープ無し→ブロック (b) 同+(gate) →通過 (c) ゲート無関係の差分→通過 (d) テストのみの FeatureGate 参照→通過 を実測
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: scripts/check-gate-commit-scope.sh（commit-msg）。判定はステージ済み Swift のうち Tests/・TestSupport/ 配下を除いたもので、追加/削除行に FeatureGate. が現れる、または FeatureGate.swift 自体の変更。件名に (gate) が無ければ exit 1。merge/fixup!/squash!/amend!/Revert はスキップ、ALLOW_MISSING_GATE_SCOPE=1 で通過。混在コミットの扱い（ゲート側を別コミットへ分ける／分けられないなら全体を (gate) 扱い）をエラーメッセージで案内する。
setup-git-hooks.sh の install_hook がフック引数を転送するようにした（commit-msg は $1 のメッセージファイルが必須。引数を取らない既存フックでは空展開）。
検証: 一時リポジトリで 8 ケース全 PASS（ゲート差分+スコープ無し→ブロック / +(gate)→通過 / fixup!→通過 / env 逃げ道→通過 / 無関係な差分→通過 / テストのみのゲート参照→通過 / FeatureGate.swift 自体の変更→ブロック / ゲート参照の削除→ブロック）。回帰元 dacb72e の差分に同じ述語を当てると 7 ファイルで HIT し、当時も弾けていたことを確認。実リポジトリで FeatureGate 参照を含む一時ファイルを stage して git commit すると実際にブロックされることも確認（フックのラッパー経由の引数転送まで疎通）。markdownlint-cli2 は 0 issues。
限界（doc に明記）: ゲート参照を含まない実装だけの差分は検知できない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
commit-msg フック scripts/check-gate-commit-scope.sh を追加し、FeatureGate 配下のプロダクトコードに触れているのに件名へ (gate) スコープが無いコミットをブロックするようにした（テスト・TestSupport は除外、ALLOW_MISSING_GATE_SCOPE=1 で通過可）。setup-git-hooks.sh はフック引数を転送するようにして commit-msg を登録し、docs/dev/development.md にフック一覧・判定範囲・限界を文書化した。一時リポジトリでの 8 ケース全 PASS、回帰元 dacb72e への述語適用で HIT、実リポジトリでの git commit ブロックを実測。
<!-- SECTION:FINAL_SUMMARY:END -->
