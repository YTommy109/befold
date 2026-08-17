---
id: TASK-485.14
title: ViewerWindowSessionSync 抽出を native-app-design.md とモジュールマップコメントに反映する
status: To Do
assignee: []
created_date: '2026-08-17 14:05'
labels: []
dependencies: []
parent_task_id: TASK-485
priority: medium
type: docs
ordinal: 748000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘、verdict: CONFIRMED）

TASK-485.2 で行った ViewerWindowSessionSync の抽出が、現在仕様の単一情報源に反映されていない。CLAUDE.md の規定「現在の仕様は docs/dev/native-app-design.md、実装完了時に必ず追随させる。更新不要と判断したならその理由を Notes に 1 行残す」に反する（TASK-485.2 の Notes は抽出を記録しているが skip 理由は無い）。

- `docs/dev/native-app-design.md:120` と行 27 のモジュールツリーは、close / rename / key のセッション更新をいまだ ViewerWindowManager の責務として記述し、ViewerWindowSessionSync に言及しない
- `BefoldApp/befold/App/ViewerWindowManager.swift:14` の自ファイルのモジュールマップコメントは「+SessionSync extension が re-keying / recording / delegate 準拠を持つ」と述べるが、実際にはもう `window(forPath:)` しか無い

このままだと次の読者が delegate ロジックを誤ったファイルに探しに行く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 native-app-design.md（モジュールツリー・該当節）が ViewerWindowSessionSync の現在の配置と責務を記述している
- [ ] #2 ViewerWindowManager.swift のモジュールマップコメントが実装と一致している
<!-- AC:END -->
