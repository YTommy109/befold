---
id: TASK-447
title: フォルダ行の「開けるものがあるか」判定が列挙失敗を「無い」と同一視している
status: To Do
assignee: []
created_date: '2026-08-11 12:34'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 675000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`DirectoryLister.containsSupportedFile`(BefoldApp/befold/Viewer/DirectoryLister.swift:157-159)は `firstSupportedFile` 経由で列挙失敗を nil → false へ畳む。結果、**読めないフォルダ**がサイドバーの行で「開けるものが無いフォルダ」と同じ見た目になる。

TASK-410 で扱った 3 経路（ルート一覧・プレビュー・Quick Open）の外だったため、そちらでは触っていない。TASK-404 / TASK-410 で導入した「失敗と空を型で分ける」方針の残りの適用先。

判断が要る点: 行のバッジ（開けるものがあるか）に第 3 の状態を足すのか、ツリー展開の `.expandedFailed` と同じ見せ方へ寄せるのか。展開してみれば失敗は分かる（TASK-404）ので、行のバッジは変えないという結論もありうる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 読めないフォルダの行が、開けるファイルの無いフォルダと同じ見た目にならない（区別しないと決める場合は理由を Notes に残す）
- [ ] #2 決めた振る舞いをユニットテストで固定している
<!-- AC:END -->
