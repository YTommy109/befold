---
id: TASK-623.2
title: 決めた構成へ viewer-src とテストを移す（中身は変えない）
status: To Do
assignee: []
created_date: '2026-09-14 11:57'
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
- [ ] #1 ファイル移動のコミットに、パス追随以外の内容変更が含まれていない
- [ ] #2 Jest のテスト件数が移動前と一致する
- [ ] #3 `npm run check:viewer-bundle` が差分なしで通る（移動でバンドル出力の実質が変わっていない）
- [ ] #4 `swift build` と、`xcodegen generate` 後の `xcodebuild build -scheme befold` の両方が通る
- [ ] #5 移動前のパスを引用する文書・コメントが残っていない（`rg` で旧パスの出現が 0 件）
<!-- AC:END -->
