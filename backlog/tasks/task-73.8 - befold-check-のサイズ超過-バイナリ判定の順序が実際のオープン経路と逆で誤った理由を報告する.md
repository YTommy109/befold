---
id: TASK-73.8
title: befold check のサイズ超過/バイナリ判定の順序が実際のオープン経路と逆で誤った理由を報告する
status: To Do
assignee: []
created_date: '2026-07-20 13:30'
labels: []
dependencies: []
references:
  - 'code review finding: BefoldApp/befold/App/CLISubcommandCommand.swift:76-89'
  - 'BefoldApp/BefoldKit/ViewerLoadPipeline.swift:44-65'
parent_task_id: TASK-73
priority: high
type: bug
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLICheckCommand.rejectReason はサイズ上限チェックを isBinary 判定より先に行うが、実際のファイルオープン経路 ViewerLoadPipeline.load は isBinary を先にチェックする。10MB超かつ内容がバイナリ判定されるテキスト系ファイル(例: .md)で、befold check は「fileTooLarge」と報告するが、実際に GUI で開くと「unsupportedFormat」として拒否される、という不一致が発生する。check サブコマンドの目的(実際に開けるかどうかの事前確認)が損なわれる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLICheckCommand.rejectReason の判定順序を ViewerLoadPipeline.load と一致させる(isBinary を先に判定する)
- [ ] #2 サイズ超過かつバイナリ判定されるファイルで、check の結果と実際のオープン結果が一致することを検証するテストを追加する
<!-- AC:END -->
