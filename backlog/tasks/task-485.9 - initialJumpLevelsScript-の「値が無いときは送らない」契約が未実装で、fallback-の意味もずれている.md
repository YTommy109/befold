---
id: TASK-485.9
title: initialJumpLevelsScript の「値が無いときは送らない」契約が未実装で、fallback の意味もずれている
status: Done
assignee: []
created_date: '2026-08-17 14:03'
updated_date: '2026-08-18 05:13'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
priority: low
type: task
ordinal: 751000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘、verdict: CONFIRMED）

`ViewerBridge.initialJumpLevelsScript`（`BefoldApp/BefoldKit/ViewerBridge.swift:297`）の doc コメントは「値が無いときはこのスクリプト自体を送らない — QuickLook など」と述べるが、未実装。`Options.headingJumpLevels` は非 optional（`ViewerWebViewFactory.swift:17`）で `ViewerRenderer.makeWebView` が `.default` を既定値にする（`ViewerRenderer.swift:163`）ため、QuickLook（`OneShotRenderer.swift:123`）も常にスクリプトを受け取り、「未設定」状態は表現不能。

さらに `assignGlobalScript(fallback: "[]")`（`ViewerBridge.swift:298`）のエンコード失敗時 fallback は「ユーザーが 3 レベル全部を OFF にした」の意味になる。`jump-providers.ts:166-177` は配列なら空配列でもユーザー状態として扱い、非配列のときだけ `HEADING_LEVELS` の既定へフォールバックするため、エンコード失敗が黙って「見出しターゲット 0 件」へ縮退する。今日は `.default` のエンコードが必ず成功するため無害。

## 方針

どちらかに整合させる: (a) option を optional 化し、nil ならスクリプトを送らない（doc コメントどおりの実装）、(b) doc コメントを実態へ直し、fallback を非配列値にして既定へ落ちるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 doc コメントと実装が一致している（未設定時の挙動が表現どおり）
- [x] #2 エンコード失敗時の fallback が「全 OFF」ではなく既定（HEADING_LEVELS）へ落ちる
- [x] #3 選んだ方針と理由を Implementation Notes に記録する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針 (b) を採用（doc コメントを実態へ合わせ、fallback を既定へ落とす）。理由: (a) は option を optional 化して「未設定」という状態を新設するが、JS 側 (_mmdInitHeadingLevels) は既に非配列を「既定の 3 レベル」として扱うため、.default を渡すことと意味が同じ。状態を増やさず既存の縮退経路へ合流できる (b) が単純。

変更点:
- ViewerBridge.initialJumpLevelsScript: doc コメントを「常に注入する / 保存値を持たない呼び出し側は .default を渡す」へ修正。fallback を "[]" から defaultingFallback (null) へ。
- scalarFallback を defaultingFallback へ改名し、配列でも空配列を使わない理由をコメント化。
- ViewerRenderer.makeWebView の headingJumpLevels の doc に QuickLook 等の扱いを追記。

テスト: ViewerBridgeJumpLevelsTests (保存値・空配列がそのまま注入される) と viewer-main-jump.test.js の「null が注入されたら既定の 3 つとも ON」。エンコード失敗そのものは [String] では到達不能なため、契約は「null → 既定」の JS 側で固定した。

検証: swift test 1637 passed / npx jest 521 passed / swiftlint 54 件（ベースラインと同数、差分ゼロ）/ swiftformat --lint 0 件 / npm run lint・format:check クリーン。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
initialJumpLevelsScript の doc コメントと実装のずれを方針 (b) で解消した。スクリプトは常に注入する旨へ doc を修正し、エンコード失敗時の fallback を "[]"（全 OFF の意味）から null（既定の 3 レベルへ落ちる）へ変更。Swift 側の注入内容と JS 側の null→既定の契約をテストで固定し、swift test 1637 / jest 521 で確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
