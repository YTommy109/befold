---
id: TASK-337
title: ソース表示へ切り替えても差分が再取得されず表示されない問題を修正する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-06 05:34'
updated_date: '2026-08-06 06:03'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 506000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/diff_view のコードレビュー（多段検証付き、CONFIRMED）で検出。

refreshDiff の canToggleDiff ガード（ViewerWindowController+Diff.swift:22）は、rendered モードの .md/.svg/.html では false になり store.diffText を nil にする（ViewerStore.showsCodeContent が非 code 型では isSourceMode を要求するため）。一方、ソース表示への切り替え経路（setSourceMode/applySourceMode、ViewerWindowController.swift:660-682）は refreshToolbarState しか呼ばず、refreshDiff を呼ぶコードパスがない。

再現シナリオ: 差分表示 ON（dev ビルド）で変更済みの .md を開く → rendered モードなので gitStatusDidApply 起点の refreshDiff が毎回 diffText を nil にする → 「ソース表示」へ切り替えても差分オーバーレイが出ない。View メニューの「差分を表示」はチェック済みのまま。保存・ウィンドウ再フォーカス・.git/index 変化など無関係な契機が来るまで表示されない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 差分表示 ON の状態でソース表示へ切り替えた直後に差分が表示される
- [x] #2 モード切替で差分が再取得されることを検証する回帰テストがあり、修正を戻すと落ちる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. applySourceMode の呼び出し元を列挙し、絞り込み点を特定する（init / performFileSwitch / setSourceMode / resetSourceMode）。ファイルが変わらずモードだけ変わるのは setSourceMode のみ。
2. setSourceMode でモードが実際に変わったときに refreshDiff() を呼ぶ。performFileSwitch は URL 更新前に applySourceMode を呼ぶため、そちらへ入れると旧 URL で git を起こす無駄が出る。
3. ソース表示へ切り替えた契機で差分が取り直されることを検証する回帰テストを追加し、修正を戻すと落ちることを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査: applySourceMode の呼び出し元は init / performFileSwitch / setSourceMode / resetSourceMode の 4 つ。このうち「ファイルが変わらずモードだけ変わる」のは setSourceMode だけで、そこが絞り込み点だった。performFileSwitch は applyURLToWindow の前に applySourceMode を呼ぶため、applySourceMode 側へ置くと切替前ファイルに対して git diff を起こす無駄が出る(TASK-338 が扱う stale fileType 問題と同型の無駄)。よって setSourceMode に置き、モードが実際に変わったときだけ呼ぶ。

実装: setSourceMode で didChange を 1 度だけ計算し(saveScrollPositionBeforeTransition の条件と共用)、モード変更後に refreshDiff() を呼ぶ。

検証:
- 回帰テスト ViewerWindowControllerDiffTests.refreshesDiffWhenSwitchingToSourceMode を追加。レンダリング表示の .md で canToggleDiff が false・取得ゼロであることを前提として固定し、setSourceMode(true) 後に取得が 1 回起きることを RecordingDiffReader で測る。
- 修正を戻すと当該テストが失敗する(callCount が 0 のままタイムアウト)ことを実測で確認済み。
- テスト作成時、既定の索引が /mock 配下でリポジトリルートを返さず取得へ到達しない空振りを踏んだため、SlowRootGitFileIndex(delay: 0) を注入して実際に取得経路まで届くようにした。
- swift test: 1168 tests / 173 suites すべて成功。
- swiftlint: main ベースラインに対する新規警告ゼロ(既存の file_length が 894→904 行に増えたのみ)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ソース表示への切り替えで差分を取り直すようにした。canToggleDiff は表示モードに依存するため、レンダリング表示中の refreshDiff は diffText を捨てる一方、モード切替には取り直しの契機が無かった。呼び出し元を列挙して「ファイルが変わらずモードだけ変わる」絞り込み点が setSourceMode だけであることを確かめ、そこでモードが実際に変わったときだけ refreshDiff() を呼ぶ。回帰テストを追加し、修正を戻すと落ちることを実測で確認。swift test 1168 件成功、swiftlint 新規警告ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
