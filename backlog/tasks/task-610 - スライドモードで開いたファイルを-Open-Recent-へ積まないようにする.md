---
id: TASK-610
title: スライドモードで開いたファイルを Open Recent へ積まないようにする
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-09-11 07:29'
updated_date: '2026-09-11 08:49'
labels: []
dependencies: []
ordinal: 800000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スライドモードは通常のドキュメントウィンドウと異なり、プレゼンテーション用途で一時的にファイルを表示するための機能。現状は通常ウィンドウと同じ経路（ViewerWindowManager+OpenViewer.swift の noteOpened / noteNewRecentDocumentURL 呼び出し、ViewerWindowSessionSync.swift のリネーム同期）でファイルを開くため、スライドモードで開いたファイルも RecentDocumentsStore と NSDocumentController の Open Recent メニューに積まれてしまう。スライドモードでの一時的な閲覧が、通常の『最近使ったファイル』の並びを汚す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 スライドモード（ViewerWindowKind.slide）でファイルを開いても RecentDocumentsStore に記録されない
- [x] #2 スライドモードでファイルを開いても NSDocumentController.shared.noteNewRecentDocumentURL が呼ばれない（Open Recent メニューに現れない）
- [x] #3 スライドモード中にファイルがリネームされた場合も Open Recent へ積まれない
- [x] #4 通常のビューアウィンドウ（.viewer）で開いた場合の Open Recent への記録は従来どおり動作する
- [x] #5 ユニットテストでスライドモード時に記録されないことを確認する
- [x] #6 スライドモードで開いても「最近使ったリポジトリ」に git リポジトリが記録されない（スコープ拡大: 設計レビューで同型の穴として検出）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計レビュー（/review-design）の結論を反映した方針。除外の判定は各履歴ストアの中へ置き、イベントハンドラ側に if を散らさない。

1. `ViewerWindowKind` に 5 つ目の述語 `recordsUsageHistory`（`self == .viewer`）を足す。呼び出し側で `kind == .slide` と書かせないという既存の規約（型の doc コメント）に合わせる。Open Recent と「最近使ったリポジトリ」の両方をこの 1 つの述語で扱う。
2. `RecentDocumentsStore.noteOpened` / `noteRenamed` に `kind: ViewerWindowKind` を**必須引数**で足し、ガードを store の中へ集約する。デフォルト引数にしないので、新しい呼び出し元は kind を渡さないとコンパイルが通らない。
3. あわせて `NSDocumentController.shared.noteNewRecentDocumentURL` を store の中へ移す。現在は 2 つの呼び出し側に散っており、「アプリ自前の履歴」と「システムの Recent」が別々に判定されうる。同じガードの内側に入れることで両者が構造的にずれない。
4. スライドでの rename は履歴へ積まないが、既に載っている項目が古いパスを指したまま残るのは防ぐ。`PathListDefaults.replace(old, with: new)`（位置を保って置換・未登録なら何もしない）を使い、先頭への昇格とシステム側への通知は行わない。
5. `RecentRepositoryRecorder.recordIfNeeded(for:controller:)` の先頭に `guard controller.kind.recordsUsageHistory else { return }` を置く。この関数は既に controller を受け取っているので引数の追加は不要で、スライド窓では git subprocess の起動自体も省ける。
6. 呼び出し側（`ViewerWindowManager+OpenViewer.swift` / `ViewerWindowSessionSync.swift`）は kind を渡すだけになり、`NSDocumentController` の行は消える。
7. テストは実配線で見る（述語だけのテストにしない）。`ViewerWindowManagerTests` に「スライドで開いても履歴に載らない」「スライドでの rename は昇格させず位置を保って置換する」、`ViewerWindowManagerRecentRepositoriesTests` に「スライドではリポジトリを記録しない」、`ViewerWindowKindTests` に述語の値を追加する。
8. `docs/dev/native-app-design.md` の `ViewerWindowKind` の記述（述語 4 つの列挙）を 5 つへ更新する。

設計レビューで検出した残りの穴（別タスクで起票する）: `openViewer` の `sessionStore.noteOpened(url)` が無条件で、`SessionRestorer.captureSavedState` の `savedURLs()` 経由でスライド窓が復元候補に入りうる。`currentSessionLayout` 側は `viewerPath` で落としているが savedURLs は別系統。未確認（復元本体の候補消費まで読んでいない）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 検証（実測）

`swift test --skip Integration --skip FileWatcherTests`: 1865 tests / 307 suites 全通過（exit=0）。

**担保が効くことをミューテーションで確認した。** `ViewerWindowKind.recordsUsageHistory` を
一時的に `true` へ書き換えて 4 スイートを回すと **19 件が失敗**し、戻すと 0 件になる。
落ちた内訳には、自前履歴（`recentURLs()`）・システム履歴（差し替えた通知先の spy）・
最近使ったリポジトリ（`entries()` と `controller.repositoryRoot`）がすべて含まれる。

swiftlint: main とのベースライン差分ゼロ（`origin/main` 49 件 = 作業ツリー 49 件、生 diff も空）。
swiftformat: 変更なし。markdownlint-cli2: 0 issues。

## 設計上の判断

- **`NSDocumentController` への通知をストアの中へ畳んだ。** 呼び出し側 2 箇所がそれぞれ
  直接叩いていたため、片方にだけ除外を足すと 2 つの履歴が食い違う形だった。同じ
  `guard` の内側に入れたので構造的にずれない。
- **通知先を差し替え可能にした（既定は `NSDocumentController`）。** 畳んだままだと
  AC #2「システムの Recent に積まれない」を自動テストで観測できず、さらに
  ユニットテストが実行環境の「最近使った項目」を書き換えてしまう。
- **`recordIfNeeded` は解決を始める前に弾く。** 消費側（`apply`）に判定を置くと、
  git の subprocess を待ってから結果を捨てることになる。
- **root 解決の回数はテストの測定器に使えなかった（実測）。** 当初 `rootLookupCount == 1` で
  測ろうとしたが実測 5 回で落ちた。`TrackedPathResolver` の既定実装からも解決が走るため。
  スライドと通常窓で別リポジトリを開き、記録されたルートを比べる形へ変えた。

## スコープ拡大の経緯

`/review-design` のチェックリスト項目 3（兄弟判断の全列挙）で「最近使ったリポジトリ」に
同型の穴を検出し、ユーザー確認のうえ AC #6 として取り込んだ。TASK-593.2 が
`recordTabGroup` 側だけを直していたため、per-open の入口が合流点を通っていなかった。

## コードレビュー（/code-review high）後の修正

- **回帰を 1 件直した。** スライド窓の rename を `PathListDefaults.replace` だけに通したため、
  新パスが既に履歴にあると同じパスが 2 回並ぶ形になっていた（従来の `remove + moveToFront` は
  重複を潰していた）。`replace` 自体が「置き換えた側の位置を残して他の出現を落とす」ように
  直した。同じ穴は `BookmarkStore.noteRenamed` にもあり、プリミティブ側で直したので両方塞がる。
- `noteRenamed` を「位置を保って置換 → `noteOpened`」の 1 経路へ畳んだ。種別の判定は
  `noteOpened` の 1 箇所だけになる。
- ワイヤードのフィクスチャ 5 箇所（`MockedViewerWindowManager` ほか）に `noteSystemRecent: { _ in }`
  を渡し、`swift test` が実行環境の「最近使った項目」を書き換えないようにした（差し替え口を
  作った動機と一致させた）。
- `didSwitchFileFrom` のスライド版と、`replace` の dedupe のテストを追加。
- 見送り: Clear Menu の `clearRecentDocuments` をストアへ折り込む指摘は、clear の入口が 1 つしか
  無いため見送り、コメントにその旨を明記した。
- 別タスクへ: `remapController` の `sessionStore.noteOpened` が無条件である点と、履歴ストア
  3 つの判定の置き場を 1 つの入口へ寄せる構造化は TASK-612 の Notes に追記した。

検証: `swift test` 1868 件全通過、swiftlint main 比ゼロ（49 = 49）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
スライド窓を利用履歴から外した。`ViewerWindowKind` に 5 つ目の述語 `recordsUsageHistory` を足し、判定は各履歴ストアの中へ置いた（`RecentDocumentsStore` は `kind` を必須引数で受け、`RecentRepositoryRecorder` は git 解決を始める前に弾く）。あわせて呼び出し側 2 箇所に散っていた `NSDocumentController` 通知をストアへ畳み、自前履歴とシステム履歴が同じガードを通るようにした。スライドでの rename は履歴へ積まないが、既存項目が消えたパスを指したまま残らないよう位置を保って置換する。検証: swift test 1865 件全通過、述語を `true` へ壊すと 19 件が落ちることを実測、swiftlint は main 比ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
