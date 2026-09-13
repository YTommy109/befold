---
id: TASK-621
title: フォルダーをブックマークに追加できる経路（管理パネルへのドロップと CLI --bookmark）を塞ぐ
status: In Progress
assignee:
  - '@claude'
created_date: '2026-09-13 14:58'
labels: []
milestone: m-9
dependencies: []
priority: medium
type: bug
ordinal: 816000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
フォルダーはブックマークできない仕様（ウィンドウ側の ⌘D / ツールバーは ViewerCapabilities.canBookmark = isPresentingDocument で、フォルダー一覧の表示中は無効）なのに、2 つの経路がフォルダーを追加できてしまう。

- 管理パネルへの Finder からのドロップ: BookmarkManagerModel.dropDecision が「ディレクトリは受け入れる」。TASK-536.3 の設計スナップショット（docs/superpowers/specs/2026-09-12-bookmark-management-design.md の 4 節）が仕様と逆の判断をそのまま入れていた
- CLI の befold --bookmark <path>: CLIBookmarkCommand.run が存在確認しかしておらず、転送先の GUI（GlobalDisplayBroadcaster.addBookmarks）も判定しない

TASK-620.1 はこの前提（ディレクトリのブックマークがある）の上に BookmarkEntry.isDirectory の記録とフォルダーアイコンを作ったが、フォルダーを追加できないならその記録は不要になる。

ユーザー判断（2026-09-13）: 両方の入口で弾く / 既存のフォルダーのブックマークは消さずに表示し続ける（削除はユーザーが明示的に行う）/ TASK-620 の stacked PR（#662〜#666）の上に 1 本積む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 管理パネルへフォルダーをドロップすると追加されず、弾いた理由がパネル下部の 1 行に出る
- [ ] #2 befold --bookmark にフォルダーを渡すと追加されず、エラーメッセージを出して非 0 で終了する（GUI 起動中の転送経路でも追加されない）
- [ ] #3 フォルダーかどうかの判定が 1 箇所にあり、ドロップと CLI の両方がそれを使う
- [ ] #4 BookmarkEntry.isDirectory の記録とフォルダーアイコンの分岐を撤去し、アイコンは拡張子だけで決まる（既存データのフォルダーのブックマークは消えずに表示される）
- [ ] #5 native-app-design.md のブックマーク関連の記述（ドロップの受け入れ規則・種別の記録・アイコン）が実装に追随している
<!-- AC:END -->
