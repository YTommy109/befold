---
id: TASK-612
title: スライド窓で開いたファイルが次回起動で通常窓として復元される
status: To Do
assignee: []
created_date: '2026-09-11 08:32'
labels: []
dependencies: []
ordinal: 802000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スライド窓は `ViewerWindowKind.isRestorable == false` で「セッション復元の対象外」と宣言しているが、その宣言が復元経路の片側で破れている。

経路（すべてコード参照）:
- `ViewerWindowManager+OpenViewer.swift` の `openViewer` は `sessionStore.noteOpened(url)` を**種別に関係なく**呼ぶ（TASK-610 で Open Recent と最近使ったリポジトリは除外したが、セッションはそのまま残した）
- `SessionRestorer.captureSavedState` は `sessionStore.savedURLs()` を復元候補に読む
- `SessionRestorer.currentSessionLayout` はスライド窓を `ViewerTabGrouping.viewerPath` 経由で落とすので、**レイアウトには入らない**
- その結果スライド専用で開いたファイルは「レイアウトに無い候補」になり、`restoreLastSession` の「レイアウトに無いファイル(クラッシュ後に開いたもの等)は従来どおり開いた順に開く」ループで `openViewer` される

つまりスライド窓を開いたままアプリを終了すると、次回起動でそのファイルが**通常のビューア窓として**開く。TASK-593.2 が `viewerPath` にスライド除外を置いたのは復元スナップショットのためだが、`savedURLs` はその合流点を通らない別系統になっている。

実装時に注意する分岐（未確認・実装者が確かめること）: 同じファイルを通常窓とスライド窓の両方で開いている場合、`noteOpened` を種別で弾くだけでは足りない可能性がある。`ViewerWindowSessionSync.noteClosedIfNoWindowRemains` は `manager.controllers[key] == nil` でしか閉じたと判定しないため、通常窓を先に閉じてもスライド窓のコントローラが辞書に残っている間は `noteClosed` が走らない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 スライド窓だけで開いていたファイルが、終了→再起動で復元されない
- [ ] #2 通常のビューア窓で開いていたファイルの復元は従来どおり動作する（レイアウト経由・レイアウト外の候補経由の両方）
- [ ] #3 同じファイルを通常窓とスライド窓の両方で開いて終了した場合、通常窓の分として復元される
- [ ] #4 スライド窓を閉じても、同じファイルを表示している通常窓のセッション記録が消えない
- [ ] #5 ユニットテストで担保する（述語だけでなく、SessionRestorer / ViewerWindowManager の実配線で見る）
<!-- AC:END -->
