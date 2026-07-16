---
id: TASK-1.4
title: ViewerStore を静的読込パイプラインと監視・永続化オーケストレーションに分離する
status: To Do
assignee: []
created_date: '2026-07-16 00:38'
updated_date: '2026-07-16 00:55'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/212
parent_task_id: TASK-1
ordinal: 17400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #212 から移行。ViewerStore（307行）の読込パイプライン（computeLoad 周辺）にアプリ専用の関心（ファイル監視・UserDefaults 永続化・ウィンドウクローズ連動）が同居しており、静的1回描画だけが欲しい QuickLook から再利用できない。二層化して静的読込モードを提供する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 読込パイプラインが watcher・UserDefaults・onFileGone から分離されている
- [ ] #2 QuickLook から静的読込のみのモードで使える
- [ ] #3 既存テスト（ViewerStoreTests 34件）が維持されている
<!-- AC:END -->
