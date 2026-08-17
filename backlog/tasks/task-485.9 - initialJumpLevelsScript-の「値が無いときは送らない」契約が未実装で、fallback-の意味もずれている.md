---
id: TASK-485.9
title: initialJumpLevelsScript の「値が無いときは送らない」契約が未実装で、fallback の意味もずれている
status: To Do
assignee: []
created_date: '2026-08-17 14:03'
labels: []
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
- [ ] #1 doc コメントと実装が一致している（未設定時の挙動が表現どおり）
- [ ] #2 エンコード失敗時の fallback が「全 OFF」ではなく既定（HEADING_LEVELS）へ落ちる
- [ ] #3 選んだ方針と理由を Implementation Notes に記録する
<!-- AC:END -->
