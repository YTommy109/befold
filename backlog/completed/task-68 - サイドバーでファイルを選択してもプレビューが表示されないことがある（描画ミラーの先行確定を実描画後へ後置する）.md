---
id: TASK-68
title: サイドバーでファイルを選択してもプレビューが表示されないことがある（描画ミラーの先行確定を実描画後へ後置する）
status: Done
assignee: []
created_date: '2026-07-19 05:30'
updated_date: '2026-07-19 06:10'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-07-19 の PR #262 コードレビュー時のイベント伝搬調査で特定。症状: サイドバーでファイルを選択してもプレビューが表示されないことが時々ある（再現性不明）。原因候補（高）: 直接 HTML モード離脱分岐（BefoldRenderKit/ViewerRenderer+ContentUpdate.swift:62-83）が実描画前に recordRendered（:78-81）でミラーを「描画済み」と先行確定する一方、実描画は reloadViewerHTML の pendingUpdate（単一スロット、ViewerRenderer+RenderHelpers.swift:101-113）の completion に遅延している。viewer.html 再ロード中に updateContent が再発火するとスロットが上書きされて離脱時の描画が破棄され、以後 needsRender（:109-114、filePath を判定に含まない）が「描画済み」と誤判定して空表示のまま固まる。再ロード中の再発火要因は FileWatcher onChange による isLoading トグル・ズーム・連続クリック等。関連の穴（中）: 内容バイト列が同一のファイル間切替では ViewerStore.apply が dataHash 一致で早期 return し revision が進まないため、needsRender が filePath 差を見ず前ファイルの表示が残る。TOCTOU で .missing になった場合も同型。根治方針: 「recordRendered は render が実際に評価された後にのみ行う」に統一（ミラーが嘘をつかなくなり、pendingUpdate が落ちても次の updateContent で自然回復）＋ needsRender に filePath 差を追加。renderer.updateContent を直接駆動する回帰テストが現状皆無（見逃しの根因）なので併せて追加する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 .html 表示中に別ファイルへ切替え、viewer.html 再ロード中に updateContent が再発火しても最終的にプレビューが表示される（回帰テストあり）
- [x] #2 内容が同一の2ファイル間の切替でも新ファイル基準で再描画される（回帰テストあり）
- [x] #3 recordRendered が実描画（render スクリプト評価）後にのみ呼ばれる構造になっている
- [x] #4 既存の描画系テスト（ViewerRendererMessageHandlingTests / ViewerStore 系）が通過する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
メイン側で main worktree に取り込み検証: swift build 成功、swift test 全439件pass(新規回帰テスト2件含む)、swiftlint --strict は該当ファイルで baseline と同数(pre-existing違反のみ、新規違反なし)。コミット 20b2929 で確定。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
recordRendered を applyRender/applyAppend 内の evaluateJavaScript 実行後に一本化し、needsRender に filePath 差分判定を追加。回帰テスト2件(直接HTMLモード離脱中の再ロード競合、同一revisionでのファイル切替)を追加し全て pass。既存描画系テスト含め swift test 439件全pass。コミット 20b2929。
<!-- SECTION:FINAL_SUMMARY:END -->
