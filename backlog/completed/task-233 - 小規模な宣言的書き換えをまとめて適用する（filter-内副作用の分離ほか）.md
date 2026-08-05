---
id: TASK-233
title: 小規模な宣言的書き換えをまとめて適用する（filter 内副作用の分離ほか）
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:16'
updated_date: '2026-07-31 22:29'
labels:
  - refactor
dependencies: []
priority: low
type: task
ordinal: 400000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
調査で挙がった小粒の命令的コードを宣言的に書き換える。(1) SessionRestorer.swift:108-122 — filter の述語内で onMissing を呼ぶ副作用を分離し、restoredPaths の構築もループから導出値に分ける（lazy 化などで noteClosed が呼ばれなくなる潜在バグの予防）。(2) ReferenceResolutionCoordinator.swift:86-93 — var 辞書 + ループを compactMapValues に。(3) GitRepository.swift:99-109 — gitdir 行探索を first(where:) + 解釈の分離に。(4) NavigationHistory.swift:80-92 — 隣接重複除去と index 補正の絡み合いを「生き残る index 集合」からの導出に。(5) HistoryButtonView.swift:96-107 — タイトルだけ分岐しアイコン生成は共通、という構造を明示化。いずれも挙動不変のリファクタで 1 PR にまとめられる規模。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 対象 5 箇所が宣言的な形に書き換えられ、既存テストが通る
- [x] #2 SessionRestorer の欠損ファイル通知（noteClosed 経路）が純粋な filter と分離されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SessionRestorer.restoreLayout: 実在判定を 1 度に固定してから onMissing 通知と existing 抽出を分離、restoredPaths も groups からの導出に
2. ReferenceResolutionCoordinator: var 辞書 + ループを compactMapValues に
3. GitRepository.gitDirectory: gitdir 行の探索(first(where:))と解釈を分離
4. NavigationHistory.deduplicateAdjacentEntries: 生き残る index 集合からの導出に
5. HistoryButtonView.menuLabel: タイトルだけ分岐しアイコン生成は共通、を明示化
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
5 箇所すべて挙動不変の書き換え。(1) SessionRestorer は『実在判定の結果を先に固定 → 消えた候補へ onMissing → 生存候補を抽出』の 3 段に分け、filter の述語内で副作用を起こす形を解消（lazy 化や短絡評価で通知が落ちる潜在バグの予防）。restoredPaths も groups からの導出に変更。(2) ReferenceResolutionCoordinator は compactMapValues。(3) GitRepository.gitDirectory は gitdir 行の探索(lazy + first(where:))と解釈を分離。(4) NavigationHistory は『生き残る index 集合』を先に決め、entries と currentIndex の双方をそこから導出（従来の『除去しながら index を減算』と等価: 隣接重複は推移的に等しいため直前要素との比較で足りる）。(5) HistoryButtonView.menuLabel はアイコン生成を共通化しタイトルのみ分岐。検証: swift test → 939 passed / swiftformat --lint パス。既存テストで挙動が固定されている箇所: NavigationHistoryTests『renameOccurred で隣接エントリが同一になった場合は重複が除去される』、SessionRestorerTests『復元時に消えていたファイルはウィンドウを開かずセッション記録からも取り除かれる』。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
調査で挙がった小粒の命令的コード 5 箇所を宣言的に書き換えた。特に SessionRestorer は filter 述語内の onMissing 副作用を分離し、通知が落ちうる構造を解消。swift test 939 件パスで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
