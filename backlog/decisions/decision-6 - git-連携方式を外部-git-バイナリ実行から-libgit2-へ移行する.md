---
id: decision-6
title: git 連携方式を外部 git バイナリ実行から libgit2 へ移行する
date: '2026-08-10 13:12'
status: accepted
---
## Context

本決定の記録は `docs/adr/0006-git-integration-via-libgit2.md` にある。
背景・呼び出し全量・トレードオフ・フォールバック方針はすべて ADR 側を参照すること。
実装タスクは TASK-435。

## Decision

git 連携（サイドバーのステータスバッジ、差分表示、Quick Open の追跡ファイル索引、
worktree 一覧）を、外部 git バイナリの `Process` 実行から libgit2 ベースの実装へ移行する。
バインディングは SwiftGitX を先に評価し、必要な API が塞げない場合に libgit2 直接
（static XCFramework + `.binaryTarget`）へ降りる。SwiftGit2 は採用しない。

採用根拠は「libgit2 の最新 git 機能への追従が速いから」ではない（実際には遅く、
jujutsu は v0.30.0 で libgit2 を削除して gitoxide へ移行している）。Swift から使える
現実的な選択肢が libgit2 系しかなく、未対応機能の大半が読み取り専用ビューアに
当たらないため。詳細は ADR 0006 の該当節を参照。

## Consequences

外部プロセス起因の手当て（fsmonitor/hooksPath 遮断・環境変数遮断・プロセスグループ
kill）が不要になり、ユーザー環境の git バージョンと `~/.gitconfig` への依存が切れる。
Mac App Store 配布の最大の障害も外れる。

一方で porcelain=v2 相当の再実装が必要になり、partial clone / reftable のリポジトリは
開けない。開けない場合は git 機能のみ静かに無効化し、通常のビューアとして継続する
（ADR 0006 の Fallback 節）。
