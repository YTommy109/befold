---
id: TASK-316
title: 差分パーサが hunk 内の '--- ' / '+++ ' 行をファイルヘッダと誤認し行を欠落させる問題を修正する
status: To Do
assignee: []
created_date: '2026-08-05 16:06'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: medium
type: bug
ordinal: 500000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・実測付き CONFIRMED）で検出。

viewer.js の parseUnifiedDiff は viewer.js:373 付近で '--- ' / '+++ ' プレフィックスを hunk 内かどうかを見ずにファイルヘッダとして解釈する。このため SQL / Lua / Haskell などで削除行の内容が '-- ' で始まる場合（raw diff 行は '--- old comment'）、その削除行がヘッダとして消費され描画から欠落する。

実測（node で関数を直接実行して再現済み）:
- 削除行 '-- old comment' が描画されない
- 以降の旧側行番号が 1 ずれる（context 行 'SELECT 2;' が oldNumber 2 と表示される）
- file.oldPath が 'old comment' に化ける

ファイルヘッダの判定を hunk 外（hunk 未開始 or 直前が別ファイルの終端）に限定する必要がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 削除行が '-- ' で始まる unified diff をインライン・左右分割の両レイアウトで正しく描画できる
- [ ] #2 追加行が '++ ' で始まるケースも同様に正しく描画できる
- [ ] #3 hunk 内ヘッダ誤認の回帰テストを __tests__/viewer-diff.test.js に追加し、修正を戻すと失敗することを確認する
<!-- AC:END -->
