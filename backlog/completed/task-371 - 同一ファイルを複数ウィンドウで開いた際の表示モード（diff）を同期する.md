---
id: TASK-371
title: 同一ファイルを複数ウィンドウで開いた際の表示モード（diff）を同期する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 11:22'
updated_date: '2026-08-08 12:32'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/ViewerWindowController.swift
  - BefoldApp/befold/App/ViewerWindowManager.swift
priority: medium
type: bug
ordinal: 512000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) 指摘。FeatureGate 配下（diff 表示）。TASK-330 で導入した toggleSourceDiff / viewerWindowDidToggleSourceDiff の全ウィンドウ broadcast（ViewerWindowManager が allControllers.forEach { refreshDiff() }）が削除され、「同一ファイルを開いた 2 窓は同じ diff の答えを示す」という不変条件（削除された DiffDisplayPreference の doc コメントが明記していた）を置き換える同一ファイル間の同期処理が無い。setDisplayMode はパス単位で永続化するだけで他窓へ通知しない。新テストは別ファイルを開いた窓のケースしか検証していない。

再現: ファイル X を 2 窓で表示 → 窓 A で diff モード選択 → 窓 B は plain source のままで cmd+3 メニューのチェックも変わらない。再起動後は last-write-wins で両窓とも diff になり、終了前の窓 B の画面と復元状態が食い違う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 同一ファイルを表示している全ウィンドウに表示モード変更が反映される
- [x] #2 別ファイルを表示しているウィンドウは影響を受けない
- [x] #3 同一ファイルを 2 窓で開いたケースをユニットテストで担保する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerWindowControllerDelegate に viewerWindow(_:didChangeDisplayMode:) を必須要件として追加する（実装漏れがコンパイルエラーになる形）。
2. setDisplayMode を「本体 + 通知」に分ける。本体は mirrorDisplayMode(_:) として切り出し、setDisplayMode は本体を呼んだ後に delegate へ通知する（mirror 側は通知しない = 再帰しない）。
3. mirrorDisplayMode ではスクロール位置を保存しない。ScrollPositionStore は (path, mode) 粒度でアプリ全体共有で、保存は JS コールバック経由の非同期（WebViewCommandController.saveCurrentScrollPosition）。2 窓が同じキーへ書くと勝者が非決定になるため、書き込みは操作した窓の 1 本に限る。
4. mirrorDisplayMode でもソース系モードへ入る際に sourceToggleReturn をクリアする（ViewerWindowController.swift:690 と同じ理由）。戻り先の記憶自体は窓ごとの操作履歴として同期しない旨を doc コメントに残す。
5. ViewerWindowManager 側は controllers[controller.fileURL.normalizedPathKey] を引き、同一性（!==）で操作元を除いた窓へ mirrorDisplayMode を適用する。allControllers を URL 比較で絞る形にはしない（AC#2 がキー引きから構造的に従う）。
6. broadcast は delegate 呼び出し内で同期に行う。Task {} で包まないこと。refreshDiff の取得登録が契機と同じターンに乗ることが、2 窓で git diff を 1 回へ合流させる条件（ViewerWindowController+Diff.swift:31-34 / TASK-325・346）。
7. 不変条件の適用範囲を doc コメントに明記する: 「同一ファイルの全窓が同じ表示モードを示す」は永続化されるユーザー選択に限る。CLI --source/--preview の起動限りの上書き（ViewerWindowController.swift:309）は意図的に窓ごとで同期しない。
8. テスト（AC#3）: MockedViewerWindowManager で同一 URL を disposition: .newWindow で 2 回開き（重複抑止は .currentTab のみ / ViewerWindowManager.swift:231）、片方で setDisplayMode → もう片方の store.displayMode が追従することを検証する。別ファイルの窓が .rendered のままであることも検証する（AC#2）。アサートは store.displayMode に置く（canSelectDiffMode は FeatureGate 非依存 / ViewerCapabilities.swift:70）。diffText・git 起動回数の検証は注入した diffReader 側で行う（diffLoader はゲート OFF で nil / ViewerWindowManager.swift:124）。

/review-design 実施済み。指摘 6 件（項目1/2/3/5/6/8/9）はすべて上記へ反映した。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: setDisplayMode の本体を mirrorDisplayMode(_:) へ切り出し、setDisplayMode は末尾で delegate へ通知する。ViewerWindowManager が controllers[origin.fileURL.normalizedPathKey] を引き、同一性（!==）で操作元を除いた窓へ mirrorDisplayMode を同期に適用する。delegate メソッドはプロトコル必須要件（実装漏れがコンパイルエラー。実際に追加時点でマネージャ側が conform エラーになることを確認した）。

設計判断（いずれも doc コメント + テストで担保）:
- mirror 側は通知しない（往復しない）／永続化しない（操作元が同じ値を既に書いている）／スクロール位置を保存しない。ScrollPositionStore は (path, mode) 粒度でアプリ全体共有かつ保存が JS コールバック経由の非同期のため、2 窓が同じキーへ書くと勝者が非決定になる。書き込みは操作した窓の 1 本に限る。
- cmd+U の戻り先の記憶（sourceToggleReturn）は窓ごとの操作履歴として同期しない。ただしソース系モードへ入る際のクリアは mirror 側でも行う。
- 不変条件の対象は永続化されるユーザー選択に限る。CLI --source/--preview の起動限りの上書き（ViewerWindowController.swift:309）は意図的に窓ごとで同期しない旨をプロトコルの doc コメントに明記した。

副産物: MockViewerWindowControllerDelegate に TASK-330 で削除された viewerWindowDidToggleSourceDiff のスタブが残っていた（参照ゼロの死んだメンバー）。新通知の記録（displayModeNotifications）へ置き換えた。

検証（実測）:
- 新規 ViewerWindowManagerDisplayModeSyncTests 4 件が pass。
- broadcast を無効化した状態（for peer in peers where false && ...）で再実行し、4 件のうち 3 件が失敗することを確認した（差分反映 / ソース反映 / cmd+U 記憶）。AC#2 の「別ファイルは影響を受けない」は非伝播のアサートなので意図どおり pass のまま。テストが空振りでないことの確認。
- swift test 全体: 1214 tests / 178 suites すべて pass。
- swiftlint: main（origin/main を別ディレクトリへ展開）と比較して警告 78 件が同一集合。差分は既存違反の行数表示のみで、新規ゼロ。
- swiftformat --lint: 0 files require formatting（hoistTry 指摘は fix モードで機械に直させた）。
- xcodegen generate 実施済み（テストファイル 1 件を新規追加したため）。

未検証: 実機での 2 窓同期（GUI 層は自動テスト対象外。差分表示は dev ビルドの dogfood 側で確認する）。スクロール位置を mirror で保存しないことは、テストでは非書き込みを決定的に観測できないため doc コメントでの担保に留めた。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
同一ファイルを表示している窓の間で表示モードが揃わない問題を、ViewerWindowControllerDelegate 経由の同期 broadcast で修正した。setDisplayMode の本体を mirrorDisplayMode(_:) へ切り出し、ViewerWindowManager が controllers のキー引きで同一ファイルの他窓だけへ適用する（別ファイルは登録の構造上そもそも対象外）。永続化・スクロール保存・cmd+U 記憶の扱いは操作元と反映先で意図的に分け、doc コメントとテストの両方で固定した。検証は新規 ViewerWindowManagerDisplayModeSyncTests 4 件（broadcast を無効化すると 3 件が落ちることを実測して空振りでないことを確認）、swift test 全体 1214 件 pass、swiftlint は main と同一の 78 件で新規ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
