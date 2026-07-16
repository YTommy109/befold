---
id: TASK-24
title: チャンク読み込み中に Cmd+F すると検索入力が「Loading…」のまま無効化されたままになる
status: To Do
assignee: []
created_date: '2026-07-16 10:54'
updated_date: '2026-07-16 12:11'
labels: []
dependencies:
  - TASK-29
references:
  - BefoldApp/befold/Viewer/ViewerWebView.swift
  - BefoldApp/BefoldKit/Resources/viewer.html
priority: medium
type: bug
ordinal: 70
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
handleLoadMoreLines の再入ガード guard !isLoadingMoreLines else { return }（ViewerWebView.swift:440-444）が、「さらに読み込む」実行中に届いた loadAllLinesForSearch メッセージを黙って破棄する。JS 側は _mmdOpenFind で先に入力を無効化して Loading… を表示しており（viewer.html:536-542）、再有効化する唯一の経路 _mmdOnAllLinesLoaded は届かない。破棄されたのが最終チャンク読込中だった場合、完了時に _mmdIsTruncated=false になるため find バーを開き直しても非ロード分岐に入り入力は永久に無効のまま（ページ再読込まで復旧不能）。修正案: untilFullyLoaded 要求をペンディングとして記憶して先行ロード完了後に継続する、または完了を常にシグナルする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 「さらに読み込む」進行中に Cmd+F を押しても検索入力が最終的に有効化され検索できる
- [ ] #2 最終チャンク読込との競合ケースでも入力が無効のまま残らない
<!-- AC:END -->
