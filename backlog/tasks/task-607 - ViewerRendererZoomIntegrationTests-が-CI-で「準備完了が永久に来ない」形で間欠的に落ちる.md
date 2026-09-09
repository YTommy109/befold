---
id: TASK-607
title: ViewerRendererZoomIntegrationTests が CI で「準備完了が永久に来ない」形で間欠的に落ちる
status: To Do
assignee: []
created_date: '2026-09-09 02:06'
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
- [ ] #1 準備完了が来ない経路（読み込み未開始 / didFinish 未着）が実測で特定されている
- [ ] #2 待機時間の延長やテストの無効化ではなく、来ない原因そのものが直っている
<!-- AC:END -->
