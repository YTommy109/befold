---
id: TASK-485.18
title: ジャンプバーがジャンプ非対応のファイル・表示モードへ切り替えても開いたまま残る
status: To Do
assignee: []
created_date: '2026-08-18 15:14'
updated_date: '2026-08-18 15:36'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerBridge へ「いま使えるジャンプ種別の集合」を JS へ渡す script を足す（jumpAvailabilityScript(kinds:)）。JS 側の入口は _mmdApplyJumpAvailability(kinds) で、activeKind が含まれなければ _mmdJump.close() する。バーが閉じていれば no-op で、close は冪等（releaseBar は openBar === kind のときだけ効く）。
2. DocumentRendering へ applyJumpAvailability(_ kinds:) を足し、WebViewDocumentRenderer が evaluateJavaScript する。生 String へ落とすのは openJump と同じくこの 1 箇所だけ。
3. WebViewCommandController に同期メソッドを置く。集合は DocumentJumpKind.allCases.filter { capabilities().canJump(to: $0) } で作る。**openJump の guard と同じ canJump(to:) を通す**（AC #4）。allCases 経由なので、新しい kind を足したとき失効判定に自動で載る。
   ViewerScriptDispatcher（BefoldRenderKit）には置かない。QuickLook と共有する層で、ViewerCapabilities を知らないため。
4. 送信契機は ViewerWindowController.refreshToolbarState()（ViewerWindowController+SidebarHost.swift:38-40 の薄いラッパー）。表示モード変更・ファイル切替・フォルダー一覧⇄文書 の 3 系統がすべてここを通る唯一の再同期点。サイドバー操作でも送るが冪等。名前が Toolbar なのに WebView へも送る形になるため、doc コメントで「capability 由来の UI 同期点」と明示する（リネームは UI を作り替える TASK-485.19 でまとめて行うほうが安い）。
5. ミラーによる送信抑止は入れない。契機はユーザー操作起点（モード切替・ファイル切替・サイドバー開閉）で高頻度経路ではなく、evaluateJavaScript 1 回の重複より状態を 1 つ増やす害のほうが大きい。
6. テスト。Swift: WebViewCommandControllerTests の FakeDocumentRenderer へ applyJumpAvailability の Command を足し、(a) 差分表示中は changeBlock を含む、(b) 差分でなければ含まない、(c) capabilities が .none なら空、(d) 集合が allCases から作られている（新しい kind が自動で載る）ことを固定する。JS: viewer-main-jump.test.js で (e) 開いている kind が集合から外れたら閉じる、(f) 含まれていれば開いたまま、(g) 閉じているときに呼んでも何も起きない。修正を戻して落ちることを確認する。
7. find バーは対象外。canFind = onDocument && !isDirectHTMLMode（ViewerCapabilities.swift:76）で表示モードに依存せず失効しないため（該当しないことを Notes に記録する）。
8. swift build / swift test / swiftlint ベースライン差分ゼロ / npm test / npm run check:viewer-bundle。
9. docs/dev/native-app-design.md の文書内ジャンプ節へ、失効時にバーを閉じる経路と、その判定が canJump(to:) 単一であることを追記する。
<!-- SECTION:PLAN:END -->
