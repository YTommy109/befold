---
id: TASK-483.3
title: レンダリング Markdown における差分表現を設計する
status: To Do
assignee: []
created_date: '2026-08-14 12:47'
labels: []
dependencies: []
parent_task_id: TASK-483
priority: medium
type: task
ordinal: 703000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Markdown をレンダリング表示したまま差分を重ねる際の、表現と方式を決める設計タスク。実装は次のサブタスクで行う。

markdown-it のブロックトークンは `token.map = [開始行, 終了行]` を持つため、「diff の何行目が追加・削除か」から「レンダリング後のどのブロック要素か」への対応付けが取れる。方式の候補は 2 つある。

- A: 新側の全文をレンダリングし、各ブロック要素にソース行を持たせて、追加行に該当するブロックへ差分色を当てる
- B: 旧版と新版をそれぞれ普通にレンダリングして左右に並べる（実装は最小だが、どこが変わったかは目視任せ）

最大の論点は削除の表現。追加は「新しい文書の中の要素を光らせる」で済むが、削除された段落はレンダリング結果に存在しない。削除ブロックも描いて赤くする（文書が実物より長くなる）か、削除は表示せず件数などで示すか、という判断が要る。

あわせて、既存の inline / side-by-side レイアウト切り替え（`DiffDisplayPreference` / `ViewerDiffBridge.Layout`）がレンダリング差分でどう働くべきかも決める。

CLAUDE.md の規定により、実装着手前に `/review-design` を 1 回通す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 方式（A / B / その他）が選定され、選ばなかった案とその理由が記録されている
- [ ] #2 削除ブロックの見せ方が決まっている
- [ ] #3 inline / side-by-side レイアウト切り替えがレンダリング差分でどう振る舞うかが決まっている
- [ ] #4 設計スナップショットが docs/superpowers/specs/ に日付付きで残り、冒頭バナーが付いている
- [ ] #5 `/review-design` を通した結果が次サブタスクの Implementation Plan または受け入れ条件に反映されている
<!-- AC:END -->
