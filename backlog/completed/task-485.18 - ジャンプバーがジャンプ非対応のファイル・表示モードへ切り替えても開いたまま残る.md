---
id: TASK-485.18
title: ジャンプバーがジャンプ非対応のファイル・表示モードへ切り替えても開いたまま残る
status: Done
assignee:
  - '@claude'
created_date: '2026-08-18 15:14'
updated_date: '2026-08-18 15:56'
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
- [x] #1 見出しジャンプを開いた状態でジャンプ非対応のファイルへ切り替えると、バーが自動的に閉じる
- [x] #2 変更ブロックジャンプを開いた状態で差分表示から離れると、バーが自動的に閉じる
- [x] #3 対象が引き続き有効なファイル・モードへの切り替えでは、バーが開いたままであることを壊していない
- [x] #4 失効判定と openJump の事前検査が同じ条件を参照していることが構造で分かる（判定の重複が無い）
- [x] #5 上記をテストで担保している
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: Swift → JS の一方向 1 経路。ViewerBridge.jumpAvailabilityScript(kinds:) → _mmdApplyJumpAvailability(kinds) → JumpController.closeUnlessAvailable(kinds)。開いている種類が集合に無ければ閉じる。

単純化の検討: 「閉じろ」を送る案（Swift が失効を判断して close を叩く）と、JS 側だけで完結させる案（_mmdViewOptions.diff() などから可否を組み直す）を先に検討した。前者は Swift が「いまバーが開いているか」を知らないため無条件送信になり、後者は「変更ブロックは差分表示中だけ」という同じ規則が Swift と JS の 2 箇所で別々に育つ。使える集合を送る形にすると、可否の規則は canJump(to:) 1 箇所のままで、JS は集合と自分の状態を比べるだけになる。

ミラーによる送信抑止は入れなかった: 契機がユーザー操作起点（モード切替・ファイル切替・サイドバー開閉）で、キーストロークや監視コールバックのような高頻度経路ではない。evaluateJavaScript 1 回の重複より状態を 1 つ増やす害のほうが大きいと判断した。

AC #4 の担保（判定の重複が無いこと）: 集合を DocumentJumpKind.allCases.filter { canJump(to: $0) } で作り、それを固定するテストを置いた。列挙を手書き（[.heading] など）に変えると 2 件落ちる。実測で確認済み。

find バーは対象外（該当しないことの記録）: canFind = onDocument && !isDirectHTMLMode（ViewerCapabilities.swift:76）で表示モードに依存しないため失効しない。find バーもファイル切替では閉じないが、これは破綻ではない。

契約テスト: _mmdApplyJumpAvailability は引数を取るため ViewerBridge.PlainFunction の allCases 網に載らない。_mmdOpenJump と同じく ViewerBridgeContractTests へ明示的に定義存在の検査を追加した。

検証（実測）:
- swift build: Build complete
- swift test: 1645 tests / 263 suites すべて成功
- npm test: 10 スイート / 537 件すべて成功
- 修正を戻して確認（JS）: closeUnlessAvailable の close() を外すと 3 件落ちる。残る 2 件は「閉じないこと」を見るテストなので通るのが正しい
- 修正を戻して確認（Swift）: allCases を [.heading] の手書き列挙に変えると 2 件落ちる
- swiftlint ベースライン差分: main / HEAD ともに 54 件、真の新規ゼロ・解消ゼロ
- swiftformat: 0/16 files formatted（変更なし）
- npm run lint (--type-aware) / typecheck:viewer / check-viewer-cycles: いずれもクリーン
- markdownlint-cli2: 0 issues / scripts/check-doc-symbols.sh: 指摘なし

docs/dev/native-app-design.md の文書内ジャンプ節へ、失効時に閉じること・集合を送る理由・送信契機・検索バーを同じ扱いにしない理由を追記した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ジャンプ非対応のファイルや表示モードへ切り替えたとき、開いたままだったジャンプバーを自動的に閉じるようにした。Swift は「閉じろ」ではなく、いま使える種類の集合（DocumentJumpKind.allCases を canJump(to:) で絞ったもの）を送り、viewer 側は開いている種類がそこに無ければ閉じる。開くときの guard と同じ述語を通るため、開く条件と開き続けられる条件が食い違わず、種類を足したときの載せ忘れも構造で塞がれている（列挙を手書きに変えるとテストが落ちることを実測で確認）。swift test 1645 件・npm test 537 件成功、swiftlint ベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
