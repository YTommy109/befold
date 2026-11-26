---
id: TASK-930.7
title: 一覧を出しているフォルダーが消えたときの本文とタイトルを決める
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T13:14:00Z'
updated_date: '2026-11-26T01:40:06Z'
labels: []
dependencies: []
parent_task_id: TASK-930
priority: medium
type: bug
ordinal: 869000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の指摘(2026-11-25、重要度 important)。本文がフォルダー X の一覧を出している間に X が削除・改名されると、取り直しで選択は外れるが意図は .folder(X) のまま残り、本文は存在しないディレクトリの一覧(失敗表示)、窓のタイトルは X のままになる。ADR 0013 以前は開いている文書へ戻っていた。注意: TASK-930.1 の Implementation Plan 7(c) と Notes で「フォルダーが消えても本文を文書へ戻さず一覧の失敗表示のままにする」と意図して決めている(サイドバーの同期は意図を書かない = ADR 0013 決定 3)。直すなら、サイドバーではなく窓が事実(フォルダーが存在しない)を見て意図を書き直す形にする必要がある。挙動の判断が要るため、着手前にユーザーへ方針を確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フォルダーが消えたときの本文の挙動(失敗表示のまま / 文書へ戻る / 親フォルダーの一覧へ移る)をユーザーと決め、Notes に記録している
- [x] #2 決めた挙動を、サイドバー側の型に意図を書く口を与えずに実装している
- [x] #3 削除と改名の両方をテストで確かめ、修正を戻すと落ちることを確かめている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. PresentationIntent に presentFileIfFolderVanished() を足す: 意図が .folder(X) で X が実在しない(DirectoryLister.isDirectory)なら .file を書く。判定は事実で行い、サイドバーの一覧の行や取得の成否は見ない
2. 呼ぶのは窓だけ: ViewerWindowController / BlankTabWindowController の windowDidBecomeKey で、サイドバーの取り直しより前(意図 → サイドバー)。ディレクトリ監視は無く、外部の変更を拾う契機はキー復帰だけ(FolderListingView の keyEpoch と同じ)
3. テスト(実ファイル): 文書タブ = フォルダーに入った / フォルダー行 × 削除 / 改名で .file とタイトル a.md、残っていれば一覧のまま。空タブ(ディレクトリを開いた窓)= 削除で空タブの画面とタイトル「新しいタブ」
4. viewer-ui.md の「消えても一覧のまま」の記述を直す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針(ユーザー決定 2026-11-26): 一覧を出しているフォルダーが消えたら、開いている文書へ戻る(意図を .file へ書き直す)。空タブの一覧の窓は .file = 空タブの画面へ戻す。書き直すのはサイドバーではなく窓。

実装: 上の計画どおり。修正前のコードで新テスト 5 ケース(文書タブ 4・空タブ 1)がすべて落ち、修正後に通ることを実測した(フォルダーが残っているケースは前後とも通る)。TASK-930.1 で決めた「消えても一覧の失敗表示のまま」を、ユーザー決定(2026-11-26)により改めた。docs/dev/viewer-ui.md の該当記述と PresentationIntent の書き手の doc を更新。ViewerWindowController は上限 963 に収めた(windowDidBecomeKey のコメントを 1 行にまとめた)。検証: swift test --skip PDF 2011 件通過、swiftlint 変更ファイル 0 件、型グループ --check 通過、xcodebuild は別の derivedDataPath で成功。実機確認は未実施。
範囲外: 表示中フォルダー自身(サイドバーの currentDirectory)が消えたときのサイドバーの表示は従来の失敗表示のまま(本文だけが文書へ戻る)。

追加(advisor の指摘): (1) 同型の兄弟 = 消えたフォルダーの一覧の履歴へ戻ると、次のキー復帰まで失敗表示の一覧が出ていた(テストで実測)。PresentationIntent.presentExisting(_:) を足し、履歴の再生(ViewerWindowController.navigateHistory)とキー復帰(presentFileIfFolderVanished)の両方をこれに通した。テスト ViewerWindowHistoryPresentationTests.goingBackToVanishedFolderPresentsDocument(修正前に落ちる)。(2) ADR 0013 の決定 2 に、この書き手を例外として追記した(2026-11-26)。(3) 存在確認はメインで同期に stat 1 回とした。withBlockingWork が守るのは協調スレッドプールの枯渇でメインの stat を禁じるものではなく、performFileSwitch の store.fileExists も同じ扱い。キー復帰と再生は高頻度の経路ではない。(4) 930.7 は新しい意図の書き手を足す変更だったが /review-design を回していなかった(上の (1)(2) はそれで拾えた型)。全体 2012 件通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
一覧を出しているフォルダーが削除・改名で無くなったら、窓がキーに戻った時点で本文を開いている文書へ戻すようにした(ディレクトリを開いた窓は空タブの画面)。PresentationIntent.presentFileIfFolderVanished() を、両方の窓の windowDidBecomeKey でサイドバーの取り直しより前に呼ぶ。判定はディレクトリの実在で行い、サイドバーには書く口を与えていない。方針はユーザー決定(2026-11-26)で、TASK-930.1 の「失敗表示のまま」を改めた。検証: 修正前に落ちる新テスト 5 ケース、全体 2011 件通過、xcodebuild 成功。実機確認は未実施。
<!-- SECTION:FINAL_SUMMARY:END -->
