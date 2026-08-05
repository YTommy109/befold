---
id: TASK-298
title: 一覧共有まわりの重複フィルタと壊れやすい不変条件を整理する
status: To Do
assignee: []
created_date: '2026-08-04 14:47'
updated_date: '2026-08-04 16:37'
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
- [ ] #1 .shared のフォルダープレビューで同じフィルタが二重適用されない
- [ ] #2 entries に紐づくディレクトリは、列挙した側が明示的に渡す形になっている
- [ ] #3 ウォッチャーファクトリの型が 1 箇所の typealias で定義されている
- [ ] #4 既存テストが通り、swiftlint の main 比ベースライン差分がゼロである
- [ ] #5 open file の追記が毎 body 評価で normalizedPathKey を計算しない（生成・キャッシュ時に 1 回、または安価な早期 return）
- [ ] #6 ensureCurrentFile が削除され、呼び出し箇所に直接 appendingOpenFile が置かれている
<!-- AC:END -->
