---
id: TASK-485.28
title: ジャンプを cmd+shift+F で開き、cmd+F と cmd+shift+F をトグルにする
status: To Do
assignee: []
created_date: '2026-09-25 08:34'
labels: []
dependencies: []
parent_task_id: TASK-485
ordinal: 829000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
文書内ジャンプの呼び出しを cmd+shift+F に割り当てる。ジャンプ 3 種（見出し・定義・変更ブロック）は排他（TASK-485.26）なので、キーは 1 つでその表示で使える種類を開く。ジャンプが無い表示では検索を開く。
cmd+F は常に検索を開く（差分表示中に変更ブロックへ振り分ける ViewerCapabilities.defaultBarKind は撤去する）。
cmd+F / cmd+shift+F はトグル: バーが閉じていれば開く、同じモードで開いていれば閉じる、別モードで開いていればそのモードへ切り替える。
紹介サイトのショートカット表への反映はゲート撤去後（TASK-485.25）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 cmd+shift+F でその表示で使えるジャンプ（見出し・定義・変更箇所のどれか）が開く
- [ ] #2 ジャンプが無い表示で cmd+shift+F を押すと検索が開く
- [ ] #3 cmd+F は表示に依らず検索を開く（差分表示中も）
- [ ] #4 同じキーをもう一度押すとバーが閉じ、別のキーならモードが切り替わる
- [ ] #5 MainMenuBuilder の「キー等価を付けない」旨の doc コメントが実態に合っている
<!-- AC:END -->
