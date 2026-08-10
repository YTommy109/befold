---
id: TASK-416
title: spaceScroll のホスト機能フラグがどこからも渡されず QuickLook で Space が効かない
status: To Do
assignee: []
created_date: '2026-08-10 07:28'
updated_date: '2026-08-10 13:52'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 102000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerBridge.hostFeaturesScript(loadMore:spaceScroll:referenceActivation:)（ViewerBridge.swift:293）は spaceScroll を「Space キーでのページスクロール可否」と定義し、viewer-main.js:185 が実際に見ている（`if (e.key === " " && !isHostFeatureEnabled(window._mmdHostFeatures, "spaceScroll")) { return; }`）。

ところが唯一の production 呼び出し（ViewerRenderer.swift:211）は loadMore: と referenceActivation: の 2 引数しか渡さず、spaceScroll はデフォルト値 true に落ちる。rendererFeatures == .quickLookRestricted（PreviewViewController.swift:26）でも true のままなので、抑止は一度も効いていない。

影響: Finder の QuickLook で .md をプレビューし、WKWebView にキーフォーカスが移った状態で Space を押すと、_mmdInitKeyboard のハンドラが e.preventDefault() してページスクロールしてしまい、QuickLook を閉じる標準ジェスチャが効かない。

デフォルト引数が穴を隠している典型で、CLAUDE.md の「デフォルト引数をやめて必須引数にする（破りようのない構造）」がそのまま当てはまる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 quickLookRestricted のとき window._mmdHostFeatures.spaceScroll が false になる
- [ ] #2 QuickLook プレビューで Space を押すとプレビューが閉じる（ページスクロールしない）
- [ ] #3 本体アプリでは従来どおり Space でページスクロールする
- [ ] #4 hostFeaturesScript のデフォルト引数を撤去し、呼び出し側が必ず 3 つとも渡す形にする
- [ ] #5 ユニットテストで ON/OFF 両方向を押さえる
<!-- AC:END -->
