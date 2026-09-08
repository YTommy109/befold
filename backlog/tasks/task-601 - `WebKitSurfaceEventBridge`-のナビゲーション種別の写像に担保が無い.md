---
id: TASK-601
title: '`WebKitSurfaceEventBridge` のナビゲーション種別の写像に担保が無い'
status: To Do
assignee: []
created_date: '2026-09-08 14:17'
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
- [ ] #1 `WebKitSurfaceEventBridge` が `.linkActivated` / `.other` / それ以外（reload・backForward・formSubmitted）を .linkActivated / .programmatic / .otherInteraction へ写すことを見るテストがある
- [ ] #2 `DirectHTMLModeController.decidePolicy` の 3 分岐を `SurfaceNavigationRequest` の値で直接見るテストがある（実 WKWebView を作らない）
- [ ] #3 写像を 2 値へ潰すと落ちることを、修正を戻して確認してある
<!-- AC:END -->
