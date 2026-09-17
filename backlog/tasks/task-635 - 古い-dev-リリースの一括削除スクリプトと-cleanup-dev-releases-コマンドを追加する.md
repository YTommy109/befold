---
id: TASK-635
title: 古い dev リリースの一括削除スクリプトと /cleanup-dev-releases コマンドを追加する
status: Done
assignee: []
created_date: '2026-09-17 07:50'
updated_date: '2026-09-17 07:51'
labels: []
dependencies: []
modified_files:
  - scripts/cleanup-old-dev-releases.sh
  - .claude/commands/cleanup-dev-releases.md
  - site/README.md
  - .claude/commands/release.md
type: chore
ordinal: 832000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-09-17 の手動クリーンアップで、GitHub Releases 一覧だけを対象の洗い出しに使うと R2 に孤立して残るオブジェクトを取りこぼし、GitHub Release／タグ／R2 オブジェクトを削除しても appcast.xml / appcast-develop.xml の item が自動連動せず壊れたダウンロードリンクが残ることが分かった。しきい値バージョン以前の dev リリースを GitHub Release／タグ・R2 オブジェクト・appcast item の4箇所で同一タグ単位にまとめて削除する、決定論的な唯一の入口が必要。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 scripts/cleanup-old-dev-releases.sh --dry-run <しきい値> が削除を行わず対象タグ一覧のみを表示する
- [ ] #2 スクリプトが GitHub Release／タグ・R2 オブジェクト（releases/<tag>/）・appcast.xml と appcast-develop.xml の該当 item を同一タグ単位で削除する
- [x] #3 /cleanup-dev-releases スラッシュコマンドからスクリプトを呼び出せる
- [x] #4 R2 管理用トークンの作成手順が site/README.md に記載されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
bash -n scripts/cleanup-old-dev-releases.sh で構文確認済み。実際の削除操作（gh / R2 API / appcast 書き戻し）は破壊的なため本セッションでは未実行——次回の実削除時に動作確認する。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
R2 を正として dev タグを列挙し、GitHub Release/タグ・R2 オブジェクト・appcast item を一括削除するスクリプトと /cleanup-dev-releases コマンドを追加。R2 管理用トークンの作成手順を site/README.md に、appcast 不整合時の対処を release.md のトラブルシュートに追記した。構文チェックのみ実施済み、実削除の動作確認は未実施。
<!-- SECTION:FINAL_SUMMARY:END -->
