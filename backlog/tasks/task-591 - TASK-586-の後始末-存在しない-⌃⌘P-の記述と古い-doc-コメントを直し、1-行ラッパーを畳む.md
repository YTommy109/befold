---
id: TASK-591
title: 'TASK-586 の後始末: 存在しない ⌃⌘P の記述と古い doc コメントを直し、1 行ラッパーを畳む'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-05 02:48'
updated_date: '2026-09-08 10:36'
labels:
  - sidebar
dependencies: []
priority: low
type: chore
ordinal: 856000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-586 の実装後レビューで見つかった、動作に影響しない取りこぼし。

- ~~スライドモードの ⌃⌘P という存在しないショートカットの記述~~ → TASK-593.1 で該当 doc ごと解消済み（`ViewerWindowController+FileList.swift` は「メニュー(⌃⌘T ほか)」へ、`FileListViewDelegate.swift` の `SidebarDisplayRequest` は列挙ごと撤去）。
- `ViewerWindowController+FileList.swift` の extension ヘッダーが「行操作の受け先」のままで、同 extension が `fileListDidRequestDisplayChange(_:)` も実装するようになったことを反映していない（`FileListView.swift` 側は更新済み）。
- `ViewerWindowAssembler.makeFileListView(for:)` はクロージャ撤去後、`FileListView(model:delegate:)` を返すだけの単一式で呼び出し元 1 箇所。doc コメントはもうやっていないことを説明し、ファイルヘッダーの「生成物のクロージャがコントローラを弱参照で捕捉するための make* ヘルパー」という根拠も当てはまらない。

/code-review high（2026-09-05）の指摘。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `ViewerWindowController+FileList.swift` の extension ヘッダーが行操作と表示切り替えの両方を受けることを述べている
- [x] #2 `makeFileListView` が無くなり、呼び出し元で `FileListView(model:delegate:)` を直接組んでいる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerWindowController+FileList.swift の extension doc を「行操作と表示切り替えの受け先」へ更新
2. ViewerWindowAssembler.makeFileListView を撤去し、makeSplitViewController の呼び出し元で FileListView(model:delegate:) を直接組む
3. swift build / swift test / swiftlint ベースライン差分ゼロを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#1: ViewerWindowController+FileList.swift の extension doc を「行操作と表示切り替えの受け先」へ更新。
AC#2: ViewerWindowAssembler.makeFileListView を撤去し、makeSplitViewController 内で FileListView(model: controller.fileListModel, delegate: controller) を直接組む形にした。rg 'makeFileListView' の Swift ヒットは 0 件。

ファイルヘッダーの「コントローラを引数で受ける関数は、生成物のクロージャがコントローラを弱参照で捕捉するためのもの」という根拠は撤去で成立に戻ったため、ヘッダー自体は変更していない（残る controller 受け取り関数 makeSidebarDidHide / wireEventMonitors / wirePresentationTargetChange / wireStoreCallbacks はいずれも弱キャプチャのクロージャを作る）。

⌃⌘P の記述は Description のとおり TASK-593.1 で解消済みのため作業なし。native-app-design.md への追随は不要（makeFileListView は同文書に登場せず、残る言及は docs/superpowers/plans のスナップショットと完了済みタスクのみ）。

検証: swift build 成功 / swift test 1914 tests・313 suites すべて成功 / swiftlint 51 件（変更した 2 ファイルの指摘は 0 件、main とのベースライン差分なし）/ check-doc-symbols.sh・check-doc-citations.sh いずれも指摘なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TASK-586 の後始末として、ViewerWindowController+FileList.swift の extension doc を表示切り替えも受ける実態へ更新し、単一式の 1 行ラッパー ViewerWindowAssembler.makeFileListView を撤去して呼び出し元で FileListView(model:delegate:) を直接組むようにした。swift build / swift test (1914 tests) / swiftlint ベースライン差分ゼロ / doc チェック 2 種で検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
