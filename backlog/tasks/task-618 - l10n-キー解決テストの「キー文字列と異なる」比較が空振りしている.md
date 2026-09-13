---
id: TASK-618
title: l10n キー解決テストの「キー文字列と異なる」比較が空振りしている
status: To Do
assignee: []
created_date: '2026-09-12 14:24'
labels:
  - test
dependencies: []
priority: low
type: bug
ordinal: 808000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SidebarEmptyStateTests（resolvesTitleForEveryReason / resolvesDescriptionForFilteredReasons）と BookmarkManagerPromptTests.resolvesEveryKey は、キーが Localizable.xcstrings に無いことを検知するつもりで `#expect(text != String(describing: key))` を置いている。しかし `String(describing:)` を `String.LocalizationValue` に掛けると `LocalizationValue(arguments: [], key: "...")` という説明文が返る（TASK-536.4 の責務レビューで scratchpad の swiftc 実行により実測）。`String(localized:)` が未解決時に返すのは素のキー文字列なので、この比較は常に真で、キーの足し忘れを検知しない。直前の `!text.isEmpty` だけが効いている。

3 箇所が同型なので一度に直す。候補: 未解決時の値そのものを比較相手にする（例: 存在しないテーブルを指定した `String(localized: key, table: "__missing__", bundle: .l10n)` はキー文字列を返すはず。未確認なので、まず 1 本を swift test で確かめてから 3 箇所へ展開する）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SidebarEmptyStateTests の 2 本と BookmarkManagerPromptTests の 1 本が、xcstrings に無いキーを渡すと落ちることを実測してから書き換える（一時的にキーを消して落ちることを確認）
- [ ] #2 3 箇所とも同じ比較の書き方に揃え、判定の根拠（未解決時に何が返るか）をテストの doc コメントに残す
<!-- AC:END -->
