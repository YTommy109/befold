---
id: TASK-666
title: CSV/TSV の列幅をファイル保存で失わない方針を決める
status: Done
assignee:
  - '@claude'
created_date: '2026-10-05 22:50'
updated_date: '2026-10-05 23:13'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/pull/708'
documentation:
  - docs/dev/file-type-display.md
priority: medium
ordinal: 851000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #708（rianjs、CSV/TSV の列幅ドラッグ・自動フィット）では、同じパスでも内容が変わると列幅を捨てる（`viewer-src/render.ts` の `prepareCsvResize` 呼び出し）。befold は FileWatcher で自動更新するため、手で調整した幅がエディタでの保存のたびに消える。仕様書 `docs/dev/file-type-display.md` には「内容の変更ではリセット」と明記されており意図した挙動ではあるが、利用者体験として妥当かは未判断。未確認: 判定時点で `_mmdDocument.content()` が前回の記録のままであること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 パス同一での内容変更時に列幅を保持するか捨てるかの方針が決まり、Notes に理由が残っている
- [x] #2 保持に決めた場合、列数が変わったときの扱い（捨てる / 末尾列のみ初期幅）がテストで固定されている
- [x] #3 方針に合わせて docs/dev/file-type-display.md の「寿命」の記述が更新されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. prepareCsvResize を「パスだけ」で判定する形へ単純化する（sameContent 引数と render.ts の判定式を撤去）。パスが null（文書の同一性が不明）のときは常に捨てる
2. 列数が減った再描画では applyWidths が超過分の幅を切り詰める（table.style.width の合計に消えた列を残さない）。増えた列は自然幅（既存の applyWidths の挙動）
3. テスト: 内容変更でも同一パスなら保持、列数減で切り詰め・列数増で末尾のみ自然幅、パス変更と null パスでリセット
4. docs/dev/file-type-display.md の「寿命」を更新。局所修正（csv-resize.ts / render.ts の 1 箇所）で状態も経路も増えないため /review-design は省略
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: 同じパスなら内容変更でも列幅を保持する（パス不明 null は別文書扱いで常に捨てる）。理由: FileWatcher の自動更新で、保存のたびに手で調整した幅が消えるのを避ける。内容の同一性を見る sameContent 引数と render.ts の判定式を撤去し、判定は「パスだけ」に単純化した。
列数: 減った分は applyWidths で切り詰め（消えた列の幅を合計に残さず、戻っても復活させない）、増えた列は自然幅。位置対応なので途中挿入では幅が 1 つずれる（仕様書に明記）。
前提の確認: render() 内で prepareCsvResize が呼ばれる時点では _mmdDocument は前回の記録のまま（document-state.ts の record は後段、append が追記を足す）。
実測: viewer-csv-resize 9/9、新規 2 件は修正を戻すと落ちる（HEAD の実装で 2 failed）。Jest 全体 18 suites / 685 tests 通過、tsc・oxfmt 通過。/review-design は局所修正のため省略。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
prepareCsvResize を「パスだけ」の判定に単純化し、同じパスの内容変更（ファイル保存）では列幅を保持するようにした。列数が減った分は切り詰め、増えた列は自然幅。仕様書の「寿命」を更新。viewer-csv-resize のテストを新方針へ更新し 2 件を追加（修正を戻すと落ちることを確認）。Jest 685 tests 通過。
<!-- SECTION:FINAL_SUMMARY:END -->
