---
id: TASK-460
title: ViewerStore（型グループ 531 行）を独立型へ切り出して閾値以下に戻す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-12 02:21'
updated_date: '2026-08-12 03:25'
labels: []
dependencies: []
priority: low
ordinal: 684000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-430 で ViewerStore を分割したが、切り出し先を同ディレクトリの ViewerStore+*.swift にしたため、型グループ（Foo.swift + 同ディレクトリの Foo+*.swift の合算）としては 531 行で閾値 400 を超えたままになっている。scripts/type-group-baseline.txt に凍結値として残っており、TASK-428.5（ベースライン撤去）の着手を妨げている。

内訳（実測 2026-08-12）:
ViewerStore.swift 351 / +Loading 115 / +FileWatching 65。本体 351 行が支配的。

extension への分割では型グループの合計は減らないため、責務を独立した型へ移す。ViewerStore は @MainActor @Observable の状態保持型なので、stored property を伴わない導出・変換ロジックから優先して切り出す。どの責務を独立型にするかは着手時に判断する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 型グループ BefoldApp/befold/Viewer/ViewerStore の行数が 400 以下になっている（scripts/check-type-group-size.sh の出力で確認）
- [x] #2 scripts/type-group-baseline.txt から ViewerStore のエントリが削除されている
- [x] #3 swift test が緑で、swiftlint のベースライン差分がゼロである
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 読み込みが確定させた表示状態（content / contentRevision / fileType / rejectReason / isTruncated / loadFailed / displayedLineCount / isLoading / filePath / hasDeclaredHTMLCharset / chunkSession / contentHash / newlineCount）と、その書き換え入口（beginLoading / finishLoading / appendChunk / markChunkLoadFailed / DisplayState / applyDisplayState）を、新規型 ViewerContentState（BefoldApp/befold/Viewer/ViewerContentState.swift, @MainActor @Observable final class）へ移す。
2. ViewerStore は contentState を 1 つ保持し、転送プロパティは置かない（転送を置くと合算行数が減らないため）。参照側は store.contentState.x へ書き換える。
3. 1 の実測後に行数を測り、400 以下に届かなければ showLineNumbers の永続化（UserDefaults キー + CLI 一時上書き）を App の他ストアと同じ形の独立型へ切り出す。
4. scripts/check-type-group-size.sh --check / --update-baseline でベースラインから ViewerStore を落とす。
5. swift test と swiftlint ベースライン差分ゼロを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 読み込みが確定させた表示状態（content / contentRevision / fileType / rejectReason / isTruncated / loadFailed / displayedLineCount / isLoading / filePath / hasDeclaredHTMLCharset / chunkSession / contentHash / newlineCount）と書き換え入口を ViewerContentState（新規 155 行）へ移し、ViewerStore は contentState を let で 1 つ持つ形にした。転送プロパティは置かず、参照側 12 ファイルを store.contentState.x へ書き換えた（転送を置くと合算行数が減らないため）。

行番号表示の設定（UserDefaults 永続化 + CLI の起動限り上書き）も ShowLineNumbersSetting（新規 44 行）へ切り出した。これで ViewerStore から UserDefaults 依存が消えた。表示モードから導出する showsCodeContent は displayMode を必要とするため ViewerStore に残している。

粒度の担保: ViewerContentState / ShowLineNumbersSetting はいずれも ViewerStore が init で生成し let で保持する。注入用のデフォルト引数を設けていないので、渡し忘れで別インスタンスになる事故（TASK-319 型）が起きない。表示状態の stored property は ViewerContentState.swift 内で private(set) にしてあり、ViewerStore 側からも直接代入できない（従来はファイルスコープ private で同じ強制をしていた）。

実測:
- 型グループ ViewerStore: 531 → 392 行（内訳 ViewerStore.swift 210 / +Loading 116 / +FileWatching 66）
- scripts/check-type-group-size.sh --check: 「型グループの行数はベースライン以内です」
- swift test: 1446 tests / 227 suites すべて緑
- swiftlint: origin/main とのルール×ファイル比較で真の新規ゼロ。解消 3 件（ViewerStore.swift の opening_brace ほか）。残る差分 2 件（QuickOpenModelTestSupport の opening_brace / ViewerWindowControllerReferenceOpenTests の large_tuple）は本タスク未変更のファイルで、TASK-431 のテスト分割コミット由来
- docs/dev/native-app-design.md のモジュールツリーとコンポーネント表に ViewerContentState / ShowLineNumbersSetting を追記
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerStore の読み込み確定表示状態を ViewerContentState へ、行番号表示設定を ShowLineNumbersSetting へ独立型として切り出し、型グループを 531 → 392 行（閾値 400 以下）に戻した。scripts/type-group-baseline.txt から ViewerStore のエントリを削除し、残りは ViewerWindowController のみ。swift test 1446 件緑、swiftlint の main 比較で新規違反ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
