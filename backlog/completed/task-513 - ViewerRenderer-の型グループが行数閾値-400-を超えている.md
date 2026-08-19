---
id: TASK-513
title: ViewerRenderer の型グループが行数閾値 400 を超えている
status: Done
assignee:
  - '@claude'
created_date: '2026-08-18 02:16'
updated_date: '2026-08-18 02:56'
labels: []
milestone: m-6
dependencies: []
priority: medium
type: chore
ordinal: 753000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

`scripts/check-type-group-size.sh` が pre-commit で次を報告する。

```
閾値超過: BefoldApp/BefoldRenderKit/ViewerRenderer が 404 行（閾値 400）
```

内訳（TASK-485.6 のコミット時点、ブランチ falcon-ocotillo）:

| ファイル | 行数 |
| --- | --- |
| `ViewerRenderer.swift` | 243 |
| `ViewerRenderer+ContentUpdate.swift` | 89 |
| `ViewerRenderer+RenderHelpers.swift` | 72 |
| 合計 | 404 |

`origin/main` 時点では 397 行で閾値内だった（`ViewerRenderer.swift` が 236 行）。
TASK-485.x の実装（文書内ジャンプの Swift 側配線）で 7 行増えて超えたもの。

このチェックは現状 exit 0 の助言レベルで、コミットは通る。そのため気づかれずに
増え続ける経路になっている。

## 方針の注意

CLAUDE.md のとおり、**閾値を緩める（`scripts/type-group-exceptions.txt` への追記）を
既定の解にしない**。合算値は extension へ割っても減らないため、責務を別の型へ
切り出すのが本筋。着手時に `ViewerRenderer` の責務（WKWebView ドライバ・
ブリッジ送信・描画ミラーの確定）のどれを分けられるかを先に見る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ViewerRenderer の型グループ合計が 400 行以下になる
- [x] #2 分割は extension ではなく別の型への切り出しで行う（合算値が減ることを check-type-group-size.sh で確認する）
- [x] #3 type-group-exceptions.txt への追記で済ませていない、または追記した場合は理由が Notes に実測付きで残っている
- [x] #4 swift build / swift test が通り、swiftlint のベースライン差分がゼロ
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. WKNavigationDelegate 対応（ViewerRenderer.swift:187-242 の didFinish / didFailProvisionalNavigation / didFail / decidePolicyFor / private handleNavigationFailure、計 56 行）を新規型 ViewerNavigationCoordinator（BefoldRenderKit/ViewerNavigationCoordinator.swift、internal、NSObject + WKNavigationDelegate、unowned let renderer）へ切り出す。姉妹型は BridgeMessageRouter（JS→Swift の framework delegate 面が既に別型になっており、WKWebView→Swift 側だけが本体に取り残されている）。
2. ViewerRenderer は private(set) lazy var navigationCoordinator を持ち、makeWebView で webView.navigationDelegate へ設定する。NSObject / WKNavigationDelegate 準拠を外し、override public init() {} は public init() {} として残す（public 型の既定 init は internal になるため）。
3. ViewerRenderer 側に転送メソッドは作らない（作ると切り出しが名目だけになる）。befoldTests/ViewerReadinessGateTests.swift:66 の呼び先を renderer.navigationCoordinator.webView(...) へ書き換える（@testable import なので internal で届く）。
4. handleNavigationFailure は coordinator の private に落とす。参照する directHTML / readiness は既に internal のため追加の露出は不要。
5. xcodegen generate → swift build → swift test → check-type-group-size.sh --check → swiftlint ベースライン差分ゼロ（/swiftlint-baseline）。
6. やらないこと: PageZoomProjector（appliedPageZoom の書き込み入口を 1 つにする件）は別タスクへ起票する。ViewerRendererDelegate の別ファイル化は主対策にしない（振る舞いも所有関係も変わらず、行数チェックの趣旨を別の綴りで回避する形になるため）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容

WKNavigationDelegate 準拠を `ViewerNavigationCoordinator`（BefoldRenderKit/ViewerNavigationCoordinator.swift、60 行、internal、NSObject + WKNavigationDelegate、unowned let renderer）へ切り出した。姉妹型は BridgeMessageRouter（JS→Swift の framework delegate 面が既に別型で、WKWebView→Swift 側だけが本体に取り残されていた）。ViewerRenderer は NSObject / WKNavigationDelegate 準拠を外し、`override public init() {}` を `public init() {}` に変えた（public 型の既定 init は internal になるため明示が必要）。

## 実測

- 型グループ: 404 行 → **366 行**（ViewerRenderer.swift 243→202、+ContentUpdate 89、+RenderHelpers 72 は不変）。新 ViewerNavigationCoordinator は 60 行の別グループ。`scripts/check-type-group-size.sh --check` が exit 0（型グループの行数は閾値以内です）
- type-group-exceptions.txt への追記なし（登録は ViewerWindowController 1 件のまま）
- `swift build` 成功、`swift test` 1632 tests / 260 suites 全通過
- swiftlint ベースライン差分ゼロ（main 54 件 / HEAD 54 件、正規化後の「真の新規」「解消したもの」いずれも空）

## 設計上の判断（/review-design + responsibility-reviewer の結果）

- **ViewerRenderer 側に転送メソッドを作らない。** 作ると削った行が戻り、「navigation 事象の受け口は coordinator」という主張が名目だけになる。befoldTests/ViewerReadinessGateTests.swift:66 は `renderer.navigationCoordinator.webView(...)` へ呼び先を 1 段深くした（@testable import なので internal で届く）
- **ViewerRendererDelegate（55 行）の別ファイル化は採らなかった。** グループキーが別になるので数値上は 404→349 になるが、振る舞いも所有関係も変わらず、行数チェックが塞いだはずの「ファイルを割れば通る」を別の綴りでやることになる
- **PageZoomProjector は同タスクに混ぜず TASK-514 として起票した。** DirectHTMLModeController が `renderer.appliedPageZoom = nil` を直接書いている結合（DirectHTMLModeController.swift:72, :118）は実在する設計の破れだが、実測で減る行数は約 25 行で、行数タスクに混ぜると本来の価値（書き込み入口を 1 つにする）が「ついで」になる
- **NSObject を外す影響はゼロ**（実測）: `navigationDelegate` の出現は ViewerRenderer.swift の 1 箇所のみ。ViewerRenderer を isEqual / ObjectIdentifier / Set / 辞書キー / as? キャストで扱う箇所は 0 件。OneShotRenderer は内包、ViewerWebView は NSViewRepresentable の Coordinator として保持しているだけ
- **docs/dev/native-app-design.md は更新不要**と判断した。同文書の BefoldRenderKit の項は `ViewerRenderer.swift + ViewerRenderer+*.swift` の 1 行のみで、既存の協力者型（BridgeMessageRouter / DirectHTMLModeController / ViewerReadinessGate 等）も列挙していないため、新規型の追加で記述がずれない
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerRenderer の WKNavigationDelegate 対応（didFinish / didFail 系 / decidePolicyFor / handleNavigationFailure）を新規型 ViewerNavigationCoordinator へ切り出し、ViewerRenderer から NSObject / WKNavigationDelegate 準拠を外した。型グループは 404 行 → 366 行（scripts/check-type-group-size.sh --check が exit 0、恒久例外の追加なし）。swift build 成功、swift test 1632 件全通過、swiftlint ベースライン差分ゼロで確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
