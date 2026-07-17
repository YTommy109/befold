---
id: TASK-38
title: 同一内容のままリネーム/別ファイルを開くと fileType が更新されず旧タイプで描画され続ける
status: Done
assignee:
  - '@claude'
created_date: '2026-07-17 02:07'
updated_date: '2026-07-17 03:31'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerStore.apply() の同一内容スキップ(`cache.dataHash == contentHash`、.chunked :341 / .full :355)が `self.fileType = fileType` の代入より前に return する。リネームはバイト列を変えないため、handleRename → pendingFileType 設定 → loadContent() は必ず同じ dataHash を生成してスキップに入り、公開 fileType が旧タイプのまま残る(例: notes.md → notes.mmd が Markdown として描画され続ける)。openFile()/close() は contentHash をリセットしないため、バイト同一の別ファイルを開いた場合も同様。

修正方向: スキップ判定キーを (dataHash, fileType) にする、またはスキップパスでも fileType の commit と onContentReloaded を行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 内容同一のまま拡張子を変えるリネームで fileType が更新され再レンダリングされる(テストあり)
- [x] #2 openFile で contentHash 起因のスキップにより表示が古いままにならない
- [x] #3 内容もタイプも同一の場合は従来どおり再描画をスキップする(TASK-23 の回帰なし)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerStore.apply() の同一内容スキップ判定(dataHash == contentHash)が fileType の変化を無視している点を確認済み(chunked: swift:341, full: swift:355)
2. 単純化検討: 新たな状態を追加せず、スキップ判定に既存の self.fileType との比較を追加するだけで対応する(スキップは『dataHash が一致 かつ fileType も変化なし』の場合のみに限定)
3. TDD: ViewerStoreTests に以下のテストを追加してから実装する
   - 内容同一のままリネーム(拡張子変更)で fileType が更新され onContentReloaded が発火する(AC#1)
   - openFile で内容同一・タイプ別の別ファイルへ切り替えても fileType が更新される(AC#2)
   - 内容・タイプとも同一の再読込では onContentReloaded が発火しない(TASK-23 の回帰なしを保証、AC#3)
4. ViewerStore.swift の apply() の2箇所のスキップ条件に fileType 比較を追加する
5. swift test 全体で回帰なしを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TDD で ViewerStoreFileTypeConsistencyTests.swift(新規)に3テストを追加:
1. watcherRenameWithIdenticalContentUpdatesFileType: 内容同一のままリネーム(.md→.mmd)で fileType が更新される(修正前は red、修正後 green)
2. openFileWithIdenticalContentAcrossDifferentTypesUpdatesFileType: openFile で内容同一・別タイプの別ファイルへ切り替えても fileType が更新される(修正前は red、修正後 green)
3. watcherCallbackWithIdenticalContentAndTypeSkipsReload: 内容・タイプとも同一の再読込では従来どおりスキップ(TASK-23 回帰なし、常に green)

修正: ViewerStore.swift apply() の .chunked/.full 両方のスキップ条件に fileType == self.fileType を追加(ViewerStoreTests.swift への追加は SwiftLint の type_body_length/file_length を超えるため、既存の ViewerStoreFileGoneTests と同様に別ファイルへ分離)。

検証: swift test 全体で 359 tests 全成功(既存テストの回帰なし)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerStore.apply() の同一内容スキップ(dataHash比較)が fileType の変化を無視していたため、内容同一のままのリネーム/別ファイル切替で旧 fileType のまま描画され続けるバグを修正。単純化方針に沿い、新たな状態を追加せずスキップ条件へ fileType == self.fileType の比較を追加するだけで .chunked/.full 両パスに対応(ViewerStore.swift:341, :355)。TDD で ViewerStoreFileTypeConsistencyTests.swift(新規)に3テスト追加し、修正前は red、修正後 green を確認。TASK-23 の同一内容スキップ(re-render抑止)の回帰なしも別テストで保証。swift test 全体(359テスト)成功。
<!-- SECTION:FINAL_SUMMARY:END -->
