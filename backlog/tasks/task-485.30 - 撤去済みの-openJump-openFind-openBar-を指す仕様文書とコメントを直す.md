---
id: TASK-485.30
title: 撤去済みの openJump / openFind / openBar を指す仕様文書とコメントを直す
status: To Do
assignee: []
created_date: '2026-09-25 09:11'
updated_date: '2026-09-25 09:11'
labels: []
dependencies: []
documentation:
  - docs/dev/viewer-ui.md
  - docs/dev/text-loading-dataflow.md
parent_task_id: TASK-485
priority: low
type: docs
ordinal: 831000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-485.28 で `openBar(kind:)`・`openJump(kind:)`・`openFind()`・`ViewerFindBridge.openFindScript` を toggle 系へ置き換えたが、それらを指す記述が残っている(2026-09-25 のコードレビューで検出)。
docs/dev は「現在の仕様」の層で、実装完了時に追随させる約束になっている(.claude/CLAUDE.md「設計文書の三層構造」)。残っているのは次の箇所。
- docs/dev/viewer-ui.md の「使える条件と自動クローズ」節末尾: `DocumentRendering.openJump(kind:)` / `DocumentCommandController.openJump(kind:)`
- docs/dev/text-loading-dataflow.md: 「Cmd+F → _mmdOpenFind()」が 2 箇所。今は `_mmdToggleBarMode("search")` を経由する
- BefoldKit/ViewerJumpBridge.swift `jumpAvailabilityScript` の doc: `DocumentCommandController.openJump`
- befold/App/DocumentCommandController.swift `syncJumpAvailability` の doc: 「openJump の guard と同じ述語」
- befold/App/WebViewDocumentRenderer.swift `applyJumpAvailability` 付近の doc: 「openJump と同じく」
- viewer-src/jump.ts: `_mmdOpenJump` を「Swift から名前で呼ばれる入口」としている。今の Swift の入口は `_mmdToggleBarMode`。`closeUnlessAvailable` のコメントの `WebViewCommandController.openJump` も同様
- viewer-src/find.ts: `_mmdOpenFind` を「ViewerBridge の各 script 定数と一対一」の入口としているが、対応する定数は撤去済み
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 列挙した文書・コメントが現在のシンボル(toggleFind / toggleJump / _mmdToggleBarMode)を指している
- [ ] #2 `rg "openJump|openBar|openFindScript|defaultBarKind"` の結果が docs/dev・BefoldApp のソースで 0 件、または意図して残した理由が書かれている
<!-- AC:END -->
