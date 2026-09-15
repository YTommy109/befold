---
id: TASK-612
title: スライド窓で開いたファイルが次回起動で通常窓として復元される
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-09-11 08:32'
updated_date: '2026-09-11 12:56'
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
- [x] #1 スライド窓だけで開いていたファイルが、終了→再起動で復元されない
- [x] #2 通常のビューア窓で開いていたファイルの復元は従来どおり動作する（レイアウト経由・レイアウト外の候補経由の両方）
- [x] #3 同じファイルを通常窓とスライド窓の両方で開いて終了した場合、通常窓の分として復元される
- [x] #4 スライド窓を閉じても、同じファイルを表示している通常窓のセッション記録が消えない
- [x] #5 ユニットテストで担保する（述語だけでなく、SessionRestorer / ViewerWindowManager の実配線で見る）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
TASK-610 の設計レビュー（項目 2「既存の不変条件との衝突」・項目 3「兄弟判断の全列挙」）で検出した穴の対応。判定は `ViewerWindowKind.isRestorable`（既存。「セッション復元の対象か」）を使い、新しい述語は足さない。

1. セッションへの「開いた」記録の入口を `ViewerWindowSessionSync.noteOpened(_:in:)` の 1 つに寄せる。中で `isRestorable` ならセッションへ、`recordsUsageHistory` は `RecentDocumentsStore` 側の判定に任せて利用履歴へ書く。`openViewer` の末尾と `remapController` の非 rename 分岐がこれを呼ぶ（4 つ目のストアが増えても呼び出し側が片方だけ書けない形）。
2. `remapController` の rename 分岐の `sessionStore.noteRenamed` と、`viewerWindowDidBecomeKey` の `sessionStore.noteActivated` も `isRestorable` で弾く（スライド窓が savedActivePath を書き換えると、復元時にキーにする窓の指定が存在しないパスを指す）。
3. `noteClosedIfNoWindowRemains` は「復元対象の窓が 1 つも残っていなければ閉じたことにする」へ変える。通常窓を閉じてスライド窓が残っている場合は閉じたことにし（AC #3）、スライド窓を閉じて通常窓が残っている場合は消さない（AC #4）。
4. テストは `ViewerWindowManagerSessionRecordTests` に実配線で 3 件（スライド窓だけで開いても savedURLs / savedActivePath に入らない、通常窓を閉じてスライド窓だけ残れば消える、スライド窓を閉じても通常窓の記録は残る）。
5. `docs/dev/native-app-design.md` の該当行を更新する。
<!-- SECTION:PLAN:END -->

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

## 実装と検証

- 判定は既存の `ViewerWindowKind.isRestorable` を使い、新しい述語は足していない。
- 「開いた」記録の入口を `ViewerWindowSessionSync.noteOpened(_:in:)` の 1 つに寄せた。`openViewer` の
  末尾と `remapController` の非 rename 分岐が通る。セッション（`isRestorable`）と利用履歴
  （`recordsUsageHistory`、判定は `RecentDocumentsStore` 側）は別の述語だが、どちらも窓の種別から
  決まるので呼び出し側が片方だけ書けない形になった（TASK-610 レビューの「3 ストアの判定位置が
  バラバラ」への構造的な対応）。
- `noteClosedIfNoWindowRemains` は「復元対象の窓が 1 つも残っていなければ閉じたことにする」へ。
  通常窓を閉じてスライド窓だけ残れば消え（AC #3 の裏）、スライド窓を閉じても通常窓が残れば
  消えない（AC #4）。
- `viewerWindowDidBecomeKey` の `noteActivated` と rename 分岐の `sessionStore.noteRenamed` も
  `isRestorable` で弾く（スライド窓が savedActivePath を書くと、復元時にキーにする窓の指定が
  存在しないパスを指す）。
- AC #1 の根拠: スライド窓だけで開いた場合 savedURLs に入らない（新テスト）＋ 復元レイアウトは
  既存の `ViewerTabGrouping.viewerPath` がスライド窓を落とす。両系統が揃ったので
  `SessionRestorer.restoreLastSession` の「レイアウトに無い候補」ループに乗らない。
- AC #2 の根拠: 既存の `SessionRestorerTests`（レイアウト経由・候補経由の両方）が変更後も全通過。

検証: `swift test --skip Integration --skip FileWatcherTests` 1882 tests / 308 suites 全通過。
新テスト 3 件（`ViewerWindowManagerSessionRecordTests`）。`noteOpened(_:in:)` の `isRestorable`
ガードを外す変異で「スライド窓だけで開いても…入らない」が落ちることを確認（本文の実測欄参照）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
スライド窓をセッション記録から外した。「開いた」記録の入口を `ViewerWindowSessionSync.noteOpened(_:in:)` の 1 つに寄せ、セッションは既存の `isRestorable` で判定する。`noteClosedIfNoWindowRemains` は復元対象の窓が残っているかで判定し、通常窓を閉じてスライド窓だけ残れば消え、スライド窓を閉じても通常窓の記録は残る。アクティブ記録と rename も同じ述語で弾く。検証: swift test 1882 件全通過、実配線テスト 3 件を追加し、ガードを外す変異で落ちることを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
