---
id: TASK-606
title: ViewerRendererZoomIntegrationTests の自前ポーリングが CI 予算を無視して間欠的に落ちる
status: Done
assignee: []
created_date: '2026-09-09 01:47'
updated_date: '2026-09-09 02:06'
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

`waitUntilReady` の自前ループと、裸のポーリング 2 箇所（`pageZoom.applied` /
`rendered.contentRevision`）を共有ヘルパー `waitUntilOnMainActor` へ置き換えた。
`befoldTests` から自前ポーリングは無くなり、予算は `BEFOLD_TEST_TIMEOUT_SECONDS`
（`ci.yml` が build-and-test に 60、thread-sanitizer に 120 を設定）へ追随する。

## 訂正: 5 秒予算は間欠失敗の原因ではなかった

着手時は「5 秒固定の自前ループが CI の 60 秒予算を読まないので枯渇している」と
判断したが、**これは誤りだった。** 修正を入れた CI 実行では、同じスイートが
**60 秒待っても準備完了に到達せず 4 件すべて失敗**した。予算の問題なら 60 秒で通る。

CI 4 回の実測（PR #643）:

| 実行 | コミット | 結果 |
|---|---|---|
| A | f33ff1ba | 1 件失敗（`applied == nil`） |
| A 再実行 | 同一 | 成功 |
| B | 本タスクの修正入り | **4 件すべて失敗**（60 秒で ready にならず） |
| B 再実行 | 同一 | 成功 |

**同一コミットが再実行で 2 回とも成功している。** 準備完了は「速く来る」か
「60 秒待っても来ない」かの二極で、遅いのではない。真因は別にあり、TASK-607 へ分けた。

## このタスクの修正が残す価値

原因ではなかったが、**失敗が読めるようになった**のは事実。修正前は待機が黙って
素通りするため、症状が下流の `applied == nil` としてしか出ず、待機が失敗している
ことが分からなかった。修正後の CI ログは待機地点を名指しする。

```
✘ ... at ViewerRendererZoomIntegrationTests.swift:38:36
  ↳ waitUntilOnMainActor が 60.0 seconds 以内に条件を満たさなかった
```

`BEFOLD_TEST_TIMEOUT_SECONDS=0.05` で枯渇を再現し、この形で落ちることを手元でも確認した。

## 検証

通常予算で 4 tests 緑。`BEFOLD_TEST_TIMEOUT_SECONDS=60`（CI と同条件）の full suite で
1945 tests / 323 suites すべて成功。swiftlint 差分なし、swiftformat 変更なし。
<!-- SECTION:NOTES:END -->
