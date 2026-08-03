---
id: TASK-268
title: pathKey と selection が非正規化のままで、TASK-265 の効果を取りこぼしている
status: To Do
assignee: []
created_date: '2026-08-03 13:50'
updated_date: '2026-08-03 13:51'
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
- [ ] #1 FileListEntry.pathKey が native 裏打ちの url から計算されている
- [ ] #2 Finder/CLI 起動経路でも FileListModel.selection が native 裏打ちの URL になる
- [ ] #3 SwiftUI の identity になる URL を native 裏打ちに揃える責務が、消費側ではなく列挙の境界（またはそれに準ずる単一の場所）にある
- [ ] #4 344 件フォルダーで pathKey 辞書引き・PreviewTargetResolver の走査それぞれの改善値を実測して Notes に残す
<!-- AC:END -->
