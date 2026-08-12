---
id: TASK-430
title: ViewerStore（492 行）を責務ごとに分割する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 12:35'
updated_date: '2026-08-12 00:44'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 100600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befold/Viewer/ViewerStore.swift` は 492 行（`wc -l` 実測、2026-08-10 時点）で `BefoldApp/.swiftlint.yml:13-15` の `file_length` warning 400 を超えている。TASK-428 のラチェットを最終的に撤去して単純な閾値強制へ畳むには、この負債の返済が必要。

`ViewerStore` は `@MainActor @Observable` の中核状態で、`FileWatcher` からの変更を受けて `ViewerRenderer` の `evaluateJavaScript` へ伝搬する経路の中心にいる（`.claude/CLAUDE.md` のデータフロー記述）。分割時は状態の単一情報源が割れないことに注意する。

着手時に確認すべき制約: 既存テストが触る internal 面（`ViewerStoreTests.swift` 540 行 / `ViewerStoreChunkTests.swift` 392 行 / `ViewerStoreFileGoneTests.swift` 353 行が参照）は同名で到達できること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ViewerStore.swift が file_length warning の 400 行以下になる
- [x] #2 分割が行数回避ではなく責務単位になっている（各分割先が何を担うかを 1 行で言える）
- [x] #3 状態の単一情報源が分割によって二重化していない
- [x] #4 main との swiftlint 差分に真の新規が無い（/swiftlint-baseline の手順で確認）
- [x] #5 swift test が既存どおり通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerStore.swift を「状態の所有と書き換え」だけに絞る（プロパティ宣言 / init / 表示状態を書き換える唯一の入口 / close）
2. ViewerStore+Loading.swift へ読み込み経路（loadContent / performLoad / apply / loadMoreLines）を移す
3. ViewerStore+FileWatching.swift へ監視・rename・削除検知（openFile / handleRename / fileExists / isExistingFile / scheduleFileGone）を移す
4. 分割先から触る必要が出た表示状態は private のまま据え置き、beginLoading / finishLoading(url:) / appendChunk / markChunkLoadFailed / cancelFileGoneTask という internal な書き換え入口を core 側に置いて経由させる（状態の二重化と直接書き換えを構造的に防ぐ）
5. xcodegen generate → swift build / swift test → swiftformat → swiftlint ベースライン差分ゼロ確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ViewerStore.swift 492 行 → 367 行（wc -l 実測）。責務ごとに 3 ファイルへ分割した。

- ViewerStore.swift(367): 状態の宣言・init・表示状態を書き換える唯一の入口・close
- ViewerStore+Loading.swift(115): 読み込み経路（loadContent / performLoad / apply / loadMoreLines）
- ViewerStore+FileWatching.swift(73): 監視・rename・削除検知（openFile / handleRename / fileExists / isExistingFile / scheduleFileGone）

状態の二重化を防ぐ構造（AC#3）: 表示状態の stored property（content / contentRevision / fileType / rejectReason / isTruncated / loadFailed / displayedLineCount / isLoading / filePath / hasDeclaredHTMLCharset / newlineCount / contentHash / chunkSession）は core ファイル内で private のまま据え置き、分割先からは beginLoading() / finishLoading(url:) / appendChunk(_:isAtEnd:) / markChunkLoadFailed() / cancelFileGoneTask() / applyDisplayState(_:) 経由でのみ変更する。Swift の private がファイルスコープであることを利用し、『分割先から表示状態を直接書き換える』ことをコンパイラが禁じる形にしてある（doc コメントの約束ではなく構造で担保）。

internal へ上げたのは読み込み・監視の内部機構のみ（pendingURL は private(set) / pendingFileType / loadTask / loadGeneration / fileGoneTask / fileWatcher / makeWatcher / watcherDebounceDelay / makeChunkedReader / contentLoader / clock / fileGoneGracePeriod / setPendingURL / chunkSession は private(set)）。それぞれに『呼んでよいのはどれか』の doc を付けた。

検証:
- swift test: 1433 tests in 213 suites passed（既存テストの internal 面は同名のまま到達可能）
- /swiftlint-baseline: 真の新規ゼロ。解消 2 件（ViewerStore.swift の file_length / type_body_length）
- swiftformat fix モード: 0 files formatted（差分なし）
- xcodegen generate 実行済み

追記（グループ・ラチェット対応）: 分割だけでは TASK-428 の型グループ合算が 492 → 555 に増えたため、削除確定のグレース期間（クロック・待機・張り替え）を FileGoneWatchdog 型へ切り出して 28 行を実際に回収し、doc の重複も整理して 531 まで下げた。それでもベースライン +39 で、内訳はファイル分割の定型部と表示状態の書き換え入口（不変条件を構造で守るためのもの）。ユーザー判断により『構造的な担保を維持してベースラインを更新』を選択し、scripts/check-type-group-size.sh --update-baseline を実行、理由をコミットメッセージへ記録した。これ以上の削減は表示状態そのものを別の型へ移すことになり AC#3 と衝突する。

最終構成: ViewerStore.swift 351 / +Loading 115 / +FileWatching 65 / FileGoneWatchdog 43。
再検証: swift test 1433 tests passed / swiftlint 真の新規ゼロ・解消 2 件 / swiftformat 差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerStore を「状態の所有と書き換え」「読み込み」「監視」の 3 ファイルへ分割し、492 → 367 行にした。表示状態の stored property を core ファイルの private のまま残し、分割先は internal な書き換え入口経由でしか触れない形にすることで、状態の単一情報源が割れないことをコンパイラで担保している。swift test 1433 件通過、swiftlint 新規違反ゼロ（file_length / type_body_length の既存 2 件が解消）。
<!-- SECTION:FINAL_SUMMARY:END -->
