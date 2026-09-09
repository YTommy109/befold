---
id: TASK-607
title: ViewerRendererZoomIntegrationTests が CI で「準備完了が永久に来ない」形で間欠的に落ちる
status: In Progress
assignee: []
created_date: '2026-09-09 02:06'
updated_date: '2026-09-09 03:25'
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
## 真因（実測で確定）: 並列実行がメインキューを飽和させ WebKit のコールバックが着地しない

`swift test` は swift-testing のテストを並列に走らせる。実 WKWebView の `didFinish` は
**メインキュー経由**で届くが、~1900 件の `@MainActor` テストが同じキューを埋め続けるため、
コールバックがその後ろで待たされる。**キューは走行中ずっと伸びるので、待機予算を
いくら延ばしても間に合わない。**

ローカルで再現した並列実行の内訳（診断ログ `RenderDiagnostics`）:

| 事象 | 件数 |
|---|---|
| `loadFileURL viewer.html` | 25 |
| `didFinish` | 12（**11:43:20 から 35 秒間 1 件も届かず、実行終了時の 11:43:53〜54 に集中**） |
| `shouldNavigate を cancel (surface が未設定)` | 0 |
| `webContentProcessDidTerminate` | 0 |
| `didFail` / `didFailProvisional` | 0 |

ロードは出続けているのに着地が 1 件も無い。これが「60 秒待っても ready にならない」の正体。

## 対処は未確定。**3 案とも失敗した**ので設計判断が要る

| # | 案 | 結果 |
|---|---|---|
| 1 | 自前ポーリングを共有ヘルパーへ（予算 5 秒 → 60 秒） | **失敗**。60 秒でも落ちる（TASK-606 で訂正済み） |
| 2 | `make(for:)` の順序固定（adopt → デリゲート → ロード） | **失敗**。診断で `surface が未設定` の cancel は 0 件 |
| 3 | `swift test --no-parallel` | **失敗**。手元では直列 3 回とも 56 秒で緑だが、**CI ではハング**。02:57:57 の `SurfaceNavigationPolicyTests` を最後に 24 分間出力が止まり打ち切られた（run 34304889554）。CI を悪化させるので revert 済み |

案 3 が手元で通り CI でハングした差は未調査。**次に試す前にここを説明できるようにすること**
（GitHub の macOS ランナーは仮想化されており、ログに
`IOServiceMatching failed for: AppleM2ScalerParavirtDriver` が出る）。

## 次の一手の候補（未検証・要判断）

- **A. 実 WKWebView の統合テストだけを別パスへ出す。** 本体は並列のまま、
  該当スイートを `--skip` し、2 本目で `--filter` して直列に走らせる。案 3 の全体直列より
  範囲が狭いのでハングを踏みにくい可能性があるが、対象一覧が drift する
- **B. 待つ側で run loop を回す。** 待機ヘルパーが `RunLoop.main.run(mode:before:)` を
  小刻みに回し、キューに積まれた WebKit のコールバックを能動的に流す。
  対象が待機ヘルパー 1 箇所で済むが、Swift 並行性とランループの混在になる
- **C. 実 WKWebView への依存を減らす。** 4 件のうち何件が本当に実 WebView を要るかを問う。
  `ViewerRendererMessageStubs.Surface`（WKWebView 実体を作らない面）で足りるものは移す

**採ってはいけない方向**: 待機の延長・テストの無効化・再実行で通す。
60 秒で来ないものは待っても来ないことが実測で分かっている。

## 残してある変更（原因ではないが有効）

- `RenderDiagnostics`（`BEFOLD_RENDER_DIAGNOSTICS=1` のときだけ動く）。面ごとの識別子で
  ロードと着地を突き合わせられる。**この調査の再開はここから**
- `WebKitRenderSurface.make(for:)` の順序固定。窓自体は実在するので閉じてある
  （`SurfaceConstructionOrderTests` が担保）
- `webViewWebContentProcessDidTerminate` の追加。この経路は didFinish も didFail も出さない
<!-- SECTION:NOTES:END -->
