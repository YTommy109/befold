---
id: TASK-316
title: 差分パーサが hunk 内の '--- ' / '+++ ' 行をファイルヘッダと誤認し行を欠落させる問題を修正する
status: Done
assignee: []
created_date: '2026-08-05 16:06'
updated_date: '2026-08-05 16:31'
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
- [x] #1 削除行が '-- ' で始まる unified diff をインライン・左右分割の両レイアウトで正しく描画できる
- [x] #2 追加行が '++ ' で始まるケースも同様に正しく描画できる
- [x] #3 hunk 内ヘッダ誤認の回帰テストを __tests__/viewer-diff.test.js に追加し、修正を戻すと失敗することを確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 原因

viewer.js の parseUnifiedDiff は、ハイフン 3 個 + 空白 / プラス 3 個 + 空白 の接頭辞を `file !== null` だけを条件に消費しており、ハンクの内か外かを見ていなかった。ヘッダ類（旧側パス・新側パス・バイナリ印）はハンクが始まる前にしか現れないため、判定を `hunk === null` の内側へ移した。Binary files / GIT binary patch の判定も同じ位置にあるため一緒に移している。

## 単純化の検討

新しい状態やフラグは足していない。既に持っている `hunk` 変数（ハンク内かどうかを表す唯一の値）をそのまま条件に使えるため、パーサの状態は増えていない。

## 検証

- jest 371 green（新規 3 件: パーサ 1 + 両レイアウトの描画 2）
- **テストが空振りしていないことを確認**: 条件を `if (true)` へ戻すと新規 3 件だけが落ちる（`Expected: "q.sql" / Received: "old comment"` ほか）。戻して再度 371 green
- markdownlint-cli2: 0 件（本タスクでは md を変更していないが規約どおり実行）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
parseUnifiedDiff がハンク内でもファイルヘッダの接頭辞を消費していたため、ハイフン 2 個で始まる削除行（SQL/Lua のコメント等）が描画から消え、以降の旧側行番号が 1 つずれ、oldPath も本文で上書きされていた。ヘッダ判定をハンク開始前（hunk === null）に限定して修正。状態は増やさず既存の hunk 変数をそのまま条件に使った。検証は jest 371 green（新規 3 件）と、条件を元に戻すと新規 3 件だけが落ちることの実測。
<!-- SECTION:FINAL_SUMMARY:END -->
