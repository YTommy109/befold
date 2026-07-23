---
id: TASK-116
title: CLI バイナリ分離ブランチのテストコード整理と CI ハング解消
status: To Do
assignee: []
created_date: '2026-07-23 23:16'
labels:
  - test
  - ci
  - cleanup
dependencies: []
priority: high
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
テストコードレビュー(2026-07-24)で検出された問題をまとめて解消する。作業は `cli-binary-separation` ブランチのコミット群の上に積む。

## 背景

`cli-binary-separation` ブランチの CI (run 30050150520) が「テストを実行する」ステップで 9.5 時間以上ハングし、完了しない。調査の結果、テストスイートが遅いのではなく `swift test` がデッドロックしていることが判明した。

実測値:
- 過去 40 回の CI 実行はすべて 2〜5 分。30 分を超えたことは一度もない
- テスト実行そのものは 590 tests / 74 suites を 37 秒(TSan 付きでも 74 秒)
- ビルド 58 秒、SwiftFormat 32 秒

つまり是正すべきは「遅さ」ではなく「ハングし得る構造」と「タイムアウトしても失敗しない構造」である。

## 本ブランチ由来の問題と、それ以前からある問題の切り分け

`git diff main...HEAD -- BefoldApp/befoldTests BefoldApp/befoldCLITests` で確認した結果:

**本ブランチで新規に持ち込まれた問題**(サブタスク .1 〜 .4):
- `befoldCLITests/CLIAppLauncherTests.swift`(新規 +298 行) の `captureStderr` デッドロック
- `befoldTests/BefoldRootCommandIntegrationTests.swift`(+107 行の書き換え) の実サブプロセス化に伴うタイムアウト保護欠如
- `befoldCLITests/TestSupport.swift`(新規 +49 行) による共有ヘルパーの二重定義
- `befoldCLITests/BefoldCLICommandTests.swift` は**未コミット(untracked)**のまま

**ブランチ以前から存在する問題**(サブタスク .5 〜 .9):
- ポーリングヘルパーが silent にタイムアウトする構造
- thread-sanitizer ジョブの慢性的な失敗
- 固定 sleep・過大フィクスチャ・実時間性能アサーション
- Unit/Integration 命名の不統一、タスク番号コメントの混入

## 進め方

.1 は CI を復旧させる最優先項目で、他のすべてをブロックする。.1 だけを先に単独 PR で出し、残りは順次積む。
<!-- SECTION:DESCRIPTION:END -->
