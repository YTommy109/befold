---
id: TASK-485.32
title: ジャンプ種別の導出と toggle の可否判定を ViewerCapabilities の 1 箇所へ寄せる
status: To Do
assignee: []
created_date: '2026-09-25 09:12'
labels: []
dependencies: []
references:
  - BefoldApp/befold/Viewer/ViewerCapabilities.swift
  - BefoldApp/befold/App/ViewerMenuValidator.swift
  - BefoldApp/befold/App/DocumentCommandController.swift
  - BefoldApp/befold/App/ViewerCapabilitiesFactory.swift
  - BefoldApp/befoldTests/ToggleBarCommandTests.swift
parent_task_id: TASK-485
priority: low
type: chore
ordinal: 833000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-485.26 / 485.28 のコードレビュー(2026-09-25)で出た整理項目。どれも挙動は正しいが、同じ規則が 2 箇所にあり、片方だけ直すと食い違う。
- cmd+shift+F が何かをするかどうかの規則が 2 箇所にある。実行側は `DocumentCommandController.toggleJump()`(`availableJumpKind` が無ければ `toggleFind()`、そこで `canFind`)、メニュー検証側は `ViewerMenuValidator.validateDocumentJumpItem`(`canFind` だけ)。ジャンプはできるが検索はできない種別が将来できると、実行はできるのに項目がグレーになる。能力として 1 つ(例: `availableJumpKind != nil || canFind`)を持たせ、両方がそれを読む形にできる
- 「`DocumentJumpKind.allCases` を `canJump(to:)` で絞る」処理が `ViewerCapabilities.availableJumpKind` と `DocumentCommandController.syncJumpAvailability()` の 2 箇所にある。集合を返すプロパティを 1 つ持てば両方が使える
- `ViewerCapabilitiesFactory.make` が `FileType(url: fileURL)` を 3 回作っている(supportsDiffDisplay / supportsHeadingJump / codeLanguage)。1 回作って使い回せる。同じ箇所のコメントは「この型の :20-24 のコメント」と行番号で参照しており、行が増えるとずれる
- `ToggleBarCommandTests.makeCapabilities(supportsHeadingJump:isDocumentJumpEnabled:)` が `showsDiff: !isDocumentJumpEnabled` と差分表示の有無をゲートに連動させている。「差分表示中でもジャンプの能力が無ければ検索」というテストの前提が引数名から読めず、ヘルパーを直すと別のケースを黙って測る形になる
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 cmd+shift+F の可否はメニュー検証と実行経路が同じ能力のプロパティを読み、ジャンプ可・検索不可の組み合わせをテストで確かめている
- [ ] #2 使えるジャンプ種別の列挙が ViewerCapabilities の 1 箇所にあり、syncJumpAvailability と availableJumpKind がそれを使う
- [ ] #3 ViewerCapabilitiesFactory の URL 由来 FileType は 1 回だけ作られ、コメントが行番号に依存しない
- [ ] #4 ToggleBarCommandTests のヘルパーが showsDiff を明示の引数で受ける
<!-- AC:END -->
