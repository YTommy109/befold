---
id: TASK-368
title: .code ファイルで選択済み source セグメント操作がスクロール位置を失う問題を修正する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 11:22'
updated_date: '2026-08-08 12:02'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/ViewerWindowController.swift
  - BefoldApp/befold/Viewer/ViewerCapabilities.swift
priority: high
type: bug
ordinal: 506000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) 指摘。executor のガードが capabilities.canToggleSourceMode（onDocument && supportsSourceMode、.code では false）から canSelect(.source) = canSelectSourceMode（onDocument && !isBinaryContent、.code では true）に変わり、.code ファイルでも setDisplayMode(.source) が実行されるようになった。

既に source 表示中の .swift 等（保存値 .rendered / effectiveDisplayMode .source）で、選択済み source セグメントのクリック / cmd+2 / パス無し `befold --source`（ViewerWindowManager.applyDisplayOverrides）を行うと didChange が true になり、rendered→source の完全遷移が走る。スクロール位置は rendered キー側へ保存され、復元は空の source キーを読むため先頭へ飛ぶ。意味の無い .source が DisplayModeStore へ永続化もされる。main ではこれらの経路は全て no-op だった。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 .code ファイルで選択済み source セグメントのクリック / cmd+2 が no-op になり、スクロール位置が維持される
- [x] #2 .code ファイルに対して DisplayModeStore に .source が永続化されない
- [x] #3 上記の判定ロジックをユニットテストで担保する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. setDisplayMode の遷移判定を保存値 displayMode ではなく実表示 effectiveDisplayMode との比較に変え、一致時は早期 return する（スクロール位置退避・永続化・refreshDiff をまとめて no-op にする）
2. .code は displayMode=.rendered / effective=.source のため、選択済み source セグメントのクリック・cmd+2・パス無し befold --source（applyDisplayOverrides）が全て no-op になる
3. effective が displayMode と食い違うのは「displayMode == .rendered かつ showsCodeContent」= .code のみで、その場合 .rendered は canSelectPreviewMode=false により既存ガードで弾かれる。よって挙動が変わるのは今回の対象ケースだけ
4. ユニットテストを追加: .code ファイルで setDisplayMode(.source) が no-op（DisplayModeStore に .source が書かれない / スクロール保存が呼ばれない）、および従来の遷移が壊れていないこと
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
setDisplayMode の遷移判定を保存値 displayMode → 実表示 effectiveDisplayMode の比較へ変更し、一致時は早期 return（スクロール位置退避・永続化・refreshDiff をまとめて no-op 化）。didChange 変数は不要になったため撤去。

単純化の検討: 新しい状態や .code 専用の分岐を足さず、既に存在する導出値 effectiveDisplayMode（セグメント選択位置の根拠と同じ値）へ比較対象を寄せるだけで解消した。判定の根拠が「セグメントが選択済みに見える値」と一致するため、同型の再発余地が減る。

影響範囲: effectiveDisplayMode が displayMode と食い違うのは displayMode == .rendered かつ showsCodeContent のときのみ（= .code、ViewerStore.swift:110）。その状態で .rendered を選ぶ経路は canSelectPreviewMode == false で既存ガードが弾くため、挙動が変わるのは本件のケースだけ。

検証（実測）:
- swift test --skip Integration --skip FileWatcherTests → 1109 tests / 154 suites 全 pass
- 修正行を元の displayMode 比較へ戻すと新規テストが失敗（2 issues）することを確認済み。テストが空振りでないことの担保
- swiftlint（変更 2 ファイル）: 警告 4 件はいずれも file_length / type_body_length 等の既存指摘で、新規増分なし（本変更は差し引き行数減）

AC#1 のスクロール位置について: 遷移そのものが起きない（saveScrollPositionBeforeTransition も復元も走らない）ことを機構として担保しており、テストは displayMode / effectiveDisplayMode が不変であることで確認している。位置の値そのものは fixture が実 WKWebView を持たないため直接観測していない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
setDisplayMode の遷移判定を保存値 displayMode ではなく実表示 effectiveDisplayMode との比較に変え、一致時を早期 return で no-op 化した。プレビューを持たない .code は保存値 .rendered のままソースを出しているため、選択済み source セグメントのクリック / cmd+2 / パス無し befold --source が遷移扱いとなり、スクロール位置を rendered キーへ退避したまま空の source キーから復元して先頭へ飛び、無意味な .source が永続化されていた。ViewerWindowControllerSourceModeTests に no-op ケースと、塞ぎすぎていないことを見る .code → .diff 遷移ケースを追加。swift test 1109 件全 pass、修正を戻すと新規テストが落ちることも確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
