---
id: TASK-435.1
title: libgit2 の SPM 依存と C シムを追加し、リポジトリオープンを 1 関数へ集約する
status: To Do
assignee: []
created_date: '2026-08-10 15:01'
labels:
  - refactor
dependencies: []
parent_task_id: TASK-435
priority: high
type: task
ordinal: 666000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-435（git 連携の libgit2 移行）の基盤サブタスク。個別の読み取り実装を移す前に、libgit2 を befold のビルドへ組み込み、全実装が共有する土台を用意する。

## 背景（親タスクの実測結果より）

- バインディングは SwiftGitX ではなく libgit2 の C API を直接使う。SwiftGitX には diff options / worktree 列挙 / submodule 列挙 / merge-base / ls-files 相当 / `git_libgit2_opts` がいずれも無い。
- 配布形態は ADR 0005 が想定した static XCFramework ではなく、`ibrahimcetin/libgit2`（libgit2 の C ソースを SPM の C ターゲットとしてビルドするパッケージ、`.library(name: "libgit2")` を公開）への依存とする。実測でフルビルド 6.4 秒・cmake 不要。
- `git_libgit2_opts` は C 可変長引数関数であり Swift から直接呼べない。固定引数へ落とす C シムターゲットが必要。
- リポジトリを開けない場合は `git_repository_open` が `-1` / klass=6(GIT_ERROR_REPOSITORY) / `unsupported extension name extensions.<名前>` で失敗する（partial clone / reftable / 未知の extensions すべて同じ形）。読み取り権限が無い場合は `-3`(GIT_ENOTFOUND)。いずれもクラッシュ・ハングはしない。

## スコープ

このサブタスクでは既存の git 呼び出しは 1 つも移さない。依存の追加と土台の設置、およびその土台のテストまで。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 libgit2 パッケージが Package.swift と project.yml の両方に追加され、`swift build` と `xcodebuild build -scheme befold` の両方が通る
- [ ] #2 git_libgit2_opts を固定引数で呼ぶ C シムターゲットが追加され、Swift から呼べることがテストで確認されている
- [ ] #3 起動時に GIT_OPT_SET_SEARCH_PATH で system/xdg/global の config 検索パスを無効化する処理が 1 箇所に置かれ、無効化後にユーザーの ~/.gitconfig が読まれないことがテストで担保されている（AC #7）
- [ ] #4 リポジトリを開いて後始末する処理が 1 関数に集約され、開けない場合に .unavailable 相当を返すことがテストで担保されている（AC #10）
- [ ] #5 開けないリポジトリのフィクスチャ（extensions.partialclone / 未知の extensions）を BefoldTestSupport に用意し、クラッシュせずモーダルも出さずに .unavailable 相当へ落ちることがテストで担保されている（AC #9）
- [ ] #6 libgit2 の初期化と終了（git_libgit2_init / git_libgit2_shutdown）の呼び出し回数と寿命が明示的に決められ、doc コメントに根拠が書かれている
<!-- AC:END -->
