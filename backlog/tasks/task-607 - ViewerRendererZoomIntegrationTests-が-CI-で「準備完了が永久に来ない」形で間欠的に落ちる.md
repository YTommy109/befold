---
id: TASK-607
title: ViewerRendererZoomIntegrationTests が CI で「準備完了が永久に来ない」形で間欠的に落ちる
status: Done
assignee: []
created_date: '2026-09-09 02:06'
updated_date: '2026-09-09 04:27'
labels: []
dependencies: []
priority: high
ordinal: 887000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ViewerRendererZoomIntegrationTests`（実 WKWebView を使う Integration）が CI の
build-and-test で間欠的に落ちる。TASK-606 で待機予算の問題は潰したが、それは原因では
なかった（あちらの Notes に訂正あり）。

## 症状

`ViewerReadinessGate.isReady` が **60 秒待っても true にならない**。二極で、
速く準備できるか、まったく来ないかのどちらか。遅いのではない。

## 実測（PR #643 / CI 4 回）

| 実行 | コミット | 結果 |
|---|---|---|
| A | f33ff1ba | 1 件失敗 |
| A 再実行 | 同一 | 成功 |
| B | TASK-606 の修正入り | 4 件すべて失敗（60 秒で ready にならず） |
| B 再実行 | 同一 | 成功 |

**同一コミットが再実行で 2 回とも成功**しているので、コードの決定的な誤りではない。

- ローカルでは 3 回とも 0.58 秒で緑。CI では 1 件に 92〜127 秒かかっている
- ランナーのログに `IOServiceMatching failed for: AppleM2ScalerParavirtDriver`（GPU 無し）

## 疑うべき箇所（未検証）

- `ViewerWebViewFactory.loadViewerHTML` は `applyRemoteLoadPolicy` の**完了を待ってから**
  viewer.html を読む。`RemoteLoadBlocker.obtainRuleList` は `WKContentRuleListStore.default()`
  でのコンパイル（非同期・ディスク）で、これが返らなければ読み込み自体が始まらない。
  static な `cached` を持つため、実行順で挙動が変わりうる
- `bundle.url(forResource: "viewer", withExtension: "html")` が nil のとき
  `loadViewerHTML` は**黙って early return** する。この経路に入ると ready は永久に来ない
- ヘッドレスランナーで WebContent プロセスが起動しない可能性

## 切り分けの起点

まず「読み込みが始まっていないのか、始まったが didFinish が来ないのか」を分ける。
`loadViewerHTML` の early return と `applyRemoteLoadPolicy` の完了に診断ログを置き、
CI で 1 回再現させるのが最短。**検知を緩めて（待機を伸ばして／テストを外して）
通す方向へ倒さないこと**——60 秒で来ないものは待っても来ない。

## 補足

このブランチ（TASK-604 系）は readiness・pageZoom の経路を触っていない
（`git diff origin/main...HEAD -- BefoldApp/BefoldRenderKit` に isVisible / readiness /
pageZoom / isReady の増減行は 0 件、`PageZoomProjector.swift` と
`ViewerReadinessGate.swift` は無変更、`loadViewerHTML` は WebKit 面については
main と等価）。main で顕在化していないだけの潜在的なものか、この枝で確率が上がったのかは
未確定。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 準備完了が来ない経路（読み込み未開始 / didFinish 未着）が実測で特定されている
- [x] #2 待機時間の延長やテストの無効化ではなく、来ない原因そのものが直っている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 真因

`Task.sleep` 系の待機では**メインランループが回らず、実 WKWebView のロードが前進しない**。
姉妹スイート `ViewerRendererContentUpdateIntegrationTests` の doc が既にこれを記録していた
——「yield スピン自体がメインランループを回してロードを前進させる」「時間ベース
(`waitUntilOnMainActor`)は予算 60 秒でも成立しない」。

旧 25ms ループも、TASK-606 で入れた `waitUntilOnMainActor` も、どちらもこの形だった。
並列実行では他のテストの `Task.yield` がたまたまランループを回すため、
**通るか永久に来ないかの二極**になり、間欠失敗として現れていた。

## 対処: 実 WKWebView 依存そのものを外した

待ち方を変えるのではなく依存を外した。根拠は、このスイートの全アサートが
`renderer.pageZoom.applied` / `readiness.isReady` という **Swift 側の状態**で、
JS を覗くアサートが 1 つも無かったこと——実 WebView に触る唯一のヘルパー
`currentZoom(in:)` は**定義されたまま一度も呼ばれていなかった**。
実 WebView が与えていたのは「準備完了の契機」だけで、それは本番と同じ
`navigationCoordinator.surfaceDidFinishLoad()` で直接起こせる。

`ViewerRendererZoomIntegrationTests` → **`ViewerRendererZoomProjectionTests`** へ改名し、
`ViewerRendererMessageStubs.Surface`(WKWebView 実体を作らない面)を `adopt` する形にした。
もう Integration ではないので名前もそれに合わせた。

## 実測

- 4 件が **0.051 秒**で決定的に通過（従来: ローカル 0.6 秒 / CI 92〜127 秒、間欠失敗）
- **網羅は保たれている**: `PageZoomProjector.desired` に `didSet { applyIfReady() }` を入れて
  TASK-567 のバグを再現させると 3 件が落ち、戻すと通る
- フル実行 2 回連続で 1947 tests / 324 suites 緑

## 残る待機について

`rendered.contentRevision` と `pageZoom.applied` の 2 箇所は待ちが残るが、これは
**Swift 側の非同期**（`applyRender` が種別によらず `await embeddedContent` を通る）で、
スリープでも前進するので待って正しい。予算は `testTimeout(fallback: 30)` と明示した
——既定の 10 秒だとフル実行の並列負荷で MainActor 外の埋め込みが遅れて予算切れした実測がある。

## 採らなかった対処（すべて実測で否定）

| 案 | 結果 |
|---|---|
| 待機予算 5 秒 → 60 秒 | 60 秒でも落ちる。ランループが回らないので待っても来ない |
| `make(for:)` の順序固定 | 診断で該当の cancel は 0 件。原因ではなかった（変更自体は残置） |
| `swift test --no-parallel` | 手元は直列 3 回とも緑だが、**CI でハング**し 24 分で打ち切り。revert 済み |

## PR #644 で先行マージ済みのもの（原因ではないが有効）

`RenderDiagnostics`（この調査の入口。`BEFOLD_RENDER_DIAGNOSTICS=1` で有効）、
`WebKitRenderSurface.make(for:)` の順序固定、`webViewWebContentProcessDidTerminate` の追加。
<!-- SECTION:NOTES:END -->
