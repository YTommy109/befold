---
id: TASK-50
title: 'CI: build-and-test の FileWatcherIntegrationTests.detectsFileDeletion が不安定に失敗する'
status: To Do
assignee: []
created_date: '2026-07-17 09:11'
updated_date: '2026-07-17 09:12'
labels:
  - ci
  - bug
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/actions/runs/29568618799'
priority: high
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #239 の CI run https://github.com/YTommy109/befold/actions/runs/29568618799 (build-and-test / テストを実行する) で FileWatcherIntegrationTests.detectsFileDeletion が失敗した(count.get() → 6 が baseline → 6 を上回らない)。task-11 では thread-sanitizer ジョブの detectsFileModification のタイムアウト無視が原因だったが、今回は build-and-test ジョブ(非TSan)で別テスト(detectsFileDeletion)が失敗しており、同種だが別原因の可能性がある。task-35 の作業中に偶然検出したもので、task-35 の変更(ci.ymlのアクションバージョン更新)自体とは無関係と判断している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GHA run 29568618799 などの失敗ログから detectsFileDeletion 失敗の原因を特定する
- [ ] #2 アプリ本体(FileWatcher)側の問題かテスト側のタイミング/ポーリング設計の問題かを切り分ける
- [ ] #3 原因に応じて実装またはテストを修正し、CI で安定して通ることを確認する
<!-- AC:END -->
