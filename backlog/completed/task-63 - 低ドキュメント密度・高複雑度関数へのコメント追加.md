---
id: TASK-63
title: 低ドキュメント密度・高複雑度関数へのコメント追加
status: Done
assignee:
  - '@claude'
created_date: '2026-07-18 23:57'
updated_date: '2026-07-19 01:46'
labels: []
dependencies: []
references:
  - dagayn refactor_tool(mode=suggest)による2026-07-19レビュー
priority: low
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
dagayn の refactor_tool(mode=suggest) が document 候補として、説明密度が低く複雑度が高い3関数を挙げた: BefoldKit/Resources/viewer.js::tokenizeCsvRows、befold/App/MainMenuBuilder.swift::makeEditMenuItem、makeViewMenuItem(いずれも分岐/協調呼び出しが多い)。各関数の非自明な意図・前提条件を短いコメントで補足する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 viewer.js の tokenizeCsvRows に、CSVトークナイズの前提(クォート処理方針等)を説明する短いコメントが追加されている
- [x] #2 MainMenuBuilder.makeEditMenuItem に、メニュー項目構成の意図を説明する短いコメントが追加されている
- [x] #3 MainMenuBuilder.makeViewMenuItem についても同様にコメントが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. dagayn が挙げた3関数を確認する。
2. viewer.js::tokenizeCsvRows: 既に関数直前にRFC4180準拠・value/raw分離のブロックコメントあり。追加でクォート内エスケープ()・\r\n連続改行・末尾行確定条件など非自明な分岐にインラインコメントを補う。
3. MainMenuBuilder.makeEditMenuItem: 既存の関数コメントに、undo:/redo:が文字列セレクタである理由・Find系がWebView内蔵検索へ委譲される点を補足。redo/findPreviousの修飾キー重複の意図も一言添える。
4. MainMenuBuilder.makeViewMenuItem: 関数コメントが無かったため新設。個別項目のkeyEquivalentModifierMask上書き(toggleSidebarの明示化、toggleHiddenFilesのHide衝突回避、fullScreenの標準ショートカット踏襲)に理由コメントを追加。
5. コメントのみの変更のため、swift build/test・npm test(jest, viewer.test.js)・webview-smoke.swiftで既存動作に影響がないことを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容

- BefoldApp/BefoldKit/Resources/viewer.js::tokenizeCsvRows: エスケープされたクオート("")の判定、クオート内でデリミタ/改行を通常文字として蓄積する理由、\r\nの連続改行を1つとして扱う先読み、末尾行を二重pushしないための条件、にそれぞれインラインコメントを追加(既存の関数直前ブロックコメントはRFC4180準拠・value/raw分離の説明として温存)。
- BefoldApp/befold/App/MainMenuBuilder.swift::makeEditMenuItem: 既存コメントにFind系がWKWebView内蔵検索バーへ委譲される旨を追記。undo:/redo:が文字列セレクタになる理由(#selectorでチェックできる宣言が存在しないため)、redo/findPreviousの修飾キー重複(shiftで方向/種別を区別)にコメントを追加。
- BefoldApp/befold/App/MainMenuBuilder.swift::makeViewMenuItem: 関数コメントを新設(メニュー構成の意図+個別項目の修飾キー上書きは各所コメント参照、と誘導)。toggleSidebarの修飾キー明示化、toggleHiddenFilesがApp メニューのHide(⌘H)と衝突しないよう⌃を重ねている点、fullScreenがmacOS標準ショートカット(⌃⌘F)に合わせている点、にコメントを追加。

## 検証
- swift build: 成功
- swift test --skip Integration --skip FileWatcherTests: 386 tests 全通過
- npm test(jest, viewer.test.js): 203 tests 全通過(ロジック変更なし、コメントのみ)
- swift scripts/webview-smoke.swift: PASS(CSP・mmd/md描画・外部画像ブロック・PDF blob表示)
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
3関数(viewer.js::tokenizeCsvRows、MainMenuBuilder.makeEditMenuItem/makeViewMenuItem)に非自明な意図・前提条件を説明する短いコメントを追加した。CSVトークナイザーはエスケープされたクオート判定・クオート内での改行/デリミタ蓄積・\r\n先読み・末尾行の二重push防止を補足。MainMenuBuilderの2関数はメニュー構成意図と修飾キー上書きの理由(標準ショートカットとの衝突回避等)を補足。コメントのみの変更で、swift build/test(386件)・npm test(jest 203件)・webview-smoke.swiftすべて既存どおり通過することを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
