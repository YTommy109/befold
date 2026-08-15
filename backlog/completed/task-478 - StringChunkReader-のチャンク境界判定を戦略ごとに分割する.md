---
id: TASK-478
title: StringChunkReader のチャンク境界判定を戦略ごとに分割する
status: Done
assignee: []
created_date: '2026-08-13 14:21'
updated_date: '2026-08-14 10:12'
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
- [x] #1 3 つの advance 戦略が戦略ごとの extension ファイルへ分かれ、各ファイルが file_length の警告閾値を下回る
- [x] #2 Markdown のフェンス状態が Markdown 戦略の側に閉じているか、閉じられない場合はその理由が doc コメントに記録されている
- [x] #3 public なアクセスレベルが下がっておらず、BefoldQuickLook のビルドが通る
- [x] #4 新規ファイル追加後に xcodegen generate を実行し、xcodebuild build -scheme befold が通る
- [x] #5 swiftlint のベースライン差分がゼロである（/swiftlint-baseline で main と比較）
- [x] #6 振る舞いの変更がなく、既存の StringChunkReader 系テストが無改修で通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
3 戦略を StringChunkReader+Lines / +Markdown / +Quotes へ分割した。共通の走査骨格（scanLines / LineOutcome）と readNextChunk は本体に残す。

- フェンス状態（AC #2）: stored property は extension に宣言できないため、状態そのものを +Markdown へ閉じることはできない。代わりに中身と遷移規則を MarkdownFenceState 構造体（+Markdown で宣言、isInside 以外は private・遷移は apply(marker:length:) のみ）へ寄せ、本体に残る面を markdownFence プロパティ 1 個へ縮小した。この理由は本体側の doc コメントに記録済み。
- maxQuotedFieldBytes は static のため +Quotes の extension へ移し、private のまま閉じた。
- internal へ引き上げたのは cache / currentLine / inQuotes / quotedRunLength / hasGivenUpQuoteTracking / markdownFence / advance / scanLines / LineOutcome。public は 1 つも下げていない。

実測:
- 行数: 本体 175 行、+Lines 20 / +Markdown 87 / +Quotes 63（分割前 309 行）。file_length 閾値を全ファイルで下回る。
- swift build 成功。xcodegen generate 後 xcodebuild build -scheme befold で BUILD SUCCEEDED（BefoldQuickLook ターゲット含む）。
- swift test --filter "StringChunkReader|NormalizedTextCache|ViewerRendererOneShot" で 55 テスト通過。テストは無改修。
- swiftlint: origin/main を git archive で展開して比較。件数 54 → 54、ルール別件数は完全一致。差分は large_tuple 3 件のファイル名が StringChunkReader.swift から分割先 3 ファイルへ移っただけで、既存の同じ違反（advance 系の 3 要素タプル戻り値）。新規違反ゼロ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
StringChunkReader の 3 つのチャンク境界戦略を +Lines / +Markdown / +Quotes の extension へ分割し、共通の走査骨格のみ本体に残した。フェンス状態は MarkdownFenceState へ寄せて本体の露出をプロパティ 1 個に縮小（extension に stored property を置けない制約は doc コメントに記録）。振る舞いは不変で、既存テスト 55 件が無改修で通過、xcodebuild BUILD SUCCEEDED、swiftlint はルール別件数が main と完全一致。
<!-- SECTION:FINAL_SUMMARY:END -->
