---
id: TASK-399
title: タスク ID TASK-389 の重複（アーカイブ済みタスクと新規バグ）を解消する
status: To Do
assignee: []
created_date: '2026-08-09 13:34'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 652000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の CONFIRMED 指摘。

`backlog/archive/tasks/task-389 - 行番号表示の粒度をアプリ全体の共有設定に揃える.md`（取り下げ済み）と `backlog/tasks/task-389 - スクロール位置の非同期通知がファイル切替直後に切替先のキーへ切替前の位置を書きうる.md`（2026-08-09 起票の bug、Done）が同じ `id: TASK-389` を持つ。

TASK-382 の Notes は「TASK-389（行番号表示）は取り下げてアーカイブした」と旧タスクを指す一方、コード・テスト内のコメント 5 箇所（ViewerRenderer.swift:17、ViewerWindowController.swift:581、WebViewCommandController.swift:112、テスト 2 ファイル)は新しいスクロールバグの意味で TASK-389 を参照している。ID からタスクを引くと誤った方に当たりうる。

CLAUDE.md の採番ルール（check_active_branches による衝突回避）が機能しなかった経緯の確認も含め、どちらかへ新 ID を振り直し、参照を追随させる。backlog CLI で扱えない場合（アーカイブ側のリネーム等）のみ手動編集を検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 リポジトリ内（archive 含む）でタスク ID が一意になっている
- [ ] #2 TASK-382 の Notes とコード内コメントの TASK-389 参照が、それぞれ正しいタスクを指している
- [ ] #3 重複が生じた経緯（採番ガードが効かなかった理由）を Implementation Notes に記録する
<!-- AC:END -->
