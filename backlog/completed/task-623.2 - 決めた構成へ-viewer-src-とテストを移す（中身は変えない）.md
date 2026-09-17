---
id: TASK-623.2
title: 決めた構成へ viewer-src とテストを移す（中身は変えない）
status: Done
assignee:
  - '@claude'
created_date: '2026-09-14 11:57'
updated_date: '2026-09-15 01:56'
labels: []
dependencies:
  - TASK-623.1
parent_task_id: TASK-623
priority: medium
type: chore
ordinal: 819000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-623.1 で決めた構成へ、ファイルの移動だけを行う。テストは `.js` のまま動かす。移動と中身の変更を同じコミットに混ぜると、類似度が落ちて `git log --follow` の追跡が切れやすくなるため、TypeScript 化（TASK-623.3 / 623.4）とは分ける。

移動で追随が要る箇所（2026-09-14 時点の実測。着手時に取り直すこと）:

- テストの `__dirname` 基準の相対パス（`support/viewerMainHarness.js` の `RESOURCES_DIR`、`style.css` の読み込み 3 箇所、`viewerShortcutCatalog.test.js` の参照）
- `BefoldApp/package.json` の jest 設定（`testMatch` / `setupFiles`）
- `BefoldApp/Package.swift` の `exclude: ["Resources/__tests__"]` と `BefoldApp/project.yml` の `excludes: "__tests__/**"`
- `.oxlintrc.json` の files パターン
- `docs/dev/rules/testing.md`、`viewer-src/README.md`、Swift の doc コメント（`ViewerShortcutCatalog.swift`、`ViewerShortcutCatalogTests.swift`、`FileType.swift`）が引用するパス
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ファイル移動のコミットに、パス追随以外の内容変更が含まれていない
- [x] #2 Jest のテスト件数が移動前と一致する
- [x] #3 `npm run check:viewer-bundle` が差分なしで通る（移動でバンドル出力の実質が変わっていない）
- [x] #4 `swift build` と、`xcodegen generate` 後の `xcodebuild build -scheme befold` の両方が通る
- [x] #5 移動前のパスを引用する文書・コメントが残っていない（`rg` で旧パスの出現が 0 件）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. git mv BefoldKit/Resources/__tests__ → BefoldApp/viewer-test（ファイル名・support/ はそのまま）
2. パス追随のみ: テストの require / __dirname 相対、package.json の jest、.oxlintrc.json の files、Package.swift / project.yml の除外削除
3. 文書・コメントの旧パス引用を追随（スナップショット層と ADR 0005 Context は除く）。README へ置き場所の理由を追記するのは別コミット
4. 検証: jest 件数 645、check:viewer-bundle、swift build、xcodegen + xcodebuild、rg で旧パス 0 件
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
移動の実測（2026-09-15）:
- `git diff --cached -M --stat` で 18 本すべてが rename として検出され、内容差分は require / __dirname の相対パス、package.json の jest（testMatch / setupFiles）、.oxlintrc.json の files、Package.swift / project.yml の除外削除、文書・コメントのパス引用だけ。style.css を読む 3 行はパスが長くなり oxfmt が折り返した（`npm run format:check` を通すため）
- Jest: 移動前 16 suites / 645 tests → 移動後 16 / 645
- `npm run check:viewer-bundle` exit 0（差分なし）、`npm run lint` exit 0、`npm run format:check` exit 0、`scripts/check-doc-citations.sh` exit 0
- `swift build` exit 0、`xcodegen generate` 後の `xcodebuild build -scheme befold -derivedDataPath .build/xcode` BUILD SUCCEEDED。成果物の BefoldKit.framework に *.test.js は含まれない
- `rg __tests__`（backlog/・docs/superpowers/ のスナップショット層を除く）の残りは ADR 0005 の Context 1 件のみ。これは決定当時の実測（6 ファイル 3,716 行）を述べる記述で、現在のパスを指す引用ではないため残した（623.1 の決定どおり）
- 置き場所の理由は viewer-src/README.md「なぜここに置くか」へ別コミットで追記
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BefoldKit/Resources/__tests__ を BefoldApp/viewer-test/ へ git mv し、パス追随だけを行った。Package.swift / project.yml のテスト除外を削除。Jest 645 件（移動前と同数）、check:viewer-bundle 差分なし、swift build・xcodegen + xcodebuild 成功、旧パスの引用はスナップショット層と ADR 0005 Context を除き 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
