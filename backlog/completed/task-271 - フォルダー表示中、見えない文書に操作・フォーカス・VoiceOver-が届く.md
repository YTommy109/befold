---
id: TASK-271
title: フォルダー表示中、見えない文書に操作・フォーカス・VoiceOver が届く
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-03 15:21'
updated_date: '2026-08-04 01:32'
labels:
  - bug
  - regression
  - accessibility
dependencies: []
priority: high
type: bug
ordinal: 462000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review high の指摘 3 件。いずれも TASK-266 で WKWebView を常駐させたことに由来する。TASK-266 では print / find / zoom だけを canOperateOnVisibleDocument で止めたが、残りの経路が空いている。

## 1. メニューコマンド（CONFIRMED）
toggleSourceView（ViewerWindowController.swift:741）・toggleLineNumbers（:745）・toggleBookmark（:749）はフォルダー一覧の表示中も有効のまま。押しても画面は変わらない（WebView は opacity 0）ので、ユーザーは繰り返し押す。その間 setSourceMode は saveScrollPositionBeforeTransition() と perFileState.sourceMode.setSourceMode(_, for: fileURL) を**前に開いていたファイル**に対して実行する。そのファイルを次に開くと、誤ったモードと壊れたスクロール位置で表示される。Cmd+D も見えていないファイルを黙ってブックマークする。

なお、ツールバーの操作は validateMenuItem を通らないため、同じ穴がもう 1 つある。

## 2. ファーストレスポンダ（PLAUSIBLE）
opacity(0) と allowsHitTesting(false) はキーボードのルーティングを止めない。文書内をクリックしてから二本指スワイプで戻る、またはメニューの「戻る」でフォルダー選択に切り替わると、矢印キー・Space・Page Down が画面にない文書をスクロールし、フォルダー一覧はキーボードで操作できない。Cmd+C も不可視の文書からコピーする。サイドバーへフォーカスを移す既存経路（FileListView.singleTapGesture → focusSidebarTable(), onSidebarDidReveal）はクリック起点のみ。

## 3. VoiceOver（PLAUSIBLE）
accessibilityHidden(true) は NSViewRepresentable のラッパーに付くが、WKWebView は AppKit/WebKit 側で独自のアクセシビリティ木を公開しており、この修飾子が必ずしも刈り取らない。VO カーソルが一覧を通り越して不可視の文書を読み上げる可能性がある。実機（VoiceOver 有効）での確認が必要。

## 方針
「見えている文書にだけ効かせる」判断は canOperateOnVisibleDocument に既に集約してある。メニュー・ツールバー双方の入口をそこへ寄せ、フォーカスとアクセシビリティは AppKit 側の手当て（フォルダー表示時に一覧へ makeFirstResponder、WebView 側の accessibilityElement 制御）を検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フォルダー一覧の表示中は、ソース表示・行番号・ブックマークがメニューでもツールバーでも実行されず、無効であることが見て分かる
- [x] #2 フォルダー表示へ切り替わったとき、キーボード操作の対象が一覧側に移る（矢印キー・Space が不可視の文書をスクロールしない）
- [x] #3 上記のガードを検証するテストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ADR 0002 の段 2（能力を状態から導出する関数へ集約）として実施する。調査で判明した追加事実: validateMenuItem を通らないコマンド経路が 4 本ある（ツールバーの view ベース項目 ViewerToolbarController.swift:76-94、オーバーフロー（»）メニュー :61-65、サイドバーの onKeyPress FileListView.swift:142、ツールバーのフィルタ/ソート/隠しファイル FileListView.swift:70-108）。TASK-266 で入れた canOperateOnVisibleDocument は validate 側にしかないため、これらは素通りする。導出関数へ集約する際に 4 本すべてを通すこと。

## 実装（2026-08-04・ADR 0002 段 2）

判断を ViewerCapabilities（提示状態と種別から導出する純粋な型）に集約し、validateMenuItem・ツールバーの applyState・WebViewCommandController のすべてがそこだけを見るようにした。条件を 1 箇所にしたので「メニューは無効なのに別経路では通る」が構造的に作れない。

- **実行側にもガードを置いた**: setSourceMode / toggleLineNumbers / toggleBookmark。validate を通らない経路（ツールバーの view ベースアイテム、オーバーフローメニュー）も必ずここを通るため。
- **ツールバーの push 漏れを塞いだ**: FileListModel.onPresentationTargetChange を新設し、選択・一覧の変化でツールバーを再同期する。従来 refreshToolbarState は明示呼び出しのみで、サイドバーの選択変更では走らなかった。
- **フォーカス**: フォルダー提示に切り替わったら fileListModel.focusSidebarTable() を呼ぶ。

## AX による実測（dev ビルド）
| ツールバー項目 | ファイル行選択中 | フォルダー行選択中 |
|---|---|---|
| 行番号を表示 | enabled | **DISABLED** |
| ソース | enabled | **DISABLED** |
| ブックマークする | enabled | **DISABLED** |
| プレビュー | DISABLED（.ts のため正しい） | DISABLED |

修正前はフォルダー行を選んでも 3 項目とも有効のままだった。

フォーカスは、フォルダー提示中に AXFocusedUIElement が「AXOutline サイドバー」であることを確認。ただし**指摘にあった前提（文書内にフォーカスがある状態）は再現できなかった**: 文書領域のクリックでも ⌘F でも、フォーカスは常にサイドバーの AXOutline のままだった。今回の focusSidebarTable 呼び出しは、その前提が成立する経路が将来できたときの保険として入れてある。

## テスト
- ViewerCapabilitiesTests（7 件）: 提示状態・種別・直接 HTML モードごとの導出規則
- ViewerWindowControllerPreviewTargetTests: フォルダー提示中に setSourceMode / toggleLineNumbers / toggleBookmark を直接呼んでも状態が変わらないこと
- WebViewCommandControllerTests: 能力が無ければ生きた WebView があってもコマンドが何もしないこと（従来の canOperateOnVisibleDocument ベースから置き換え）
- swift test 1027 tests green / swiftlint ベースライン差分ゼロ / xcodebuild 成功

## 残: AC #3（VoiceOver 実機確認）
AX ツリー上はフォルダー提示中に web area が現れない（webAreas=0）ことを確認済みで、VoiceOver はこの木を辿るため到達しない見込み。ただし VoiceOver を実際に有効化しての確認は未実施（読み上げが始まるため環境を占有する）。手元で VoiceOver を入れて確認いただくのが確実。

## AC #3 は TASK-277 へ分離（2026-08-04）
VoiceOver 実機確認（読み上げが始まり環境を占有するため未実施）を TASK-277 に切り出した。本タスクは実装・自動テスト・AX 実測をもって完了とする。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
フォルダー一覧の表示中に不可視の文書へ操作が届く問題を、能力判断を ViewerCapabilities（提示状態と種別から導出する純粋な型）へ集約して修正した。validateMenuItem・ツールバーの applyState・WebViewCommandController がすべて同じ導出結果だけを見るため、経路ごとの抜けが構造的に作れない。実行側（setSourceMode / toggleLineNumbers / toggleBookmark）にもガードを置き、validate を通らないツールバー・オーバーフローメニュー経路を塞いだ。フォルダー提示への切り替え時はサイドバーへフォーカスを移す。検証は ViewerCapabilitiesTests ほか swift test 1027 件 green、AX 実測でフォルダー行選択時にツールバー 3 項目が DISABLED・フォーカスが AXOutline であることを確認、swiftlint ベースライン差分ゼロ、xcodebuild 成功。VoiceOver 実機確認は TASK-277 へ分離。
<!-- SECTION:FINAL_SUMMARY:END -->
