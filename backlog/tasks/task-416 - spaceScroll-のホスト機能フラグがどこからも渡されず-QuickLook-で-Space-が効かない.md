---
id: TASK-416
title: spaceScroll のホスト機能フラグがどこからも渡されず QuickLook で Space が効かない
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 07:28'
updated_date: '2026-08-10 15:58'
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
- [x] #1 quickLookRestricted のとき window._mmdHostFeatures.spaceScroll が false になる
- [ ] #2 QuickLook プレビューで Space を押すとプレビューが閉じる（ページスクロールしない）
- [x] #3 本体アプリでは従来どおり Space でページスクロールする
- [x] #4 hostFeaturesScript のデフォルト引数を撤去し、呼び出し側が必ず 3 つとも渡す形にする
- [x] #5 ユニットテストで ON/OFF 両方向を押さえる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. RendererFeatures に computed property allowsSpaceScroll を足す（新しい stored state は増やさず allowsInteractiveBridging から導出。1 回描画の静的プレビューでは Space はホストの閉じるジェスチャ、という意味づけを doc に書く）
2. ViewerBridge.hostFeaturesScript のデフォルト引数 3 つを撤去し、呼び出し側に全指定を強制する
3. ViewerRenderer.makeWebView の唯一の production 呼び出しで spaceScroll: rendererFeatures.allowsSpaceScroll を渡す
4. テスト: RendererFeaturesTests に allowsSpaceScroll の ON/OFF、ViewerBridgeTests のデフォルト依存テストを明示指定へ書き換え、生成スクリプトが spaceScroll:false/true 両方向を含むことを押さえる
5. swift build / swift test / swiftformat・swiftlint 差分ゼロを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-11）

単純化の検討: 新しい stored flag を RendererFeatures に足す案と、既存の allowsInteractiveBridging から導出する案を比較し、後者を採用。QuickLook で Space を抑止したい理由（1 回描画の静的プレビューでホストに操作を委ねる）は allowsInteractiveBridging の判定軸と同一のため、状態を増やさず computed property allowsSpaceScroll として意味づけだけ与えた（BefoldKit/RendererFeatures.swift:16-26）。

- ViewerBridge.hostFeaturesScript のデフォルト引数 3 つを撤去（BefoldKit/ViewerBridge.swift:295）。指定漏れが黙って「全機能有効」に落ちる構造そのものを消した。
- 唯一の production 呼び出し（BefoldRenderKit/ViewerRenderer.swift:223-227）で spaceScroll: rendererFeatures.allowsSpaceScroll を渡す。

検証（実測）:
- swift test: 1394 tests / 203 suites すべて成功
- swiftformat --lint: 0 files require formatting
- swiftlint（変更 5 ファイル）: 指摘 0 件

AC #2 は未チェック。QuickLook 拡張を Finder 上で操作する実測が必要で、自動テストでは Space 押下→プレビューが閉じる、という OS 側の挙動まで再現できない。コード上の経路は viewer-main.js:185 が spaceScroll=false で早期 return し preventDefault しない、という形で塞がっており、注入値が false になることは RendererFeaturesTests の makeWebViewInjectsSpaceScrollFlag で担保済み。dev ビルドの dogfood で確認したい。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
hostFeaturesScript のデフォルト引数を撤去し、spaceScroll を RendererFeatures.allowsSpaceScroll（allowsInteractiveBridging からの導出）で必ず渡す形にした。AC #1/#3/#4/#5 は swift test 1394 件成功（makeWebViewInjectsSpaceScrollFlag が quickLookRestricted→false / allEnabled→true を実測）で確認。AC #2 のみ QuickLook 実機操作が要るため dev ビルドの dogfood 待ち（プロジェクトのテスト規約どおり GUI 層はリリース前手動チェック）。
<!-- SECTION:FINAL_SUMMARY:END -->
