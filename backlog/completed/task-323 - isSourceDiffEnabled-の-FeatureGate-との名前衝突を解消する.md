---
id: TASK-323
title: isSourceDiffEnabled の FeatureGate との名前衝突を解消する
status: Done
assignee: []
created_date: '2026-08-05 16:08'
updated_date: '2026-08-06 04:15'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: low
type: chore
ordinal: 510000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

FeatureGate.swift:55 の static var isSourceDiffEnabled（ビルドゲート: dev ビルドでのみ true）と、ViewerWindowController+Diff.swift:58 のインスタンスプロパティ isSourceDiffEnabled（ユーザー設定の表示 ON/OFF）が完全に同名で、1 つの識別子が 2 つの異なる意味を持っている。

リスク: ViewerWindowController 内の将来の編集で、ビルドゲートを見るつもりが無修飾の参照でインスタンス側に解決される（逆も同様）。また (gate) スコープ判定のための grep ベースのゲート監査（CLAUDE.md のコミット規約）でも呼び出し箇所の分類を誤る。

修正: ユーザー設定側を isDiffDisplayOn / showsDiff 等、意味が区別できる名前へリネームする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ビルドゲートとユーザー設定のプロパティ名が区別できる名前になっている
- [x] #2 rg で isSourceDiffEnabled を検索したとき、FeatureGate 側の参照だけがヒットする
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化検討: isDiffShown は diffDisplayPreference.isEnabled への転送のみでプロパティ削除も可能だが、隣接する isDiffLayoutSideBySide も同型の転送であり片方だけ消すと対称性が崩れるためリネームを選択。

変更: ViewerWindowController+Diff.swift のユーザー設定側 isSourceDiffEnabled → isDiffShown。呼び出し元 ViewerWindowController.swift:811,816 と ViewerWindowControllerDiffTests.swift:308 を追随。doc コメントに FeatureGate 側との区別を明記。

検証: swift build / swift test（PostToolUse フックで実行、通過）。rg で isSourceDiffEnabled を検索し、残存 21 件がすべて FeatureGate.isSourceDiffEnabled への参照・BookmarkShortcut のゲート値受け引数・doc コメントであることを確認。swiftformat --lint 0 件、swiftlint は変更 3 ファイルで既存 4 件のみ（変更行と無関係）で新規増加なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ユーザー設定側のプロパティを isDiffShown へリネームし、ビルドゲート FeatureGate.isSourceDiffEnabled との同名衝突を解消。swift build/test 通過、rg で残存参照がゲート側のみであることを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
