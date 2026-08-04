---
id: TASK-33
title: ViewerStore.openFile() の filePath/fileType を content と同時に一括適用する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-16 14:24'
updated_date: '2026-07-16 14:37'
labels: []
dependencies: []
priority: high
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
task-32 の調査で判明した根本原因の修正。ViewerStore.openFile() は filePath/fileType を同期即時更新するが、content/contentRevision は非同期の loadContent()→apply() 完了まで前ファイルのまま据え置かれる。この不整合ウィンドウ中に ViewerWebView.Coordinator が '新fileType + 前ファイルのcontent' という中間状態を描画してしまい、画像ファイルから巨大な行指向ファイル(SJIS CSV等)へ切り替えた際に前ファイルのbase64画像文字列が一瞬誤表示される(task-32参照)。filePath/fileType の更新を openFile() の即時代入からやめ、既存の一括適用箇所である apply()(ViewerStore.swift:293-331)内で content/contentRevision と同時に更新するよう変更し、表示状態を単一のアトミックな単位として扱う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 openFile() 呼び出し直後、apply() が完了するまで store.fileType が前ファイルの値のままである(filePath/fileType が content/contentRevision と同時にのみ変化する)
- [x] #2 画像ファイル→巨大な行指向ファイルへの切替で、旧ファイルのcontentと新ファイルのfileTypeが組み合わさって描画される中間状態が発生しないことをテストで確認できる
- [x] #3 既存のViewerStoreTests/ViewerStoreIntegrationTests/ViewerWebViewCoordinatorTestsが全て通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装内容
ViewerStore.openFile()/handleRename() で fileType の即時代入をやめ、新しい private
@ObservationIgnored プロパティ pendingFileType へ代入するよう変更した(ViewerStore.swift)。
pendingFileType は loadContent() が computeLoad へ渡す fileType の元になり、
performLoad → apply(_:fileType:) を経由して、公開の fileType プロパティは
apply() 内で content/contentRevision と同時にのみ更新されるようにした。

filePath は据え置き(引き続き openFile()/handleRename() で即時更新)。理由:
- ViewerWebView.Coordinator の再描画判定(needsRender)は fileType の変化のみを見ており、
  filePath 単独の変化では再描画がトリガーされないため、task-32 のバグには filePath は関与しない。
- scheduleFileGone のグレース期間チェックや handleRename の rename/削除競合対応は、
  filePath が常に「現在監視中のファイル」を即時に指していることに依存しているため
  (ViewerStore.swift:340-342 のコメント参照)、ここを遅延させると別の競合を生む。
必要最小限の変更に留める単純化の観点から、fileType のみを遅延対象とした。

## テスト(TDD)
task-32 の再現条件を再現する失敗テストを先に追加(ViewerStoreFileGoneTests.swift の
ViewerStoreLoadRaceTests に「画像→巨大CSVへの切替では、読み込み完了まで旧ファイルの
fileType/content が保たれる(task-32)」を追加)。修正前に red、修正後に green を確認した。

副作用として ViewerWindowControllerToolbarTests.swift の「行番号アイテムはコード表示中のみ有効」が
fileType の即時更新に暗黙に依存していたため red になった。これは store.onContentReloaded による
toolbar 更新を待たずに同期的に検証していたテスト側の前提が誤りだったための失敗であり、
読み込み完了を待つよう async 化して修正した(製品コード側の追加変更は不要)。

## 検証結果
swift test (フィルタなし、全 346 tests / 46 suites) が全て pass。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
task-32 で特定した根本原因(ViewerStore.openFile() が fileType を即時更新する一方 content が
非同期完了まで前ファイルのまま据え置かれる不整合)を修正した。fileType の即時代入をやめ、
新設した非公開の pendingFileType を loadContent()→performLoad()→apply(_:fileType:) へ通し、
公開の fileType は apply() 内で content/contentRevision と同時にのみ更新するよう変更した
(ViewerStore.swift)。filePath は Coordinator の再描画判定に影響せず、
scheduleFileGone/handleRename が即時性に依存しているため据え置いた(最小限の変更)。

TDD で task-32 の再現条件(画像→巨大CSVへの切替)を再現する失敗テストを先に追加し、
修正で green になることを確認した(ViewerStoreFileGoneTests.swift)。
副作用で red になった ViewerWindowControllerToolbarTests.swift のテストは、
読み込み完了(onContentReloaded)を待たない誤った前提だったため async 化して修正した。

検証: swift test(フィルタなし、346 tests / 46 suites)が全て pass。
<!-- SECTION:FINAL_SUMMARY:END -->
