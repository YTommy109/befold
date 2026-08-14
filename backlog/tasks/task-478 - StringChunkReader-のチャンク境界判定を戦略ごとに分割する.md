---
id: TASK-478
title: StringChunkReader のチャンク境界判定を戦略ごとに分割する
status: To Do
assignee: []
created_date: '2026-08-13 14:21'
labels:
  - refactor
dependencies: []
priority: low
type: chore
ordinal: 123000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/BefoldKit/StringChunkReader.swift` は 309 行あり、dagayn の `refactor_tool(mode="suggest")` で Swift 側の split 候補 2 件のうちの 1 件として挙がっている（型 272 行 / split_pressure 4.87。2026-08-13 実測）。

`readNextChunk()` の下に、チャンクの終端をどこに置くかを決める 3 つの戦略が同居している。

- `advanceByLines(from:)` — 行単位で `maxChunkBytes` まで詰める
- `advanceByMarkdownBlocks(from:)` — Markdown のブロック境界（フェンス）を跨がないようにする。補助として `classifyMarkdownLine(from:to:)` と `applyFenceTransition(_:)` を持つ
- `advanceRespectingQuotes(from:)` — CSV/TSV の引用フィールドの途中で切らない

`advance(from:)` がこの 3 つを振り分けており、各戦略は互いを参照していない。戦略ごとに `StringChunkReader+Lines` / `+Markdown` / `+Quotes` へ分けると、共有されるのは `cache`（正規化バイト列へのアクセス）と `maxChunkBytes` だけになる。振る舞いは変えない純粋な整理。

注意点: Swift の `private` はファイルスコープのため、分割先から触る `cache` / `currentLine` / `maxChunkBytes` および `MarkdownLineKind` まわりの状態を internal へ引き上げる必要がある。特に `applyFenceTransition` はフェンス状態という可変状態を跨いで持つため、Markdown 戦略側へ状態ごと寄せられるか（他戦略から見えなくできるか）を分割時に確認する。

CLAUDE.md の分割前例は `FileListModel+TreeRows` / `+Lookup` / `+Snapshot`。BefoldKit 側なので QuickLook 拡張からも使われる点に注意（アクセスレベルを public から下げない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 3 つの advance 戦略が戦略ごとの extension ファイルへ分かれ、各ファイルが file_length の警告閾値を下回る
- [ ] #2 Markdown のフェンス状態が Markdown 戦略の側に閉じているか、閉じられない場合はその理由が doc コメントに記録されている
- [ ] #3 public なアクセスレベルが下がっておらず、BefoldQuickLook のビルドが通る
- [ ] #4 新規ファイル追加後に xcodegen generate を実行し、xcodebuild build -scheme befold が通る
- [ ] #5 swiftlint のベースライン差分がゼロである（/swiftlint-baseline で main と比較）
- [ ] #6 振る舞いの変更がなく、既存の StringChunkReader 系テストが無改修で通る
<!-- AC:END -->
