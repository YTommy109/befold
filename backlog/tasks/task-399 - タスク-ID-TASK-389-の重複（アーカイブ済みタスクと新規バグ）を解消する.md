---
id: TASK-399
title: タスク ID TASK-389 の重複（アーカイブ済みタスクと新規バグ）を解消する
status: Done
assignee: []
created_date: '2026-08-09 13:34'
updated_date: '2026-08-10 00:42'
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
- [x] #1 リポジトリ内（archive 含む）でタスク ID が一意になっている
- [x] #2 TASK-382 の Notes とコード内コメントの TASK-389 参照が、それぞれ正しいタスクを指している
- [x] #3 重複が生じた経緯（採番ガードが効かなかった理由）を Implementation Notes に記録する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
重複の経緯（実測）: backlog CLI の採番は backlog/tasks（と drafts）だけを走査し、archive / completed 配下を見ない。一時タスクを作って 2 回実測したところ、archive に TASK-400 が居る状態でも新規作成は TASK-400 を割り当てた。このため「そのとき最大番号のタスクをアーカイブする」と番号が空きに戻り、次の create が同じ ID を再発行する。実際の経緯は 6ec24ec で TASK-389（行番号表示）を起票 → 24c1cdf（doc/adr ブランチ）で archive へ移動 → 3df0d41 で TASK-389（スクロール位置）を起票。CLAUDE.md の check_active_branches は他ブランチの active タスクを見るガードであり、archive の不可視性は防げない。

解消の方向: アーカイブ側を大きい番号へ上げると「最大番号が archive に居る」状態が続き罠が即再現するため、アクティブ側を新 ID へ移した（archive の ID がアクティブ最大値より小さければ再発行されない）。TASK-389（スクロール位置）→ TASK-400、参照 11 ファイルを追随。archive の TASK-389（行番号表示・取り下げ）はそのまま。

同型 2 件目を同時に検出: 新設した検査スクリプトが TASK-390 の重複（archive「スクロール位置の保存粒度を再検討する」/ active「リネーム後の再描画が…巻き戻す」）も検出したため、同じ方針で active 側を TASK-401 へ改番した。TASK-382:98 と TASK-388:30 の「旧 TASK-390」参照はアーカイブ側を指すため据え置き。

構造対策: scripts/check-task-id-uniqueness.sh を追加し、pre-commit（setup-git-hooks.sh）へ組み込んだ。frontmatter の id を backlog 配下全体（tasks/drafts/archive/completed）から集めて重複を落とす。--self-test 付き。ID 書き換えは backlog CLI に手段が無く、PreToolUse フックも backlog md の直接 Edit を止めるため、git mv + perl で行った。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
backlog CLI の採番が archive / completed を走査しないことが重複の原因（実測で確認）。アクティブ側を改番して解消した: TASK-389（スクロール位置）→ TASK-400、TASK-390（リネーム後の巻き戻り）→ TASK-401。アーカイブ済みの取り下げタスク 2 件は元の ID を保持し、コード・テスト・関連タスクの参照 11 ファイルを追随させた。再発は scripts/check-task-id-uniqueness.sh（pre-commit 組み込み・--self-test 付き）で落ちる。検証: 同スクリプトで 492 件の ID 一意性を確認、BefoldApp/ に旧 ID 参照ゼロ、swift build 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
