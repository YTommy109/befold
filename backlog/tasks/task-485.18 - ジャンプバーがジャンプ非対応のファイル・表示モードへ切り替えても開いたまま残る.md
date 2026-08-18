---
id: TASK-485.18
title: ジャンプバーがジャンプ非対応のファイル・表示モードへ切り替えても開いたまま残る
status: To Do
assignee: []
created_date: '2026-08-18 15:14'
updated_date: '2026-08-18 15:15'
labels: []
milestone: m-6
dependencies:
  - TASK-485.7
parent_task_id: TASK-485
priority: medium
type: bug
ordinal: 765000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 症状

見出しジャンプのバーを開いた状態で、サイドバー等から別のファイルへ切り替えても
バーが表示されたまま残る。切り替え先がジャンプ対象外（画像・PDF・HTML 直描画、
あるいは見出しジャンプ非対応のソース表示など）でも同じで、0 件のバーが
操作できない状態で居座る。表示モードの切り替え（レンダリング → ソース、
差分 → ソース）でも同様に、その kind のジャンプが使えなくなった後もバーが残る。

## 期待する挙動

いま開いているジャンプの kind が `ViewerCapabilities.canJump(to:)` で
偽になった時点でバーを閉じる。

## 調査の起点

- `viewer-src/jump.ts` の `open` / `close` / `invalidate` / `refresh`。
  描画のたびに `invalidate` → 着地で `refresh` は走るが、
  **「もう対象外になったから閉じる」経路は無い**（`close` の呼び出しは
  Esc（`bar.ts` の closeCurrentBar）と閉じるボタンのみ）
- capability の判定は Swift 側（`befold/Viewer/ViewerCapabilities.swift:103`）に
  あり、JS 側は知らない。閉じる判断をどちらに置くかが設計上の分かれ目
- 変更ブロックジャンプは `canJumpToChangeBlock`（差分表示中のみ）なので、
  差分から離れた瞬間に閉じるべき代表例

## 関連

TASK-485.7（`openJump(kind:)` が kind 別 capability を検査しない）と同じ穴の
裏返し。開くときの検査だけでなく、**開いている間の失効**も扱う必要がある。
片方だけ直すと同型のバグが残るため、実装時に両者の判定を 1 箇所へ寄せられないかを
先に検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 見出しジャンプを開いた状態でジャンプ非対応のファイルへ切り替えると、バーが自動的に閉じる
- [ ] #2 変更ブロックジャンプを開いた状態で差分表示から離れると、バーが自動的に閉じる
- [ ] #3 対象が引き続き有効なファイル・モードへの切り替えでは、バーが開いたままであることを壊していない
- [ ] #4 失効判定と openJump の事前検査が同じ条件を参照していることが構造で分かる（判定の重複が無い）
- [ ] #5 上記をテストで担保している
<!-- AC:END -->
