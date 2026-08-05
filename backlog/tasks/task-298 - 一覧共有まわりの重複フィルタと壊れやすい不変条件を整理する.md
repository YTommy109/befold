---
id: TASK-298
title: 一覧共有まわりの重複フィルタと壊れやすい不変条件を整理する
status: Done
assignee: []
created_date: '2026-08-04 14:47'
updated_date: '2026-08-05 01:23'
labels:
  - git-filter
  - review-finding
  - refactor
dependencies: []
priority: low
ordinal: 496000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) のクリーンアップ指摘 3 件（2026-08-04）＋同領域の追加指摘 2 件（2026-08-05 の /code-review high、末尾 4・5）。

1. (CONFIRMED) .shared の場合、FolderListingView.visibleEntries が、サイドバーが既に同じ FileListFilter で絞り込んだ entries に対して同じ apply を再実行しており、body 評価のたびに O(n) のグロブ + git ステータス判定が二重に走る（FolderListingView.swift:67）。空状態オーバーレイに必要な「絞り込み前後の差」はフラグや件数で渡せる。
2. (PLAUSIBLE) entriesDirectory を entries.didSet の中で currentDirectory から刻んでおり、「currentDirectory を書き換える 4 箇所すべてが listingGeneration を bump する」という別オブジェクト側の不変条件に依存している。performListing は列挙した directory を知っているのに捨てている。setEntries(_:for:) 相当にすれば不変条件がローカルに閉じる（FileListModel.swift:22）。
3. (CONFIRMED) ウォッチャーファクトリのクロージャ型 `(URL, @escaping @MainActor @Sendable () -> Void) -> FileWatching` が 2 ファイル 4 箇所に直書きされている。typealias にまとめる（GitIndexWatch.swift:17, SidebarNavigator.swift:58 ほか）。
4. (CONFIRMED) visibleEntries が body 評価のたびに DirectoryLister.appendingOpenFile を呼び、normalizedPathKey（resolvingSymlinksInPath＝コンポーネントごとの FS syscall）最大 3 回 + entries の O(n) 走査がメインスレッドで毎レンダ走る（FolderListingView.swift:71）。URL+NormalizedPathKey のヘッダが記録しているとおり、この種の毎レンダのパス処理は 300 件規模でメインスレッドを止めた実績がある。open file の追記は一覧を生成・キャッシュする側（resolveEntries か .task のキャッシュ層、openFile をキーに含める）へ移すか、少なくとも normalizedPathKey に触る前に非解決の安価なパス比較で early-return する。
5. (CONFIRMED) ensureCurrentFile が単一呼び出し元の 1 行ラッパー（DirectoryLister.appendingOpenFile の inout 適合のみ、SidebarNavigator.swift:273）になっている。refreshFileList の呼び出し箇所（:168）へインライン化してメソッドと inout 適合を除去する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 .shared のフォルダープレビューで同じフィルタが二重適用されない
- [x] #2 entries に紐づくディレクトリは、列挙した側が明示的に渡す形になっている
- [x] #3 ウォッチャーファクトリの型が 1 箇所の typealias で定義されている
- [x] #4 既存テストが通り、swiftlint の main 比ベースライン差分がゼロである
- [x] #5 open file の追記が毎 body 評価で normalizedPathKey を計算しない（生成・キャッシュ時に 1 回、または安価な早期 return）
- [x] #6 ensureCurrentFile が削除され、呼び出し箇所に直接 appendingOpenFile が置かれている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FolderListingView.visibleEntries: .shared のときは filter.apply を再実行しない
   (FileListModel.listingSource が渡す payload を visibleEntries(絞り込み済み)に変更)。
   openFile 追記で件数が増えたときだけ apply する(冪等性を利用し正しさを保つ)。
2. FileListModel: entries.didSet の entriesDirectory = currentDirectory 自動導出を廃止し、
   setEntries(_:for:) を新設。performListing の onApplied に列挙した directory を
   明示的に渡し、SidebarNavigator の呼び出し側(refreshFileList/navigateToFolder)を
   setEntries(_:for:) 経由に変更。
3. GitIndexWatch.WatcherFactory typealias を追加し、GitIndexWatch/SidebarNavigator の
   4 箇所の直書きクロージャ型をまとめる。
4. DirectoryLister.appendingOpenFile に生パス比較の早期 return を追加
   (resolvingSymlinksInPath 呼び出しを通常時ゼロに)。シンボリックリンク越しの
   正しさは実ファイル+実シンボリックリンクのテストで確認。
5. SidebarNavigator.ensureCurrentFile を削除し、refreshFileList に
   DirectoryLister.appendingOpenFile を直接インライン化。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。単純化検討: entriesDirectory の自動導出(#2)は「currentDirectory を書き換える
全箇所が事前に世代を進めている」という別オブジェクト側の不変条件への依存を、状態を増やさず
setEntries(_:for:) で局所化できたため採用。.shared の二重フィルタ(#1)は、SwiftUI の
@State キャッシュ化も検討したが、既存テストが displayedEntries/visibleEntries を
マウント無しの純粋関数として直接呼ぶ設計に依存しており、キャッシュ化するとその契約を
壊して広範なテスト書き換えが必要になるため見送り、.shared の payload 自体を
絞り込み済みにして再適用を条件付きでスキップする形にした(冪等性で正しさを担保)。

テスト: 新規 11 件追加(setEntries/entriesDirectory 分離、.shared 再フィルタ回避、
appendingOpenFile の生パス早期 return とシンボリックリンク越しの正しさ)。
swift test --skip Integration --skip FileWatcherTests: 1025/1025 パス。
xcodebuild build -scheme befold: 成功。
swiftlint: main とのベースライン差分ゼロ(diff 空)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
/code-review high の指摘 5 件(2026-08-04/05)をすべて解消。

1. FolderListingView.visibleEntries: .shared のときサイドバー(FileListModel.visibleEntries)が
   既に絞り込んだ一覧をそのまま使い、filter.apply を再実行しない(openFile 追記で件数が
   増えたときだけ apply、冪等性で正しさを担保)。FileListModel.listingSource は
   .shared(entries) ではなく .shared(visibleEntries) を渡すよう変更。
2. FileListModel.entriesDirectory の自動導出(entries.didSet 内の currentDirectory 参照)を廃止し、
   setEntries(_:for:) を新設。SidebarNavigator.performListing の onApplied に列挙した
   directory を明示的に渡すよう変更し、呼び出し元(refreshFileList/navigateToFolder)を
   setEntries(_:for:) 経由にした。
3. GitIndexWatch.WatcherFactory typealias を追加し、GitIndexWatch/SidebarNavigator
   4 箇所の直書きクロージャ型を統一。
4. DirectoryLister.appendingOpenFile に生パス比較の早期 return を追加。
   resolvingSymlinksInPath(シンボリックリンク解決の syscall)を通常時(一致時)は
   呼ばなくなる。シンボリックリンク越しの正しさは実ファイル+実シンボリックリンクの
   テストで確認済み。
5. SidebarNavigator.ensureCurrentFile(単一呼び出し元の 1 行ラッパー)を削除し、
   refreshFileList へ DirectoryLister.appendingOpenFile を直接インライン化。

検証: 新規テスト 11 件追加。swift test --skip Integration --skip FileWatcherTests で
1025/1025 パス。xcodebuild build -scheme befold 成功。swiftlint は main とのベースライン
差分ゼロ(diff 空、新規ファイルは type_body_length/file_length 超過を避けるため
DirectoryListerAppendingOpenFileTests.swift へ分離)。
<!-- SECTION:FINAL_SUMMARY:END -->
