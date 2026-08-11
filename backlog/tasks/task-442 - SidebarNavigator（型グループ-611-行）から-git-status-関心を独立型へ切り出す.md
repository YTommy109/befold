---
id: TASK-442
title: SidebarNavigator（型グループ 611 行）から git status 関心を独立型へ切り出す
status: In Progress
assignee: []
created_date: '2026-08-11 05:06'
updated_date: '2026-08-11 07:36'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 100300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/befold/App/ の SidebarNavigator 型グループが 611 行（本体 364 / +Expansion 87 / +History 70 / +FolderNavigation 67 / +SelectionMemory 23）。scripts/check-type-group-size.sh の実測値で scripts/type-group-baseline.txt にも凍結されている。

TASK-428.4 で新設した responsibility-reviewer を、この型を分割したコミット e94161d へ実際に回した結果、次の指摘が出ている（TASK-428.4 の Implementation Notes に全文あり）。

- High: e94161d の分割は責務分離ではなく file_length 回避。型グループ合計は 446 → 449 行と実質不変で、SidebarNavigator が抱える関心は 8 個のまま（Base Directory 解決 / Git Status 取得・世代管理・index 監視 / File List 列挙・世代管理 / 選択 + extension 4 本の関心）。3 世代カウンタ（listingGeneration / baseDirectoryGeneration / gitStatusGeneration）と 5 個の注入クロージャを 1 型が兼ねている（規約の上限は 3 個）。
- 提案された切り口: git 関連（resolveGitRoot / loadGitStatuses / makeGitIndexWatcher / gitStatusGeneration / pendingGitStatusTask と MARK: - Git Status / MARK: - Base Directory 一式）を、既存の SidebarGitStatus.swift（145 行）へ寄せた独立型として切り出す。既に独立型として存在する SidebarExpansion.swift（172 行）が先例。これが行数と関心を同時に減らせる切り口と評価されている。
- Medium: ファイル分割の代償で本体の隠蔽が 2 箇所緩んでいる（SidebarNavigator.swift:90 の host が private → private(set)、:305 の folderEntryURL(forKey:) の private 撤去）。+History の applyHistoryEntry が担っているのは履歴の記録ではなく「履歴エントリのナビゲーション適用」であり、本体の File List 関心そのものという指摘。切り戻せば folderEntryURL は private に戻せる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 型グループの合算行数が 400 行以下になる（scripts/check-type-group-size.sh で確認できる）
- [ ] #2 ベースライン scripts/type-group-baseline.txt から SidebarNavigator のエントリが消える
- [ ] #3 git status / base directory の関心が独立型へ切り出されている
- [ ] #4 SidebarNavigator への注入クロージャが 3 個以下になっている
- [ ] #5 e94161d で緩んだ隠蔽（host / folderEntryURL(forKey:)）が private へ戻っている、または戻せない理由が記録されている
- [ ] #6 main との swiftlint 差分に真の新規が無く、swift test が既存どおり通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 設計レビュー結果 (実装前 / 2026-08-11)

/review-design を回し、responsibility-reviewer サブエージェントで案を評価した。当初案 (git 関心を 1 型へ切り出す) は 2 点で不成立と判明したため、サブタスク 442.1〜442.5 へ分割した。

### 実測

- 型グループ 611 行 (scripts/check-type-group-size.sh)。AC#1 の 400 行以下には 211 行の削減が必要。
- 当初案 (git 切り出し + 展開の切り出し) の見積もりは 420〜430 行で、AC#1 に届かない。履歴の独立型化まで実施して初めて 350〜400 に入る。
- SidebarRowBuilder.rows のプロダクト呼び出しは 2 箇所 (DirectoryLister.swift:96 / SidebarNavigator+Expansion.swift:29)。fileListModel.setEntries のプロダクト呼び出しは +Expansion.swift:40 の 1 箇所。
- resolveGitRoot の唯一の呼び出し元は refreshBaseDirectory (SidebarNavigator.swift:129)。git status 側は resolveGitRoot を使っていない。
- sequence の意味論 (recency + ディレクトリ対付け) は FileListModel.swift:193-212 に閉じており、SidebarNavigator は採番だけを担う。採番点を型の内側へ閉じることが分割の実質的な利得。
- swiftlint main ベースライン 71 件。

### 当初案の不成立点

1. **git status coordinator に基準ディレクトリ解決を同居させるのは誤り。** 書き込み先 (fileListModel.baseDirectory) も用途 (相対パスコピー・Quick Open のヘッダー) も git バッジ経路と別。同居させると新設時点で世代カウンタ 2 本・pending タスク 2 本を抱え、docs/dev/rules/product-code.md:127-130 に抵触する。→ 442.4 で 2 型に分ける。
2. **反映通知をクロージャ注入にするとクロージャが 4 個になる。** 既存の SidebarNavigatorHost を weak で直接持たせれば 2 個で済み、gitStatusDidApply() を必須メソッドにした TASK-330 の意図も薄まらない。→ 442.4 の AC。

### 既存の不変条件が既に破れている

SidebarExpansion.swift:15 の「行の生成は SidebarNavigator の 1 箇所だけが行う」は現状で成立していない (上記の 2 箇所)。DirectoryLister.buildEntries が組んだ行を applyRows が kind == .parentNavigation で分解し直して再度組んでいる。新型の doc に「1 箇所」と書いた時点で嘘になるため、先に 442.1 で一本化する。

### 却下した案

- folderEntryURL(forKey:) を展開の型へ移す案は却下。matchingEntryURL(for:) と対の「FileListModel.entries に対する検索述語」であり、片方だけ移すと履歴適用・フォルダ移動がツリー表示の型へ問い合わせる形になって依存の向きが逆になる。→ 442.2 で両方を FileListModel へ移す。
- テスト互換のための委譲プロパティ (pendingGitStatusTask 等) は残さない。残すと本体に git 側 stored への参照が残り、「cancelPendingListing が 1 行へ畳めるか」という分離の判定基準が使えなくなる。

### AC#5 の扱い

folderEntryURL(forKey:) は 442.2 で FileListModel へ移り、SidebarNavigator から消える (private に戻す以上の解決)。host は +FolderNavigation / +History が読むため Swift の private (ファイルスコープ) では戻せず、private(set) のまま理由を doc に記録する。緩んだのは読み取り側だけで、書き込みを attach(to:) に限定する当初の意図は保たれている。
<!-- SECTION:NOTES:END -->
