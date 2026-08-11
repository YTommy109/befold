---
id: TASK-442
title: SidebarNavigator（型グループ 611 行）から git status 関心を独立型へ切り出す
status: To Do
assignee: []
created_date: '2026-08-11 05:06'
updated_date: '2026-08-11 05:25'
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
