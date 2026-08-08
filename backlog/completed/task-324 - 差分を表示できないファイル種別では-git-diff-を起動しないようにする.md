---
id: TASK-324
title: 差分を表示できないファイル種別では git diff を起動しないようにする
status: Done
assignee: []
created_date: '2026-08-05 16:09'
updated_date: '2026-08-06 04:27'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: low
type: chore
ordinal: 511000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

ViewerWindowController+Diff.swift:18 の refreshDiff は、表示中コンテンツが差分を表示し得る種別かどうか（capabilities.canToggleDiff / showsCodeContent）で絞らずに毎回 git diff を起動する。変更ありのトラッキング済み PNG や PDF を表示していると、コンテンツリロードのたびに描画されることのない diff のためにサブプロセスが起動され、結果は常に破棄される。

修正: refreshDiff の入口で表示種別を判定し、差分を表示できない種別では フェッチをスキップ（かつ diffText をクリア）する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 画像・PDF 表示中のコンテンツリロードで git diff サブプロセスが起動しない
- [x] #2 差分を表示できる種別（ソースコード等）の挙動は変わらない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
コードレビュー(2026-08-06, high)で CONFIRMED として再検出。canToggleDiff は CSV/TSV のソース表示で true になる（showsCodeContent が isSourceMode で true, ViewerStore.swift:167）が、_renderDiffHtmlIfAvailable（viewer-main.js:1714）は type === "csv" で空文字を返す。結果、⌘D はチェックだけ付いて表示は変わらず、保存のたびに git rev-parse / git diff / git ls-files が走る。

実装: 課題の前半(画像・PDF)は TASK-315 レビュー修正時点で refreshDiff の capabilities.canToggleDiff ガードにより既に解消済みだった(ViewerWindowController+Diff.swift:27)。残っていたのは Notes 記載の CSV/TSV。

単純化の検討: refreshDiff の入口へ種別判定を足すのではなく、既にある絞り込み点(canToggleDiff)を正しくした。⌘D のチェック表示・メニュー有効判定・取得ガードが同じ値を見るため、分岐は増えない。

- FileType.supportsDiffDisplay を追加(.csv のみ false)。viewer-main.js の _renderDiffHtmlIfAvailable が type === 'csv' で空を返す事実に対応。
- ViewerCapabilities.init に supportsDiffDisplay を必須引数で追加(既定値なし = 配線漏れがコンパイルエラーになる)。canToggleDiff = isPresentingDocument && showsCodeContent && supportsDiffDisplay。
- ViewerWindowController.capabilities から store.fileType.supportsDiffDisplay を配線。

検証(実測):
- swift test --skip Integration --skip FileWatcherTests → 1071 tests / 150 suites 全通過。
- canToggleDiff から && supportsDiffDisplay を外して再実行すると、新規テスト 2 件が落ちることを確認(ViewerCapabilitiesTests『差分は種別が差分表示に対応しているときだけ切り替えられる』、ViewerWindowControllerDiffTests『CSV のソース表示では差分を取得しない』= reader.callCount 0 と diffText nil を測る)。
- swiftlint: 変更 4 ファイルに新規警告なし(既存の file_length 等のみ)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
差分を描けない種別で git を起こさない絞り込みを canToggleDiff に集約した。画像・PDF は既存ガードで解消済みだったため、残る CSV/TSV を FileType.supportsDiffDisplay として ViewerCapabilities へ配線。CSV のソース表示で GitDiffReader が 1 回も呼ばれないこと・修正を戻すと該当テストが落ちることを swift test で実測。
<!-- SECTION:FINAL_SUMMARY:END -->
