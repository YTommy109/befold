---
id: TASK-612
title: スライド窓で開いたファイルが次回起動で通常窓として復元される
status: To Do
assignee: []
created_date: '2026-09-11 08:32'
updated_date: '2026-09-11 08:44'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 起票後の追記（TASK-610 のコードレビューより）

- **入口は `openViewer` だけではない。** `ViewerWindowSessionSync.remapController` も
  `manager.sessionStore.noteOpened(newURL)` を種別に関係なく呼ぶ。スライド窓が文書内リンクで
  `.currentTab` 切替（`didSwitchFileFrom`）した場合や、表示中ファイルが rename された場合も
  同じ経路で savedURLs に入る。`openViewer` 側だけ直すと穴が残る。
- **3 つ目の同型なので、構造で塞ぐ。** TASK-593.2（復元スナップショット）、TASK-610
  （Open Recent と最近使ったリポジトリ）に続く 3 件目。現状は履歴ストアごとに判定の置き場が
  違う（`RecentDocumentsStore` は必須引数、`RecentRepositoryRecorder` は解決前の guard、
  `SessionStore` は無し）。このタスクで `SessionStore` だけに 4 つ目の個別ガードを足すのではなく、
  `openViewer` / `remapController` が 3 ストアへ扇状に書いている部分を 1 つの kind 付き
  入口へ寄せ、4 つ目のストアが判定を忘れられない形にすることを検討する。
<!-- SECTION:NOTES:END -->
