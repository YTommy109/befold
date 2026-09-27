---
id: TASK-485.24
title: 定義ジャンプの対応言語を広げる（go / rust / java / kotlin ほか）
status: Done
assignee:
  - '@claude'
created_date: '2026-08-23 16:35'
updated_date: '2026-09-25 13:39'
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

ADR 0011 の方式なら**言語ごとに正規表現を 1 本足すだけ**で広げられる（コメント・文字列の除外は highlight.js が持つので言語ごとに書かない）。

## 注意

言語を足すときは Swift と JS の両方に足す。片方だけだと `ViewerFunctionJumpLanguageContractTests` が落ちる（そのための契約テスト）。`ViewerFunctionJumpLanguageContractTests.sampleExtensions` にも拡張子を 1 つ足す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 追加した各言語で定義が拾えることを実 hljs 出力に対するテストで示している
- [x] #2 追加した各言語でコメント・文字列内の紛らわしい行を誤検出しないことをテストで示している
- [x] #3 Swift 側 FunctionJumpLanguages.supported と JS 側 FUNCTION_JUMP_LANGUAGES の両方が更新され、契約テストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 実 hljs 出力に対するテストを go / rust / java / kotlin で「拾う」「コメント・文字列内を拾わない」の 2 本ずつ足す
2. DEFINITION_PATTERNS に 4 言語の正規表現を 1 本ずつ足し、FUNCTION_JUMP_LANGUAGES と FunctionJumpLanguages.supported の両方へ追加する
3. 契約テストの sampleExtensions に go / rs / java / kt を足し、viewer-ui.md の対応言語を更新する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
範囲: 題にある go / rust / java / kotlin の 4 言語に絞った。ruby は Swift 側のテスト（ViewerCapabilitiesTests / ViewerMenuValidatorTests）が「非対応言語」の代表として 5 箇所で使っており、足すならそれらの置き換えが要る。C / C++ / C# / PHP ほかは戻り値型や修飾が行頭に来て錨を下ろしにくく、言語ごとに判断が要るため今回は入れていない。
方式: ADR 0011 どおり、言語ごとに正規表現を 1 本足しただけ。コメント・文字列の除外は既存の codeTextOf（hljs スパン）に任せており、言語別の規則は書いていない。単純化の余地: Java だけはキーワードで錨を下ろせないため「型 名前(」の形 + 型位置の予約語の否定先読み + 大文字始まりのコンストラクタで拾う形になった。他 3 言語はキーワード錨で済んだ。
空振りの確認（実測）: (a) codeTextOf のスパン除外を無効化すると、新規の除外テスト 4 本（Go / Rust / Java / Kotlin）を含む 7 本が落ちる。(b) FUNCTION_JUMP_LANGUAGES から 4 言語を外すと新規 8 本すべてが落ちる。
検証: jest 674 件すべて通過、swift test --skip Integration --skip FileWatcherTests 1878 件と 66 件がすべて通過（ViewerFunctionJumpLanguageContractTests を含む）、swiftlint は main 46 件 / 作業ツリー 46 件で新規 0。swiftformat の変更なし。
現在の仕様への反映: docs/dev/viewer-ui.md の対応言語の表と本文を 8 言語に更新した。native-app-design.md は型の追加・変更が無いので更新不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
定義ジャンプの対応言語に go / rust / java / kotlin を追加した（計 8 言語）。viewer-src/jump-providers.ts の DEFINITION_PATTERNS に言語ごとの正規表現を 1 本ずつ足し、FUNCTION_JUMP_LANGUAGES と FunctionJumpLanguages.supported の両方を更新した。コメント・文字列の除外は既存の hljs スパン判定のままで、言語別の規則は足していない。テストは実 hljs 出力に対し、言語ごとに「定義を拾う（修飾子・注釈・レシーバ・コンストラクタを含み、呼び出しや制御構文を拾わない）」と「ブロックコメント・生文字列／テキストブロック内を拾わない」の 2 本ずつ。ruby と C 系ほかは今回の範囲外（理由は Notes）。
<!-- SECTION:FINAL_SUMMARY:END -->
