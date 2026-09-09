---
id: TASK-601
title: '`WebKitSurfaceEventBridge` のナビゲーション種別の写像に担保が無い'
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-09-08 14:17'
updated_date: '2026-09-08 15:08'
labels: []
dependencies: []
priority: low
type: task
ordinal: 873000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-595.2 で `WKNavigationType` → `SurfaceNavigationRequest.Kind` の写像が `WebKitSurfaceEventBridge` へ移った。`SurfaceEvents.swift` の doc は「**3 つに分ける。2 値へ潰さないこと。** …3 つ目を 1 つ目へ寄せるとリロードや戻る/進むが黙って通るようになる」と明記しているが、この写像を見るテストは 1 本も無い（実測: `rg "surfaceShouldNavigate|SurfaceNavigationRequest|WebKitSurfaceEventBridge" BefoldApp/befoldTests` は `ViewerNavigationCoordinatorLifetimeTests` の「renderer 解放済みなら .cancel」1 件だけにヒット）。

写像の `default: .otherInteraction` を誰かが `.programmatic` へ寄せても、ビルドも CI も通る。その状態では viewer.html モードでリロード・戻る/進む・フォーム送信が `.allow` になり、`decidePolicy` の「viewer.html モードではリンク以外を全て止める」が破れる。

あわせて `DirectHTMLModeController.decidePolicy` の 3 分岐（programmatic → allow / 非アクティブ → cancel / linkActivated → 分類）自体も無テスト。`SurfaceNavigationRequest` は WebKit 非依存の値になったので、いまなら実 WKWebView 無しで直接テストできる（それがこの境界を入れた利点そのもの）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `WebKitSurfaceEventBridge` が `.linkActivated` / `.other` / それ以外（reload・backForward・formSubmitted）を .linkActivated / .programmatic / .otherInteraction へ写すことを見るテストがある
- [x] #2 `DirectHTMLModeController.decidePolicy` の 3 分岐を `SurfaceNavigationRequest` の値で直接見るテストがある（実 WKWebView を作らない）
- [x] #3 写像を 2 値へ潰すと落ちることを、修正を戻して確認してある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 既存の fake (`ViewerRendererMessageStubs.Surface`) と `ViewerRenderer` を使い、WKWebView 実体を作らずに `DirectHTMLModeController.decidePolicy` の 3 分岐を直接見るテストを追加する（AC#2）。分岐は programmatic → .allow / 非アクティブ → .cancel / アクティブ + linkActivated → DirectHTMLLinkPolicy の分類。NSWorkspace.open を起こす openExternal 経路は避け、ローカルファイル・同一文書フラグメント・url なし・otherInteraction で覆う。
2. `WKNavigationAction` のサブクラスで navigationType / request / modifierFlags を差し替え、`WebKitSurfaceEventBridge.webView(_:decidePolicyFor:decisionHandler:)` に流して `SurfaceNavigationRequest.Kind` の写像を記録する fake observer で見るテストを追加する（AC#1）。.linkActivated / .other / .reload / .backForward / .formSubmitted / .formResubmitted を全て通す。
3. `xcodegen generate` → `swift test` で通ることを確認する。
4. 写像の `default: .otherInteraction` を `.programmatic` へ寄せた版と、`case .other: .programmatic` を `.otherInteraction` へ寄せた版で落ちることを実測して AC#3 を満たす。元へ戻して再度 green を確認する。

設計レビュー(/review-design)は回さない: 追加するのはテストのみで、プロダクト側の状態・分岐・経路を増やさないため（CLAUDE.md の「小さな局所修正には適用しない」に該当）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

`BefoldApp/befoldTests/SurfaceNavigationPolicyTests.swift` を新設（テストのみ。プロダクトコードは 1 行も変えていない）。

- `SurfaceNavigationStubs`: `SurfaceNavigationObserver` / `SurfaceBridgeMessageObserver` の記録用スタブと、`navigationType` / `request` / `modifierFlags` を差し替えた `WKNavigationAction` サブクラス。WebKit は実遷移からしかこの型を作らないため、写像を単体で見るにはこの形しかない。
- `WebKitSurfaceEventBridgeMappingTests`（6 本）: `.linkActivated` → .linkActivated / `.other` → .programmatic / `.reload`・`.backForward`・`.formSubmitted`・`.formResubmitted` → .otherInteraction。あわせて URL・修飾キーの素通し、観測者解放時の `.cancel`、判断の `WKNavigationActionPolicy` への写しも固定した。
- `DirectHTMLDecidePolicyTests`（7 本）: `decidePolicy` の 3 分岐を fake の描画面（`ViewerRendererMessageStubs.Surface`）だけで組む。実 WKWebView は作らない。

## テストが空振りしていた 1 本を作り直した

「直接 HTML モードでも、リンククリック以外は止める」の初版は `.otherInteraction` + 他ファイルの URL で見ていたが、`DirectHTMLLinkPolicy.classify` がその URL を `.openLocalFile`（= `.cancel`）に分類するため、`guard request.kind == .linkActivated` を外しても通ってしまった（実測）。同一文書内フラグメント（`classify` が唯一 `.allow` へ倒す入力）へ差し替え、delegate が呼ばれないことも見るようにして落ちるようにした。

## 実測: 変異を入れて落ちることを確認（AC#3）

いずれも 1 箇所だけ書き換えて `swift test --filter` を実行し、元へ戻して green を再確認した。

| 変異 | 結果 |
|---|---|
| `default: .otherInteraction` → `.programmatic` | 「リロード・戻る/進む・フォーム送信は…」が 4 issue で失敗 |
| `case .other: .programmatic` → `.otherInteraction` | 「プログラムからのロード(.other)は…」が失敗 |
| `case .linkActivated: .linkActivated` → `.programmatic` | 「リンククリックは .linkActivated へ写る」が失敗 |
| `guard isActive else { return .cancel }` → `.allow` | 「viewer.html モードでは…」が 2 issue で失敗 |
| `guard request.kind == .linkActivated, let url…` から kind 判定を削除 | 「直接 HTML モードでも、リンククリック以外は分類せず止める」が失敗 |
| `if request.kind == .programmatic { return .allow }` を削除 | programmatic の 2 本が失敗 |

## 検証

- `swift test`: 1942 tests / 320 suites 全て pass
- swiftlint: 新規ファイルからの指摘 0 件（`swiftlint lint --quiet` の出力 51 行に `SurfaceNavigationPolicyTests` は 1 件も現れない）
- swiftformat: 変更なし
- `xcodegen generate` 実行済み

`docs/dev/native-app-design.md` は更新しない（現在仕様は変わっておらず、追加したのは既存の doc コメントに対する担保のみ）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`WKNavigationType` → `SurfaceNavigationRequest.Kind` の 3 値写像と `DirectHTMLModeController.decidePolicy` の 3 分岐を、実 WKWebView 無しで固定するテスト 13 本を `SurfaceNavigationPolicyTests.swift` に追加した。写像を 2 値へ潰す変異 3 種と decidePolicy の分岐を崩す変異 3 種を実際に入れ、それぞれ対応するテストが落ちることを実測して確認した（1 本は初版が空振りしていたので同一文書内フラグメントを使う形へ作り直した）。プロダクトコードの変更は無し。`swift test` は 1942 tests 全て pass。
<!-- SECTION:FINAL_SUMMARY:END -->
