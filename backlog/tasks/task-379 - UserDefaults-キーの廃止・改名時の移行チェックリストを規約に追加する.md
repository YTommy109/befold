---
id: TASK-379
title: UserDefaults キーの廃止・改名時の移行チェックリストを規約に追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 11:49'
updated_date: '2026-08-08 13:26'
labels: []
dependencies: []
priority: low
type: docs
ordinal: 639000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) の振り返りから。TASK-372（app-global の SourceDiffEnabled キーが読み手を失ったまま放置され、diff ON 状態が移行されない）は「キーを廃止・改名するときは移行と stale キー削除を必ず対にする」という短い規約があれば設計段階で気づけた型。

.claude/CLAUDE.md に永続化変更のチェックリストを追加する。最低限:
- キーの廃止・改名時は、旧値の移行（意味を保って新形式へ写す）か、移行しないという明示的判断を必ず記録する
- 旧キーは removeObject で削除し defaults に残さない
- 移行ロジックはユニットテストで担保する（旧値あり / なし / 移行済みの 3 ケース）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 .claude/CLAUDE.md に UserDefaults キー廃止・改名時のチェックリストが記載されている
- [x] #2 チェックリストが TASK-372 の型（読み手を失ったキーの放置）を検知できる内容になっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. .claude/CLAUDE.md の「完了基準」の直前に「UserDefaults キーの廃止・改名」節を追加する
2. 検知条件（読み手を失ったキーを残さない）・移行 or 非移行の明示的判断・stale キー削除・3 ケースのユニットテストを列挙する
3. TASK-372 を根拠として実測付きで示す
4. markdownlint-cli2 と scripts/check-doc-symbols.sh を通す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: .claude/CLAUDE.md に「UserDefaults キーの廃止・改名」節を「完了基準」の直前へ追加。旧キーの読み手を rg で数えて 0 なら移行可否を明示的に決める / 移行経路は既存の一度きり移行へ合流させる / removeObject を defer に置き早期 return 経路でも消す / 旧値あり・なし・移行済みの 3 ケースを makeIsolatedDefaults(prefix:) 上のユニットテストで担保する、を列挙。参考実装として DisplayModeStore.migrateLegacySourceModesIfNeeded を挙げ、TASK-372 の実測を根拠として付記した。
検証: scripts/check-doc-symbols.sh rc=0（引用シンボル実在）、markdownlint-cli2 で 66 ファイル 0 issues。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
.claude/CLAUDE.md に UserDefaults キー廃止・改名時のチェックリストを追加した（AC#1）。チェックリストの先頭項目が「新キーを足したら旧キーリテラルを rg で数え、読み手が 0 になったキーは移行するかしないかを明示的に決める」であり、TASK-372 の型（読み手を失った app-global キーが移行も削除もされず放置される）を設計段階で検知できる。あわせて stale キー削除を defer に置くこと、旧値あり/なし/移行済みの 3 ケースをテストすることを必須化し、TASK-372 の実測を根拠として明示した（AC#2）。scripts/check-doc-symbols.sh rc=0、markdownlint-cli2 0 issues で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
