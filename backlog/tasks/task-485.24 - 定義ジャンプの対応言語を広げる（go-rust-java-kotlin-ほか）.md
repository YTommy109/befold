---
id: TASK-485.24
title: 定義ジャンプの対応言語を広げる（go / rust / java / kotlin ほか）
status: To Do
assignee: []
created_date: '2026-08-23 16:35'
labels:
  - jump
dependencies: []
parent_task_id: TASK-485
ordinal: 798000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

TASK-485.4 で入れた定義ジャンプの対応言語は swift / python / javascript / typescript の 4 つ（`FunctionJumpLanguages.supported` と JS の `FUNCTION_JUMP_LANGUAGES`）。同梱 highlight.js は common ビルドで 36 言語を扱う（`viewer-src/vendor.ts:19`）ため、残りの言語では機能が無効になっている。

ADR 0009 の方式なら**言語ごとに正規表現を 1 本足すだけ**で広げられる（コメント・文字列の除外は highlight.js が持つので言語ごとに書かない）。

## 注意

言語を足すときは Swift と JS の両方に足す。片方だけだと `ViewerFunctionJumpLanguageContractTests` が落ちる（そのための契約テスト）。`ViewerFunctionJumpLanguageContractTests.sampleExtensions` にも拡張子を 1 つ足す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 追加した各言語で定義が拾えることを実 hljs 出力に対するテストで示している
- [ ] #2 追加した各言語でコメント・文字列内の紛らわしい行を誤検出しないことをテストで示している
- [ ] #3 Swift 側 FunctionJumpLanguages.supported と JS 側 FUNCTION_JUMP_LANGUAGES の両方が更新され、契約テストが通る
<!-- AC:END -->
