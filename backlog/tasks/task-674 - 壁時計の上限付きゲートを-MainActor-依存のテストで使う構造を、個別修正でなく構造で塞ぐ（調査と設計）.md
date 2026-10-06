---
id: TASK-674
title: 壁時計の上限付きゲートを MainActor 依存のテストで使う構造を、個別修正でなく構造で塞ぐ（調査と設計）
status: To Do
assignee: []
created_date: '2026-10-06 06:06'
labels:
  - test
  - refactor
dependencies: []
references:
  - TASK-619
  - TASK-665
  - TASK-672
priority: medium
ordinal: 859000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-619（2026-09-13、ゲート予算 60 秒超過）、TASK-665（2026-09-29、15 秒超過）、TASK-672（2026-10-06、120 秒超過）は、同じ型の失敗が 3 週間に 3 回、毎回別のテストで出たもの。型は、「壁時計の上限付きの同期ゲート（BlockingGate.wait）を、MainActor の順番待ちに依存するテスト本体が開ける」で、全テストがほぼ同時に開始して @MainActor で直列化される全体実行（特に TSan）では、単独 0.015 秒のテストが 330〜460 秒かかり、待つ側の上限を混雑が超えるたびに次のテストが落ちる。.claude/CLAUDE.md の「同型のバグが 2 回目に出たら、個別修正をやめて構造で塞ぐ」に従い、3 回目の今、個別修正を続けず構造を決める。TASK-672 は SlowFileReader だけ上限なしにして対処したが、これは 3 件目の個別修正で、BlockingGate を上限付きで使う他の利用箇所（GitCommandFileIndexConcurrencyTests / ViewerWindowControllerDiffTests / GitStatusStoreTests。GitStatusStoreTests は TASK-619 で fixedBudget 300 を渡した）に同じ露出が残る（失敗の観測は無い）。選択肢の候補は、(A) 画像埋め込み等を本番側で async の注入点にして AsyncGate で待つ（TASK-665 と同じ形。同型を消せるが本番コードの継ぎ目の変更を伴う）、(B) 上限付き wait を MainActor 依存のフェイクで使うことを禁止する検査（scripts/check-*.sh）、(C) TSan ジョブを並行性に敏感なスイートへ絞る（混雑の根を減らすがカバレッジが減る）。いずれも効果は推定で未実測。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 BlockingGate.wait を使う全箇所が棚卸しされ、それぞれについて「開ける側が MainActor の順番に依存するか」「上限の根拠（env / fixedBudget / 既定）」「本番側に async の注入点を作って AsyncGate へ移せるか」が実測またはコード参照で示されている
- [ ] #2 選択肢 A / B / C のどれを採るか（併用を含む）が、検討した他の案を採らない理由とともに決まり、不可逆な判断なら ADR（backlog/decisions）に記録されている
- [ ] #3 決めた構造を破ると落ちるもの（破れない構造、または落ちるテスト・検査）が、実装サブタスクの Acceptance Criteria に含まれている
- [ ] #4 実装が必要なら、サブタスクに分割して起票され、サブタスクごとに /review-design が回されている
<!-- AC:END -->
