---
id: TASK-588
title: スライドモードのマスクを行のツールチップと VoiceOver が迂回する
status: Done
assignee: []
created_date: '2026-09-05 02:48'
updated_date: '2026-09-06 09:40'
labels:
  - sidebar
  - slide-mode
dependencies: []
priority: medium
type: bug
ordinal: 853000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-587 で入れた `.redacted(.placeholder)` は描画される Text/Image しか隠さない。`FileListEntryRow` は `.help(entry.url.lastPathComponent)` を付けたまま（`FileListEntryRow.swift` のアイコンとファイル名の 2 箇所）で、`.help` は NSView の toolTip を設定するだけで `redactionReasons` を見ないため、スライドモード中に灰色の板へホバーすると本物のファイル名が AppKit ツールチップに出る。VoiceOver も Text の値をそのまま読み上げる。プレゼン投影中にカーソルを置いただけで漏れるので、TASK-587 AC#1「ファイル名が読めない」が破れている。

TASK-587 は「FileListEntryRow を無改変にする」方針で FileListView 側にマスクをかけたが、ツールチップは行の中で付けているため、この方針のままでは塞げない。行側で `@Environment(\.redactionReasons)` を読んでツールチップと accessibility を止めるのが最小の形（FolderListingView 側では redactionReasons が空なので挙動は変わらない）。

/code-review high（2026-09-05、TASK-586 のブランチ上）の指摘。main には PR #632 で入っている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 スライドモード中にサイドバー行へホバーしてもファイル名のツールチップが出ない
- [ ] #2 スライドモード中は VoiceOver がファイル名を読み上げない（accessibility の値も隠れる）
- [ ] #3 スライドモードでないとき、および FolderListingView（プレビュー内のフォルダー一覧）ではツールチップと読み上げが従来どおり出る
- [ ] #4 redactionReasons が非空のときにツールチップが空になることをテストが確認している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
見送り予定: スライドモードを専用ウィンドウへ移す（TASK-593）の決定により、サイドバー内のマスク自体が撤去対象になった。撤去サブタスク TASK-593.1 の完了時に見送りの要約付きで Done にする。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
見送り。TASK-593.1 でサイドバー内スライドモード（`FileListView` の `.redacted(.placeholder)` と `SidebarTransientState.isSlideMode`）を撤去したため、ツールチップと VoiceOver が迂回する対象そのものが消えた。`FileListEntryRow` の `.help` / accessibility には手を入れていない（スライドモード以外では従来どおり出るべきもので、変更する理由が無い）。スライドモードは専用ウィンドウ（TASK-593.2 / 593.3）へ移り、サイドバーを持たないためファイル名の漏れ経路自体が無い。
<!-- SECTION:FINAL_SUMMARY:END -->
