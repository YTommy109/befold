---
id: TASK-435
title: git 連携を外部 git バイナリ実行から libgit2 ベースへ移行する
status: To Do
assignee: []
created_date: '2026-08-10 13:13'
updated_date: '2026-08-10 13:29'
labels:
  - refactor
dependencies: []
priority: medium
type: task
ordinal: 507950
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold の git 連携（サイドバーのステータスバッジ、差分表示、Quick Open の追跡ファイル索引、worktree 一覧）は、すべて GitCommandRunner が /usr/bin/git を Process で起動する方式で実装されている。この方式はライブラリ方式との比較検討を経ずに採用されており（docs/adr/0005 の Context 参照）、次のコストを恒常的に負っている。

1. GitCommandRunner（300 行）の大半が外部プロセス起因の手当て — core.fsmonitor/core.hooksPath による任意コマンド実行の遮断、環境変数の非継承と PATH 固定（TASK-148）、タイムアウト時のプロセスグループ kill と fd 回収（TASK-155）、DispatchSemaphore によるブロック待ち（TASK-226 が未解決）
2. ユーザー環境の Xcode Command Line Tools の git に依存する — バージョン差・未インストール・~/.gitconfig の内容が挙動に影響する
3. Mac App Store 配布では原理的に成立しない — サンドボックス下の子プロセスは PowerBox 由来の user-selected アクセスを継承しないため、ユーザーがフォルダを選んでも子プロセスの git はそれを読めない

方針・トレードオフ・不採用としたライブラリ（SwiftGit2）の根拠は docs/adr/0005-git-integration-via-libgit2.md（decision-6, Proposed）に記録済み。バインディングは SwiftGitX を先に評価し、必要な API が塞げない場合に libgit2 直接（static XCFramework + .binaryTarget）へ降りる。

現状の呼び出しは 13 箇所ですべて読み取り専用（commit/add/checkout/fetch なし）のため、認証・credential helper・push 系は移植対象外。差分の生テキストは Swift 側で構造化せず viewer.js の parseUnifiedDiff が JS 側でパースしているため、git_diff_to_buf で unified diff を出せれば JS 側は無改修で済む見込み。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ADR 0005 の「実装前に潰すべき未確認事項」4 点が実測で解消され、結果が Implementation Notes に記録されている
- [ ] #2 docs/adr/0005 の呼び出し一覧 13 箇所すべてがライブラリ実装に置き換わり、プロダクトコードから /usr/bin/git の Process 実行が消えている
- [ ] #3 -U1000000 相当の全文コンテキスト diff が再現され、viewer.js の parseUnifiedDiff が無改修で従来どおり描画できる（差分表示の既存テストが通る）
- [ ] #4 porcelain=v2 相当のステータス取得が再実装され、GitStatusReader の既存テストが同等の期待値で通る
- [ ] #5 worktree 列挙・submodule 境界検出・比較起点の解決が従来と同じ結果を返す
- [ ] #6 GitCommandRunner の外部プロセス起因の手当て（fsmonitor/hooksPath 遮断・環境変数遮断・プロセスグループ kill）が不要になったぶん撤去されている
- [ ] #7 起動時に GIT_OPT_SET_SEARCH_PATH で global/system/xdg config を無効化し、ユーザーの ~/.gitconfig に依存しないことがテストで担保されている
- [ ] #8 SwiftGitX を先に評価し、必要な API が塞げるかの判断結果（採用したバインディングとその理由）が Implementation Notes に記録されている
- [ ] #9 libgit2 が開けないリポジトリ（partial clone / reftable）を模したフィクスチャで、クラッシュせず・モーダルを出さず・通常のビューアとして動作することがテストで担保されている
- [ ] #10 リポジトリを開けなかった場合に .unavailable 相当へ写像する箇所が 1 関数に集約されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 関連タスク

- TASK-226（GitCommandRunner の async 化）: 本タスクが着地すれば subprocess 待ちそのものが消えるため、TASK-226 は前提から見直しになる。どちらを先にやるかは本タスクの採否が決まってから判断する（先に TASK-226 を実施すると、撤去予定のコードに対して 18 ファイル規模の改修を投じることになる）。
- TASK-397（オープンソースのままバイナリを販売する場合の配布・課金モデルを ADR にまとめる）: Mac App Store 配布を選ぶ場合、本タスクは必須の前提条件になる。ただし MAS 対応には他にも App Sandbox 有効化（security-scoped bookmark が現状 0 件）、Sparkle 撤去、CLI（/usr/local/bin への symlink + NSAppleScript 昇格、DistributedNotificationCenter）の扱いという別の障害があり、本タスク単独では MAS 対応は完了しない。

## 着手条件

MAS 対応と切り離しても、上記 1・2 のコスト解消という独立の価値がある。ただし ADR 0005 は Proposed のままであり、着手前にユーザーと方針を確定すること。

## 方針確定（2026-08-10）

ADR 0005 は Accepted。libgit2 ベースへの移行を採用する。

採用理由が「最新 git 機能への追従が速いから」ではない点に注意（ADR 0005 の該当節を参照）。実際には jujutsu は v0.30.0 で libgit2 を削除して gitoxide へ移行しており、libgit2 の upstream 追従は遅い（sparse-checkout の issue は 12.3 年 open、reftable は未リリース、partial clone は未対応）。採用根拠は「Swift から使える現実的な選択肢が libgit2 系しかなく、かつ未対応機能の大半が読み取り専用ビューアに当たらない」こと。

これに伴い、開けないリポジトリのフォールバック（git 機能のみ静かに無効化し通常のビューアとして継続）を ADR の Fallback 節に追加し、AC #9 / #10 で担保する。
<!-- SECTION:NOTES:END -->
