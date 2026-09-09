---
id: TASK-607
title: ViewerRendererZoomIntegrationTests が CI で「準備完了が永久に来ない」形で間欠的に落ちる
status: Done
assignee: []
created_date: '2026-09-09 02:06'
updated_date: '2026-09-09 02:51'
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
## 真因: テストの並列実行がメインキューを飽和させ、WebKit のコールバックが着地しない

`swift test` は swift-testing のテストを並列に走らせる。実 WKWebView を使う統合テストは
`didFinish` が**メインキュー経由**で届くが、~1900 件の `@MainActor` テストが同じキューを
埋め続けるため、コールバックがその後ろで待たされる。**待機予算をいくら延ばしても
間に合わない**（キューは走行中ずっと伸び続けるため）。

### 実測（ローカルで再現。診断ログ `RenderDiagnostics` による）

並列（失敗した回）:

| 事象 | 件数 |
|---|---|
| `loadFileURL viewer.html` | 25 |
| `didFinish` | 12（**すべて実行の最後 11:43:53〜54 に集中**） |
| `shouldNavigate を cancel (surface が未設定)` | **0** |
| `webContentProcessDidTerminate` | **0** |
| `didFail` / `didFailProvisional` | **0** |

ロードは 11:43:20 から出続けているのに、`didFinish` は 35 秒間 1 件も届かず、
テスト実行が終わる時点でまとめて 12 件着地した。これが「60 秒待っても ready にならない」
の正体。`--no-parallel` では着地が時間軸に分散し、全件緑になる。

### 対処

`ci.yml` の `swift test` を 2 ステップとも `--no-parallel` にした。
代償は実行時間 40 秒 → 56 秒（ローカル実測）。ローカルで直列 3 回連続緑。

検知を緩める方向（待機を伸ばす・テストを外す・再実行で通す）は採っていない。

## 訂正 2 件

1. **「5 秒予算の枯渇」は原因ではなかった**（TASK-606 の Notes で訂正済み）。60 秒でも落ちる。
2. **「adopt より前の初回ロードが `.cancel` される」も原因ではなかった。**
   1 回目の診断で観測した `shouldNavigate を cancel` 1 件は、意図的な寿命テスト
   `ViewerNavigationCoordinatorLifetimeTests.decidePolicyCancelsWhenRendererIsReleased`
   が出していたもの（renderer 解放であって surface 未設定ではない）。
   メッセージが両者を畳んでいたため取り違えた。理由を分けて記録するよう直し、
   再測したところ `surface が未設定` は 0 件だった。

## 残した変更（原因ではないが有効なもの）

- **`WebKitRenderSurface.make(for:)` の順序固定**: 組み立て → 結びつけ →
  デリゲート接続 → ロード開始。窓そのものは実在した（デリゲートを繋いだ直後に
  ロードを始めており、`renderer.surface` 未設定でコールバックを受けうる）ので閉じてある。
  `SurfaceConstructionOrderTests` が担保する（修正前は落ちることを確認済み）。
- **`webViewWebContentProcessDidTerminate`** を `WKNavigationDelegate` に追加。
  この経路は didFinish も didFail も出さないため、握っていないと同じ症状になる。
  今回は 0 件だったが、握っていない状態を残す理由が無い。
- **`RenderDiagnostics`**（`BEFOLD_RENDER_DIAGNOSTICS=1` のときだけ動く）を残す。
  面ごとの識別子でロードと着地を突き合わせられる。次に同種の障害が出たときの入口。
  CI での常時有効化は外した。
<!-- SECTION:NOTES:END -->
