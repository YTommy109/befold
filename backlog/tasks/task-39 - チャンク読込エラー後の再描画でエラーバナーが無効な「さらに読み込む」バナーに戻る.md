---
id: TASK-39
title: チャンク読込エラー後の再描画でエラーバナーが無効な「さらに読み込む」バナーに戻る
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-17 02:07'
updated_date: '2026-07-17 03:47'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerWebView.swift の TruncationState は `failed: Bool = false` のデフォルト付きで、applyRender の truncatedScript 再送(:503)は failed:false を固定で送る。チャンク読込失敗後(loadFailed=true、chunkSession=nil、isTruncated=true 維持、lastTruncation.failed=true)、行番号トグル等の任意の再描画で truncationStateChanged() が failed の差分を検知して _mmdSetTruncated(..., failed:false) を再送し、エラーバナー(TASK-25 で導入)が通常の「さらに読み込む」バナーに戻る。しかし chunkSession が nil のためボタンは永久に無反応。

修正方向: failed のデフォルト値をやめ、applyRender/truncationStateChanged に lastTruncation の failed を貫通させる(3箇所の呼び出しが揃うように)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 チャンク読込エラー後に再描画(行番号トグル等)してもエラーバナーが維持される
- [x] #2 TruncationState の failed がデフォルト引数に依存せず全経路で明示的に渡される
- [x] #3 クリックしても何も起きない「さらに読み込む」ボタンが表示される経路がない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化検討: Coordinator の lastTruncation.failed をそのまま持ち越す案は、正常な再ロード(新しい chunkSession 成功)時に failed をリセットするタイミングが Coordinator 側では判別できず、逆に複雑化する。ViewerStore は既に isTruncated/displayedLineCount を stored property として一元管理しているのと同じパターンで loadFailed も stored property化するのが最も単純で一貫性がある。
2. ViewerStore.swift: private(set) var loadFailed: Bool = false を追加。apply() の .chunked/.full 両ケースで false にリセット、loadMoreLines() の catch ブロックで true に設定。
3. ViewerContentView.swift: ViewerWebView(...) 呼び出しに loadFailed: store.loadFailed を追加。
4. ViewerWebView.swift:
   - struct ViewerWebView に let loadFailed: Bool を追加。
   - updateNSView 内の updateContent(...) 呼び出しに loadFailed: loadFailed を追加。
   - Coordinator.updateContent(...) のシグネチャに loadFailed: Bool を追加し、truncationStateChanged と applyRender の呼び出しへ渡す。
   - applyRender の truncation タプル型に failed: Bool を追加し、_mmdSetTruncated 呼び出しの failed 引数と lastTruncation 構築の両方に明示的に渡す(503行目付近のハードコード false を廃止)。
   - truncationStateChanged に failed: Bool 引数を追加し、比較用 TruncationState 構築に明示的に渡す。
   - TruncationState.init のデフォルト引数 `failed: Bool = false` を廃止し、3箇所の呼び出し(handleLoadMoreLines / applyRender / truncationStateChanged)すべてで明示的に渡すよう揃える。
5. ビルド・既存テスト(swift build / swift test)を実行して確認。ViewerStoreTests に loadFailed のリセット/設定を検証するケースを追加する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: ViewerStore に private(set) var loadFailed を追加(apply() で false リセット、loadMoreLines() の catch で true 設定)。ViewerContentView → ViewerWebView → Coordinator.updateContent(truncation タプルに loadFailed を統合、function_parameter_count lint 対応) → applyRender/truncationStateChanged/TruncationState まで failed を明示的に貫通させ、TruncationState.init のデフォルト引数を廃止。
検証: swift build 成功、swift test --skip Integration --skip FileWatcherTests で346件全通過(新規テスト loadFailedResetsOnReload を含む)。加えて viewer.html の _mmdSetTruncated を直接叩くスクラッチスクリプトで、エラー後の再送(failed=true 維持)でバナー/ボタン状態が壊れないことをJSレベルでも確認(スクリプトはテスト後削除)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
チャンク読込エラー後の再描画でエラーバナーが失われる問題を修正した。ViewerStore に永続プロパティ loadFailed を新設し(apply() でリセット、loadMoreLines() のエラーパスで true 設定)、ViewerContentView → ViewerWebView → Coordinator まで既存の isTruncated/lineCount と同じパターンで一貫して伝搬させた。TruncationState.init のデフォルト引数 failed:false を廃止し、全呼び出し箇所で明示的な値を要求するようにした。検証: swift build 成功、swift test 346件全通過(新規テスト含む)、viewer.html への _mmdSetTruncated 直叩きスクリプトでエラーバナー/ボタン非表示が再描画後も維持されることを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
