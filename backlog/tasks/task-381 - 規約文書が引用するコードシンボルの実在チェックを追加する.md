---
id: TASK-381
title: 規約文書が引用するコードシンボルの実在チェックを追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 11:50'
updated_date: '2026-08-08 13:10'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 641000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) の振り返りから。.claude/CLAUDE.md が模範例として引用した `BookmarkShortcut.keyEquivalent(isSourceDiffEnabled:)` は、同ブランチの先行コミットで削除済みの関数だった（TASK-374）。文書がコードを名指しする限り同型の陳腐化は再発するため、引用シンボルの実在を機械的に検査する。

内容: .claude/CLAUDE.md（必要なら docs/ の ADR も対象に含めるか判断）内のバッククォート引用からシンボル名（関数・プロパティ・型名）を抽出し、リポジトリ内に宣言が存在するかを rg で確認するスクリプトを scripts/ に置き、CI または pre-commit で実行する。誤検知（コマンド名・ファイルパス・一般語）の除外方法を含めて設計する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 TASK-374 の型（削除済みシンボルを引用し続ける文書）がチェックで検知される
- [x] #2 誤検知の除外手段があり、既存文書に対してチェックがグリーンで通る
- [x] #3 CI または pre-commit に組み込まれている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLAUDE.md 内のバッククォート引用から 型.メンバ 形式だけを抽出する検査スクリプトを scripts/ に追加する
2. 誤検知対策: 抽出条件を 型.メンバ に限定し、ファイル名形式(.swift 等)を除外、除外リストを scripts/doc-symbol-allowlist.txt に置く
3. 検知能力が腐らないよう、既定実行に self-test(削除済みシンボルを検知/実在シンボルは通過)を組み込む
4. pre-commit フック(scripts/setup-git-hooks.sh)へ組み込む
5. 検知で見つかった実際の陳腐化(BookmarkShortcut.keyEquivalent の引用)を文書側で修正する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検査範囲は CLAUDE.md 系(リポジトリ直下 + .claude/)に限定した。docs/ の ADR は「その時点の判断の記録」であり、当時実在したシンボル名が残るのは陳腐化ではないため対象外とした（必要になれば引数で個別に検査できる）。

CI ではなく pre-commit を選んだ理由: .github/workflows/ci.yml のトリガは paths: BefoldApp/** に限定されており、CLAUDE.md やコード削除を含むコミットで確実に走らせるには pre-commit が適する。

実測:
- ./scripts/check-doc-symbols.sh --self-test → OK（BookmarkShortcut.keyEquivalent(isSourceDiffEnabled:) を検知、ModeSegments.modes(isSourceDiffEnabled:) は通過）
- 既存文書に対して実行 → 陳腐化 1 件を検知（.claude/CLAUDE.md:238、TASK-374 で削除済み）。文書を修正後グリーン
- CLAUDE.md へ壊れた引用を追記して再実行 → CLAUDE.md:53 で検知、exit=1
- 実行時間 0.1 秒未満
- markdownlint-cli2 → 0 issues
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
scripts/check-doc-symbols.sh を追加し、CLAUDE.md 系が名指しする 型.メンバ 形式のシンボルの実在（引数ラベル含む）を検査する。誤検知は抽出条件の限定・ファイル名形式の除外・scripts/doc-symbol-allowlist.txt で抑え、既定実行に self-test を組み込んで検知能力の腐敗を防ぐ。pre-commit フックへ組み込み済み。検査で見つかった実際の陳腐化（TASK-374 で削除された BookmarkShortcut.keyEquivalent(isSourceDiffEnabled:) の引用）を .claude/CLAUDE.md から除去した。検証: --self-test OK、既存文書グリーン、壊れた引用の追記で exit=1 を確認、markdownlint 0 issues。
<!-- SECTION:FINAL_SUMMARY:END -->
