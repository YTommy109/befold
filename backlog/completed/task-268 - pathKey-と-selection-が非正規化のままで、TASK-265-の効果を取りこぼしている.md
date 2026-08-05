---
id: TASK-268
title: pathKey と selection が非正規化のままで、TASK-265 の効果を取りこぼしている
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-03 13:50'
updated_date: '2026-08-03 14:25'
labels:
  - performance
dependencies:
  - TASK-267
priority: high
type: bug
ordinal: 459000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review high で確認された、TASK-265 の修正の取りこぼし 3 点。いずれもメインスレッドの Unicode 正規化ハッシュが残る。

## 1. FileListEntry.pathKey が引数の url から計算されている（FileListEntry.swift:34）
line 31 で `self.url = url.nativeBackedFileURL` としながら、line 34 は `pathKey = url.normalizedPathKey` と**引数の** url を読んでおり、pathKey は NSString 裏打ちのまま。FileListView.entryList は行ごとに `gitStatuses[entry.pathKey]` と `gitFolderStatuses[entry.pathKey]` の 2 回辞書引きし、SidebarNavigator.swift:204/254/262/271 は `$0.pathKey == key` を O(n) で走査する。

実測（344 件・日本語名）: 現状 4.3ms / 344 lookups、`self.url.normalizedPathKey` にすると 0.23ms。344 件フォルダーの 1 描画あたり約 8.6ms のメインスレッド仕事が残っている。**1 トークンの修正**。

## 2. FileListModel.selection が生の URL のまま（Finder/CLI 起動経路）
ViewerWindowController.swift:181 が外部から渡された（CFURL 裏打ちの）URL をそのまま `selection:` に入れ、SidebarNavigator.restoreSelection（line 331）も生の URL を代入する。refreshFileList は selectionStillValid が false のときしか matchingEntryURL で置き換えないため、Finder/CLI で開いたファイルは選択が有効なまま = 生の URL がセッション中ずっと残る。PreviewTargetResolver.resolve は body 評価のたびに `entries.first(where: { $0.id == selection })` を走らせる。

実測（344 件）: 生 selection 1.93ms/パス、selection も正規化すると 0.035ms（修正前は 2.93ms なので効果の約 98% を取り逃している）。

## 3. 正規化が列挙の境界ではなく 1 つの消費側にだけ入っている
QuickOpenView の ForEach は候補 URL を行 ID にしており（id: \.element.url）、その URL は DirectoryLister.allEntriesSorted / FileManager 列挙由来で NSString 裏打ちのまま。候補数に上限があるため現状のコストは限定的だが、「SwiftUI の identity になる URL は native 裏打ち」という不変条件が FileListEntry.init 1 箇所でしか守られておらず、次の消費側が同じ地雷を踏む。

## 依存
実装は TASK-267（nativeBackedFileURL の NFC 保持）の方針決定後に行う。ヘルパーの実装が変わると 1・2 の呼び出し方も変わるため。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 FileListEntry.pathKey が native 裏打ちの url から計算されている
- [x] #2 Finder/CLI 起動経路でも FileListModel.selection が native 裏打ちの URL になる
- [x] #3 SwiftUI の identity になる URL を native 裏打ちに揃える責務が、消費側ではなく列挙の境界（またはそれに準ずる単一の場所）にある
- [x] #4 344 件フォルダーで pathKey 辞書引き・PreviewTargetResolver の走査それぞれの改善値を実測して Notes に残す
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-03・TASK-267 と同じコミット）

1. **pathKey**: `pathKey = self.url.normalizedPathKey` に変更（引数の url ではなく native 裏打ちに揃えた self.url から作る）。resolvingSymlinksInPath().path も native 裏打ちのまま返ることを実測で確認（before: contiguous=false / after: true）。
2. **selection**: FileListModel.selection を計算プロパティにし、setter で nativeBackedFileURL を通す。init も storedSelection へ直接代入して同じ処理を通す。ViewerWindowController の起動経路・restoreSelection・matchingEntryURL のいずれから書かれても揃うため、書き込み側を個別に直す必要がない。
3. **境界**: DirectoryEnumeration.sortedContents（FileManager 列挙の出口＝URL がアプリへ入る唯一の境界）で map(\.nativeBackedFileURL) する。これでサイドバー一覧だけでなく Quick Open の候補 URL も揃う。FileListEntry.init 側の正規化は、列挙を経由しない親移動エントリ等のために残す（連続 UTF-8 なら早期 return するので二重コストにはならない）。

### 実測（344 件・backlog/tasks）
| 経路 | 修正前 | 修正後 |
|---|---|---|
| pathKey 辞書引き（344 行 × 2 回＝1 描画ぶん） | 5.99 ms | 1.65 ms |
| PreviewTargetResolver の走査（1 パス） | 0.92 ms | 0.012 ms |

### 確認済み
- swift test 1008 tests / 151 suites green（FileListEntryTests に pathKey の裏打ちアサートを追加）
- swiftlint ベースライン差分ゼロ / xcodebuild 成功
- GUI: backlog/ で tasks 行を 24 回往復する同一手順の sample で idle 663 / 2632、_normalizedHash 9
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
pathKey を native 裏打ちの self.url から作り、FileListModel.selection を setter で揃え、正規化の責務を DirectoryEnumeration.sortedContents（列挙の境界）へ移した。344 件の実測で pathKey 辞書引き 5.99ms → 1.65ms、選択の走査 0.92ms → 0.012ms。swift test 1008 green / swiftlint ベースライン差分ゼロ / xcodebuild 成功 / GUI sample も同等以上。
<!-- SECTION:FINAL_SUMMARY:END -->
