---
id: TASK-232
title: viewer.js の showLineNumbers 既定解釈の不一致と body クラスリスト重複を是正する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:15'
updated_date: '2026-07-31 15:41'
labels:
  - refactor
dependencies: []
priority: medium
type: task
ordinal: 390000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldKit/Resources/viewer.js で showLineNumbers 省略時の解釈が反転している: buildLineNumberRows (:311) は !== false で既定 true、renderCodeHtml (:335) は === true で既定 false。renderCsvSourceHtml (:508) は引数 1 個で wrapWithLineNumbers を呼び緩い判定に依存して行番号ありになっている。既定を === true 側（明示）に統一し、:508 は true を明示する。挙動が変わりうるため CSV ソース表示の行番号テストで固定してから触る。併せて viewer-main.js:1583/:1618 の body クラス一覧 2 箇所の手写しを定数 + ヘルパー化する（新 type 追加時の更新漏れで前の型のスタイルが残るバグを防ぐ）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 showLineNumbers 省略時の解釈が 1 つの規則に統一され、既存の各表示（コード/CSV ソース）の行番号有無が変わらないことがテストで固定されている
- [x] #2 body クラスの付け替えが単一の定数リストとヘルパー経由になっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. buildLineNumberRows の既定を !== false から === true へ揃え、行番号系の省略時解釈を一本化
2. renderCsvSourceHtml の緩い判定を === true にし、wrapWithLineNumbers へ true を明示
3. 既定変更で壊れる既存テストは明示引数へ更新し、統一後の規則を固定するテストを追加
4. viewer-main.js の body クラス一覧 2 箇所を BODY_CLASSES + _mmdSetBodyClasses に集約
5. ソース表示への切替でクラスが残らないことをテストで固定
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
行番号系の省略時解釈を『=== true のときだけ付ける』へ統一（buildLineNumberRows が !== false、renderCodeHtml が === true と反転していた）。renderCsvSourceHtml は wrapWithLineNumbers へ true を明示し、緩い判定への依存を解消。実表示は全呼び出し元が明示引数を渡しているため変化なし（コード/CSV ソースの行番号有無は既存テストで固定済み、renderCsvSourceHtml の true/false/省略の 3 ケースも既存）。既定変更で行番号を期待していた buildLineNumberRows のテスト 2 件は明示 true へ更新し、統一後の規則を固定するテストを 1 件追加。body クラスは BODY_CLASSES 定数 + _mmdSetBodyClasses ヘルパーへ集約し、render() の remove(6件) と _renderSource の remove(5件)+add の手写しを撤去。検証: npx jest → 336 passed / swift test → 937 passed。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
showLineNumbers 省略時の解釈を『明示 true のときだけ行番号』へ統一し、renderCsvSourceHtml の緩い判定依存を解消。body クラスの付け替えを BODY_CLASSES + _mmdSetBodyClasses の単一経路に集約した。jest 336 件 / swift test 937 件パスで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
