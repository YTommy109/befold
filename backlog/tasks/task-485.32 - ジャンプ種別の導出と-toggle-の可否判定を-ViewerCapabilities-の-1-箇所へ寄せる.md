---
id: TASK-485.32
title: ジャンプ種別の導出と toggle の可否判定を ViewerCapabilities の 1 箇所へ寄せる
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 09:12'
updated_date: '2026-09-25 12:40'
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
- [x] #1 cmd+shift+F の可否はメニュー検証と実行経路が同じ能力のプロパティを読み、ジャンプ可・検索不可の組み合わせをテストで確かめている
- [x] #2 使えるジャンプ種別の列挙が ViewerCapabilities の 1 箇所にあり、syncJumpAvailability と availableJumpKind がそれを使う
- [x] #3 ViewerCapabilitiesFactory の URL 由来 FileType は 1 回だけ作られ、コメントが行番号に依存しない
- [x] #4 ToggleBarCommandTests のヘルパーが showsDiff を明示の引数で受ける
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerCapabilities に availableJumpKinds（allCases を canJump(to:) で絞る唯一の列挙）と canToggleJump（availableJumpKind != nil || canFind）を computed で足す。availableJumpKind は availableJumpKinds.first
2. DocumentCommandController.toggleJump は canToggleJump で guard、kind があれば toggleJump(kind:)、無ければ renderer.toggleFind。syncJumpAvailability は Set(availableJumpKinds)。ViewerMenuValidator.validateDocumentJumpItem は canToggleJump
3. ViewerCapabilitiesFactory.make の FileType(url:) を 1 回にし、行番号参照コメントを直す
4. ToggleBarCommandTests.makeCapabilities に showsDiff を明示引数で渡す。ViewerCapabilitiesTests の手書き filter も availableJumpKinds へ
5. テスト: ジャンプ可・検索不可で項目有効かつ toggleJump が届く
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
/review-design: 真実の源は能力の事実（canJump/canFind）で中身判定なし。新 computed は既存フラグの合成で init の条件は増えない（ADR 0002 段 2）。消費経路は toggleJump / validateDocumentJumpItem / syncJumpAvailability の 3 つ（rg 実測）、JS のスイッチは sync の集合を読むので追随。validateMenuItem のコストは allCases 3 件で定数。ジャンプ可・検索不可は supportsFind:false の Markdown で作れる（canJump は supportsFind を読まない）。行数: ViewerCapabilities 185 / DocumentCommandController 210 / ViewerMenuValidator 193、増分 +10 行程度・stored property 増なし。

実装: ViewerCapabilities に availableJumpKinds / canToggleJump を computed で追加。toggleJump は canToggleJump で guard し、種類が無ければ renderer.toggleFind を直接呼ぶ（canToggleJump かつ種類無し ⇒ canFind なので DocumentCommandController.toggleFind の guard は不要）。validateDocumentJumpItem も canToggleJump。syncJumpAvailability は Set(availableJumpKinds)。ついでに syncJumpAvailability の doc の openJump 参照を直した（TASK-485.30 の列挙の 1 つ）。WebViewDocumentRenderer.applyJumpAvailability の allCases.filter は受け取った集合を送信用に並べるだけで可否判定ではないので残した。
検証: 修正を戻す（validateDocumentJumpItem を canFind に）と ViewerMenuValidatorTests「ジャンプはできるが検索はできない表示では…」が :149 の validate 期待で落ちることを実測。swift test --skip Integration --skip FileWatcherTests 1878+66 件合格。swiftlint は main 比で新規 0・解消 0。check-type-group-size --check 合格。型・stored property・プロトコル準拠は増えていないので responsibility-reviewer は不要。docs/dev/viewer-ui.md の ⇧⌘F の節に canToggleJump を 1 行追記。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
⇧⌘F の可否を ViewerCapabilities.canToggleJump 1 つにまとめ、メニュー検証と実行経路の両方がそれを読むようにした。使えるジャンプ種別の列挙は availableJumpKinds 1 箇所に寄せ、availableJumpKind と syncJumpAvailability がそれを使う。ViewerCapabilitiesFactory の FileType(url:) は 1 回だけ作り、コメントの行番号参照をなくした。ToggleBarCommandTests のヘルパーは showsDiff を引数で明示するようにした。ジャンプ可・検索不可のテストは修正を戻すと落ちることを確認済み。swift test 全件合格、swiftlint 新規 0。
<!-- SECTION:FINAL_SUMMARY:END -->
