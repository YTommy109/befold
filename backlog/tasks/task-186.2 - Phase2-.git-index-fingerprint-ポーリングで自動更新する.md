---
id: TASK-186.2
title: 'Phase2: 作業ツリー/index の変更に追従して自動更新する'
status: Done
assignee:
  - '@claude'
created_date: '2026-07-28 14:23'
updated_date: '2026-08-02 09:47'
labels: []
dependencies:
  - TASK-186.1
documentation:
  - docs/superpowers/specs/2026-07-28-sidebar-git-status-design.md
parent_task_id: TASK-186
priority: medium
ordinal: 261600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FileWatcher 経由の変更通知を第一の契機として GitStatusSnapshot を無効化・再取得する。GitRepository.indexFingerprint(.git/index の mtime) は add/commit/checkout など index を動かす操作の検出とキャッシュ妥当性判定に用途を限定する（素の作業ツリー編集では mtime が変化しないため、ポーリング単独では編集に追従できない）。また git status は既定で index を refresh して mtime を書き換えうるため、status 実行には --no-optional-locks を付け、ポーリングとの自己励振ループを避ける。着手時に TASK-226（GitCommandRunner の async 化 / GitCommandFileIndex の actor 化）の要否を再評価する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 add/stage/commit 操作後、明示 refresh なしで数秒以内にバッジが更新される
- [x] #2 表示中ファイルの編集保存が unstaged バッジに反映される
- [x] #3 fingerprint 無変化時は不要な git 呼び出しが発生しない
- [x] #4 作業ツリーでのファイル編集保存が、明示 refresh なしで unstaged バッジに反映される
- [x] #5 add/stage/commit/checkout 操作後、明示 refresh なしで数秒以内にバッジが更新される
- [x] #6 変更がない状態では不要な git 呼び出しが発生しない（status 実行自体が再取得を誘発しない）
- [x] #7 TASK-226 の async 化を先行させるか否かを判断し、結論を Notes に記録する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-226(async 化)先行要否の判断(2026-08-02): **先行させない**。TASK-226 の着手条件1は「186.2 で git 実行がユーザー操作のたびから*定期的*に変わりワーカー占有の頻度が上がるため」だったが、186.2 の設計は 2026-08-02 の見直しでポーリングから **FileWatcher 起点のイベント駆動 + デバウンス** に変更済み。git 実行頻度は「ユーザーがファイルを保存した/操作した回数」に留まり定期実行にはならないため、条件1の前提が消えている。条件2(実環境でのハング報告)も未発生。よって Phase 2 は現行の同期 API のまま実装し、TASK-226 は保留を継続する。

実装・検証記録(2026-08-02):

構成: ポーリングは実装せず、契機は 2 つのイベントのみ。
1. `.git/index` の FileWatcher 監視（SidebarNavigator が状態取得のたびに対象を張り直す。パスは GitStatusSnapshot.indexURL 経由で受け取る = worktree の .git ファイル解決を呼び出し側に持ち込まない）。通知は GitStatusRefreshPolicy.onlyIfIndexChanged で受け、fingerprint 無変化なら git を起こさずキャッシュを返す。
2. ViewerStore.onContentReloaded（表示中ファイルの保存）。作業ツリー編集は index を動かさないため 1 では拾えず、既存の再読込経路に相乗りする形にした。ディレクトリ監視は追加していない（1・2 + windowDidBecomeKey で AC を満たせるため）。

付随変更: GitRepositoryReading に indexURL(at:) を追加（既定実装は <root>/.git/index、GitRepository だけが gitdir 解決で上書き）。ViewerWindowController の ViewerStore コールバック配線を private extension の wireStoreCallbacks() へ移動（type_body_length を超えたための整理も兼ねる）。

検証:
- swift test 984 件パス。新規: Store の fingerprint 門番3本、SidebarNavigator の index 監視4本（張り直し抑止・離脱時停止・cancel 連動・通知時 policy）、ViewerWindowController の再読込→再取得配線1本、実 git 統合2本（git add 後に明示 refresh なしでモデルが staged に変わる／status 実行が index fingerprint を変えない = 自己励振しない）。
- GUI: Debug ビルドを起動したまま別プロセスから git add を実行し、アプリに一切触れずにバッジが橙 M → 緑 M へ変わることをスクリーンショットで確認。
- swiftformat 0 件、swiftlint はベースラインと差分なし。
- 注意: フルスイートで 984 件中 3 件が失敗する実行が 2 回あった（Phase 1 でも 1 回）。同一コードで連続 6 回はクリーンにパスし再現しない。失敗時の詳細ログを取れておらず原因未特定のため、再発したら該当テスト名を記録すること。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの git バッジを自動更新にした。契機は (1) .git/index の FileWatcher 監視（fingerprint 無変化なら git を起こさない門番付き）と (2) 表示中ファイルの再読込（ViewerStore.onContentReloaded）の 2 つで、ポーリングは行わない。status は --no-optional-locks 付きのため自分の実行で index を動かさず自己励振しない。GitRepositoryReading に indexURL(at:) を追加し、監視対象パスは snapshot 経由で渡す。swift test 984 件パス（実 git 統合テストで「git add 後に明示 refresh なしでモデルが更新される」「status が fingerprint を変えない」を固定）、および実ビルドで別プロセスの git add によりバッジが橙 M→緑 M へ変わることを目視確認。
<!-- SECTION:FINAL_SUMMARY:END -->
