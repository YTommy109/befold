---
id: TASK-440
title: ViewerRenderer（型グループ 1300 行）を責務ごとに分割する
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-11 05:05'
updated_date: '2026-08-11 05:33'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 100100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/BefoldRenderKit/ の ViewerRenderer 型グループ（本体 + 5 本の extension の合算）が 1300 行で、型グループ単位の全 12 グループ中で最大。scripts/check-type-group-size.sh の実測値であり、scripts/type-group-baseline.txt にも同値が凍結されている。

内訳: ViewerRenderer.swift 370 / +RenderHelpers 265 / +ContentUpdate 238 / +OneShot 177 / +MessageHandling 146 / +DirectHTMLLinkPolicy 104。

ファイル単位では全て file_length の warning 400 を下回っており、TASK-428 の起票時にファイル単位で測った 7 件のリストには現れていなかった。合算で数えて初めて顕在化したグループであり、file_length の error 閾値 1000 をグループとしては超えている。

この型は本体アプリと QuickLook 拡張の双方が使う描画エンジンであり、肥大化の影響範囲が広い。分割は extension をさらに切るのではなく、独立した型へ関心を出す形で行うこと（extension を増やしても型グループの合算値は減らない）。

着手前に responsibility-reviewer サブエージェントを回し、どの関心を独立型へ出すかを決めてから実装すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 型グループの合算行数が 400 行以下になる（scripts/check-type-group-size.sh で確認できる）
- [ ] #2 ベースライン scripts/type-group-baseline.txt から ViewerRenderer のエントリが消える
- [ ] #3 分割は extension の追加ではなく独立型への切り出しで行われている（切り出し先の型名が説明できる）
- [ ] #4 新規ファイル追加後に xcodegen generate を実行し xcodebuild でも通る
- [ ] #5 main との swiftlint 差分に真の新規が無い
- [ ] #6 swift test が既存どおり通り、QuickLook 拡張のビルドも通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
responsibility-reviewer の分析（実測: stored property 23 個・ネスト型 10 個・関心 12 個）に基づく 5 段階。順序を入れ替えない（段階 5 は段階 1 の型のトップレベル化が前提）。

段階 1（非破壊, -330 → 約 970）
1. RenderValues.swift: DiffState / TruncationState / RenderRequest / AppendRequest をトップレベル型へ
2. RenderedStateMirror.swift: RenderedStateMirror / PendingAppend / canConsumePendingAppend / isFileOrModeSwitch / shouldEnterDirectHTMLMode / renderableContent（全て既に nonisolated static）
3. ViewerWebViewFactory.swift: makeWebView / loadViewerHTML / messageHandlerNames / dismantle / WeakScriptMessageHandler

段階 2（非破壊, -200 → 約 770。ここで error 閾値 1000 を下回る）
4. BridgeMessageRouter.swift: userContentController + handle* 5 個
5. ReferenceResolutionQueue.swift: handleResolveReferences / resolveResponseChain / pageGeneration

段階 3（公開 API に触れる, -180 → 約 590）
6. OneShotRenderer.swift: +OneShot 全体。ViewerRenderer を内包する（継承・extension にしない）。呼び出し側は PreviewViewController と RenderedMarkdownView の 2 箇所のみ

段階 4（-200 → 約 390）
7. DirectHTMLModeController.swift: isDirectHTMLMode / lastDirectHTMLPath / pendingPageZoom + enter/exit/reload/リンクポリシー
8. ViewerReadinessGate.swift: isReady / pendingUpdate（現在 4 箇所に散る書き込みを 1 型へ）
   WKNavigationDelegate 準拠は webView.navigationDelegate が weak のため ViewerRenderer に残す

段階 5（-190 → 400 以下）
9. ContentUpdatePlanner.swift: doUpdate クロージャ 125 行を nonisolated static な純関数 plan(...) -> UpdatePlan へ
10. ViewerScriptDispatcher.swift: evaluateJavaScript 発行点を集約

各段階で不変条件を doc コメントではなく構造で担保する（recordRendered の単一入口 / pageGeneration の単一 incrementer / pendingUpdate の単一書き込み点 → private(set) + mutating func）。
各段階で xcodegen generate → swift test。ベースラインは 1289 tests / 180 suites 全通過。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 着手前の責務分析（responsibility-reviewer, 2026-08-11）

**この extension 6 分割は責務分離ではなく行数回避**という判定。証拠 3 点:

1. doc コメント自身が 4 箇所で自認している（+ContentUpdate.swift:86 と +MessageHandling.swift:16 が 'type_body_length 対策で ViewerRenderer 本体の外の extension に分離している'、+DirectHTMLLinkPolicy.swift:8-9 と ViewerRenderer.swift:318 も同様。RenderRequest / AppendRequest は 'function_parameter_count 対策' で生まれた型）
2. 主要 extension が本体の stored property を大量参照（全 23 個中: +ContentUpdate 15 / +RenderHelpers 14 / +MessageHandling 5 / +OneShot 4 / +DirectHTMLLinkPolicy 2）。上位 2 つは本体と同一の状態集合を触っており切れていない。下位 3 つは独立型へ出せる候補であることが数字に出ている
3. ネスト型 10 個。うち DiffState(11 参照) / TruncationState(8 参照) は befold 本体からも使う公開値型

関心は MARK 区切りの 5 個ではなく実質 12 個。プロトコル準拠 3（NSObject / WKNavigationDelegate / WKScriptMessageHandler）。注入クロージャは 0 で、クロージャバンドル規定は既に満たしている（ViewerRendererDelegate へ移行済み。この構造は崩さない）。

**400 行は 1 回では届かない**（5 段階必要）。段階 1〜2 は非破壊で 1300 → 約 770 となり、ここで file_length の error 閾値 1000 をグループとして下回る。段階 3 以降は公開 API（loadOneShot の移設、DiffState の typealias 撤去）に触れ、QuickLook 拡張と本体の両方へ波及する。

副次的な利得として、現在 doc コメントの約束だけで担保されている 3 つの不変条件を構造へ移せる: recordRendered の単一入口 / pageGeneration を増やすのは reloadViewerHTML の 1 箇所だけ / pendingUpdate の書き込み（現在 4 箇所に散り、後勝ちで前の保留更新が黙って消える）。

## ベースライン（実測）

swift test --skip Integration --skip FileWatcherTests: **1289 tests / 180 suites 全通過**（exit 0）。
<!-- SECTION:NOTES:END -->
