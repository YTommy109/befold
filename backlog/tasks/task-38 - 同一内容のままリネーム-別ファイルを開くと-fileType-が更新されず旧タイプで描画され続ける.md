---
id: TASK-38
title: 同一内容のままリネーム/別ファイルを開くと fileType が更新されず旧タイプで描画され続ける
status: To Do
assignee: []
created_date: '2026-07-17 02:07'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerStore.apply() の同一内容スキップ(`cache.dataHash == contentHash`、.chunked :341 / .full :355)が `self.fileType = fileType` の代入より前に return する。リネームはバイト列を変えないため、handleRename → pendingFileType 設定 → loadContent() は必ず同じ dataHash を生成してスキップに入り、公開 fileType が旧タイプのまま残る(例: notes.md → notes.mmd が Markdown として描画され続ける)。openFile()/close() は contentHash をリセットしないため、バイト同一の別ファイルを開いた場合も同様。

修正方向: スキップ判定キーを (dataHash, fileType) にする、またはスキップパスでも fileType の commit と onContentReloaded を行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 内容同一のまま拡張子を変えるリネームで fileType が更新され再レンダリングされる(テストあり)
- [ ] #2 openFile で contentHash 起因のスキップにより表示が古いままにならない
- [ ] #3 内容もタイプも同一の場合は従来どおり再描画をスキップする(TASK-23 の回帰なし)
<!-- AC:END -->
