---
id: TASK-606
title: ViewerRendererZoomIntegrationTests の自前ポーリングが CI 予算を無視して間欠的に落ちる
status: Done
assignee: []
created_date: '2026-09-09 01:47'
updated_date: '2026-09-09 01:48'
labels: []
dependencies: []
priority: medium
ordinal: 886000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ViewerRendererZoomIntegrationTests` が PR #643 の CI（build-and-test）で間欠的に赤くなった。

失敗は「倍率は代入では当たらず、次に描かれるときに当たる」の
`#expect(renderer.pageZoom.applied == 1.0)`（`:64`）で、`applied` が nil。

## 原因

このスイートだけが**自前のポーリング**を持っていた（`befoldTests` で唯一）。

- `waitUntilReady` は 25ms × 200 回 = **5 秒固定**で、`BEFOLD_TEST_TIMEOUT_SECONDS`
  （`ci.yml` が build-and-test に 60、thread-sanitizer に 120 を設定している）を読まない
- **時間切れでも黙って先へ進む**ため、失敗が「準備できていない」ではなく
  後続の `applied == nil` として現れ、原因が読めない
- 同じ形の裸ループが他に 2 箇所（`:77` `:99`）

GPU の無い CI ランナー（ログに `IOServiceMatching failed for: AppleM2ScalerParavirtDriver`）
では実 WKWebView のロードが 5 秒に収まらないことがある。同ジョブでこのテスト 1 件が
127 秒かかっていた。ローカルでは同じテストが 0.58 秒で、3 回とも緑。

前例: TASK-437（CI で待機上限に達して落ちる）、TASK-517（打ち切りを予算から導かない）。

## 対処

3 箇所とも共有ヘルパー `waitUntilOnMainActor` へ置き換える。予算は
`testTimeout(fallback:)` 経由で CI の環境変数に追随し、時間切れはその場で
`Issue.record` される。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 自前のポーリングループが無くなり、待機予算が BEFOLD_TEST_TIMEOUT_SECONDS に追随する
- [x] #2 待機が時間切れになったとき、後続のアサートではなく待機地点で失敗が報告される
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施

`waitUntilReady` の自前ループと、裸のポーリング 2 箇所（`:77` の `pageZoom.applied`、
`:99` の `rendered.contentRevision`）を共有ヘルパー `waitUntilOnMainActor` へ置き換えた。
`befoldTests` から自前ポーリングは無くなった。

## 切り分けの実測

- CI（PR #643 / run 34299261374）で 1 件だけ失敗。**同じコミットのまま再実行したら成功**した。
- ブランチが `BefoldRenderKit` を触っているので差分を確認した。
  `git diff origin/main...HEAD -- BefoldApp/BefoldRenderKit | grep -E '^[+-].*(isVisible|readiness|pageZoom|isReady)'`
  は **0 件**。`PageZoomProjector.swift` / `ViewerReadinessGate.swift` はこのブランチで
  1 コミットも触っていない。失敗したテストの本体も未変更（TASK-599 が同ファイルで
  変えたのは別テスト `:115` の 1 行）。
- ローカルでは同テストが 0.58 秒 × 3 回とも緑。CI は同じテスト 1 件に 127 秒。
  ランナーのログに `IOServiceMatching failed for: AppleM2ScalerParavirtDriver`。
- `ci.yml` は `BEFOLD_TEST_TIMEOUT_SECONDS` を build-and-test に 60、
  thread-sanitizer に 120 で設定しているが、**このスイートの自前ループだけがそれを読まず
  5 秒固定**だった。

## 修正が効くことの確認

`BEFOLD_TEST_TIMEOUT_SECONDS=0.05` で枯渇を再現すると、失敗が待機地点で報告される。

```
✘ ... recorded an issue at ViewerRendererZoomIntegrationTests.swift:38:36
  ↳ waitUntilOnMainActor が 0.05 seconds 以内に条件を満たさなかった
```

修正前はここが黙って素通りし、`applied == nil` として下流でしか出なかった（CI の症状と一致）。
通常予算では 4 tests 緑、`BEFOLD_TEST_TIMEOUT_SECONDS=60`（CI と同条件）の full suite で
1945 tests / 323 suites すべて成功。swiftlint 差分なし、swiftformat 変更なし。
<!-- SECTION:NOTES:END -->
