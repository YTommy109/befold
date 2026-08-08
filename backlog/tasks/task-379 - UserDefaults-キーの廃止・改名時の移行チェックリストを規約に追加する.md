---
id: TASK-379
title: UserDefaults キーの廃止・改名時の移行チェックリストを規約に追加する
status: To Do
assignee: []
created_date: '2026-08-08 11:49'
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
- [ ] #1 .claude/CLAUDE.md に UserDefaults キー廃止・改名時のチェックリストが記載されている
- [ ] #2 チェックリストが TASK-372 の型（読み手を失ったキーの放置）を検知できる内容になっている
<!-- AC:END -->
