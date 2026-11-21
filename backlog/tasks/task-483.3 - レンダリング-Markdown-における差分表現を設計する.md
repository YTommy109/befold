---
id: TASK-483.3
title: レンダリング Markdown における差分表現を設計する
status: Done
assignee:
  - '@claude'
created_date: 2026-08-14 12:47
updated_date: '2026-11-21T00:20:00Z'
labels:
  - diff
  - markdown
milestone: m-4
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

差分は前後 1,000,000 行の文脈付きで取得している（`GitDiffReader.wholeFileContextLines`）ため、差分本文から旧版・新版の全文を復元できる。B のための追加の git 読み込みは要らず、A でも削除ブロックを前後の文脈込みで描ける。

最大の論点は削除の表現。追加は「新しい文書の中の要素を光らせる」で済むが、削除された段落はレンダリング結果に存在しない。削除ブロックも描いて赤くする（文書が実物より長くなる）か、削除は表示せず件数などで示すか、という判断が要る。

あわせて次を決める。

- 既存の inline / side-by-side レイアウト切り替え（`DiffDisplayPreference` / `ViewerDiffBridge.Layout`）がレンダリング差分でどう働くべきか
- Markdown の `diff` モードの意味。今の `diff` はソース差分として動いているため、レンダリング差分へ置き換えるとソース差分が失われる。親タスク TASK-483 の「差分モードの意味」の論点を Markdown について確定させる
- 差分ジャンプ用の `data-diff-block` をどの要素に付けるか

CLAUDE.md の規定により、実装着手前に `/review-design` を 1 回通す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 方式（A / B / その他）が選定され、選ばなかった案とその理由が記録されている
- [x] #2 削除ブロックの見せ方が決まっている
- [x] #3 inline / side-by-side レイアウト切り替えがレンダリング差分でどう振る舞うかが決まっている
- [x] #4 設計スナップショットが docs/superpowers/specs/ に日付付きで残り、冒頭バナーが付いている
- [x] #5 `/review-design` を通した結果が次サブタスクの Implementation Plan または受け入れ条件に反映されている
- [x] #6 Markdown の diff モードの意味（ソース差分を残すか、どう切り替えるか）が決まっている
- [x] #7 差分ジャンプ用の data-diff-block をどの要素に付けるかが決まっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 前提を実測・コードで確かめる（markdown-it の map、差分の送信条件、モード決定）
2. 方式・削除の見せ方・レイアウト・diff モードの意味・data-diff-block の置き場を spec に書く
3. /review-design を回し、結果を TASK-483.4 の Plan と AC に反映する
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
docs/superpowers/specs/2026-11-21-rendered-markdown-diff-design.md に設計を残した。方式 A（新旧を parse し、トップレベルブロック単位で削除→追加を文書順に並べる。CSV と並べ替えを共通化）を採り、B（左右並置）と『削除は件数のみ』を退けた。削除ブロックは描いて削除色、レイアウト切替は効かせず 1 カラム、Markdown は ⌘3 のソース差分を残して ⌘4 をレンダリング差分にする、data-diff-block は変更ブロックの包み div に付ける。/review-design の結果は TASK-483.4 の Plan と AC（見出し id の二重化防止）へ反映した。
<!-- SECTION:FINAL_SUMMARY:END -->
