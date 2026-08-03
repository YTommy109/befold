---
id: TASK-271
title: フォルダー表示中、見えない文書に操作・フォーカス・VoiceOver が届く
status: In Progress
assignee:
  - '@Tommy109'
created_date: '2026-08-03 15:21'
updated_date: '2026-08-03 15:46'
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
- [ ] #1 フォルダー一覧の表示中は、ソース表示・行番号・ブックマークがメニューでもツールバーでも実行されず、無効であることが見て分かる
- [ ] #2 フォルダー表示へ切り替わったとき、キーボード操作の対象が一覧側に移る（矢印キー・Space が不可視の文書をスクロールしない）
- [ ] #3 VoiceOver を有効にした実機で、フォルダー表示中に不可視の文書が読み上げられないことを確認する
- [ ] #4 上記のガードを検証するテストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ADR 0002 の段 2（能力を状態から導出する関数へ集約）として実施する。調査で判明した追加事実: validateMenuItem を通らないコマンド経路が 4 本ある（ツールバーの view ベース項目 ViewerToolbarController.swift:76-94、オーバーフロー（»）メニュー :61-65、サイドバーの onKeyPress FileListView.swift:142、ツールバーのフィルタ/ソート/隠しファイル FileListView.swift:70-108）。TASK-266 で入れた canOperateOnVisibleDocument は validate 側にしかないため、これらは素通りする。導出関数へ集約する際に 4 本すべてを通すこと。
<!-- SECTION:NOTES:END -->
