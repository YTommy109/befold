---
id: TASK-328
title: 左右分割の差分で末尾が空行のファイルが描画されない問題を修正する
status: Done
assignee: []
created_date: '2026-08-06 01:47'
updated_date: '2026-08-06 01:57'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 500000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
highlightedDiffLines は reflowSpanBalancedLines が末尾の空要素を落とすため hunk.lines より 1 件少ない配列を返す。インライン描画は undefined ガードを持つが、左右分割描画（viewer.js:548 / :529）はガードなしで lineHtmls[left] / lineHtmls[right] を参照するため TypeError で落ちる。例外は _renderDiffHtmlIfAvailable（viewer-main.js:1712）の catch に飲まれて空文字を返すので、ユーザーには「⇧⌘D だけ何も起きない」ように見える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 末尾が空行のファイル（例: alpha\nbeta\n\n）で ⇧⌘D の左右分割差分が描画される
- [x] #2 highlightedDiffLines の戻り値が常に hunk.lines と同数であること、または両描画経路が同じガードを持つことをテストで固定する
- [x] #3 修正を戻すと落ちることを確認したテストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
原因: reflowSpanBalancedLines は highlight.js が付ける末尾 \n を落とすため無条件に末尾の空要素を pop する。ハンクの最終行が空行（末尾が空行のファイル）だと本物の行まで落ち、highlightedDiffLines の戻り値が hunk.lines より 1 件短くなる。

単純化の検討: 両描画経路にガードを足す案と、絞り込み点で長さを保証する案を比べ、後者を採った。行 HTML を添字で引く前提は pairDiffLines（対を添字で返す）が持つ設計そのものなので、長さ一致を highlightedDiffLines の事後条件にすれば経路が増えても破れない。あわせて renderInlineDiffHtml 側の undefined ガードを削除し、不変条件を 1 箇所に寄せた。

実測: 修正前に viewer-diff.test.js の新規 2 件が TypeError で失敗（leadingIndentInfo → lineContentCell → diffSideCells → renderSideBySideDiffHtml, viewer.js:280）。修正後 npx jest で 4 suites / 377 tests すべて成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
highlightedDiffLines の戻り値を必ず hunk.lines と同数へ正規化し、末尾が空行のファイルで左右分割差分が TypeError で落ちる問題を修正した。インライン側の重複ガードは削除して不変条件を 1 箇所に集約。viewer-diff.test.js に長さ一致テストと左右分割の描画テストを追加し、修正前は 2 件失敗・修正後は npx jest で 377 件全成功を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
