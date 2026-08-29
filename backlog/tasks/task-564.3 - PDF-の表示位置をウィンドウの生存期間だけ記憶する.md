---
id: TASK-564.3
title: PDF の表示位置をウィンドウの生存期間だけ記憶する
status: To Do
assignee: []
created_date: '2026-08-29 00:41'
labels: []
dependencies:
  - TASK-564.1
parent_task_id: TASK-564
priority: medium
type: feature
ordinal: 817000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 目的

PDF を見ている途中で別のファイルへ移り、また戻ってきたときに、離れる直前の表示位置で開く。ウィンドウを閉じたら忘れてよく、次に開いたときは 1 ページ目でよい。

## 前提と、既存の仕組みに乗せられない理由

既存のスクロール位置記憶は `befold/App/ScrollPositionStore.swift` にあるが、**これは UserDefaults に永続化する**（キー `"ViewerScrollPositions.rendered"` / `"ViewerScrollPositions.source"`、値は `Double` の scrollTop、`PathKeyedDictionary`）。今回の要望は「永続化しない」なので、このストアへ相乗りしてはならない。相乗りすると次回起動時にも位置が復元され、要望と逆の振る舞いになる。

同様に、per-file 設定を束ねる `befold/App/PerFileStateStore.swift`（`zoom` / `displayMode` / `scrollPosition` / `sidebar` / `windowFrame`）も永続ストアの束ねなので、そのまま足すと永続化される。**永続化しない状態の置き場が既存に無い**ことが、このタスクの主要な設計判断になる。

また `viewer-src/scroll.ts` の scrollTop ベースの記憶は `.viewer` か `#diagram-wrap.code-body pre code` を対象にしており、`PDFView` へ移った PDF はそもそもこの経路に乗らない。

## 論点（実装着手前に `/review-design` で詰める）

- **保持する値**: ページ番号だけでは足りず、ページ内のオフセットも要る（`PDFView.currentDestination` が `PDFDestination` としてこれを表す）。拡大縮小（TASK-564.4）と回転（TASK-564.5）の状態も同じ「戻ってきたときの見え方」に含めるべきかを決め、含めるなら 1 つの値型にまとめる。バラバラの辞書を増やさない。
- **置き場所**: ウィンドウの生存期間に一致するスコープが要る。`ViewerWindowController` が持つメモリ内の path → 表示状態の辞書が素直だが、既存の per-file ストア群との見分けが付く形にすること（「これだけ永続化しない」が読んで分かる名前・doc コメント）。
- **リネーム追従**: 既存ストアは `migrate(from:to:)` でファイルのリネームに追従している。ウィンドウ内の一時記憶が同じ追従を要るかどうかを決める。
- **ファイル監視による再描画**: 同じ PDF が外部で更新されて再描画されたとき、位置を保つのか先頭へ戻すのかを決める。ページ数が減って現在ページが範囲外になる場合の扱いも決めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PDF を途中まで見て別ファイルへ移り、戻ると離れる直前の表示位置で開く
- [ ] #2 ウィンドウを閉じて同じ PDF を開き直すと 1 ページ目から表示される
- [ ] #3 表示位置が UserDefaults へ書かれないことを検証するユニットテストがある（この判断が破れたら落ちるもの。分離した `UserDefaults` 上で書く）
- [ ] #4 記憶した位置のページが存在しなくなった場合（ファイル更新でページ数が減った等）に範囲内へ丸められ、クラッシュしない
- [ ] #5 複数のウィンドウで同じ PDF を別の位置で開いても互いの記憶を壊さない
<!-- AC:END -->
