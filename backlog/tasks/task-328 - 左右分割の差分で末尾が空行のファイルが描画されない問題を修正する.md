---
id: TASK-328
title: 左右分割の差分で末尾が空行のファイルが描画されない問題を修正する
status: To Do
assignee: []
created_date: '2026-08-06 01:47'
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
- [ ] #1 末尾が空行のファイル（例: alpha\nbeta\n\n）で ⇧⌘D の左右分割差分が描画される
- [ ] #2 highlightedDiffLines の戻り値が常に hunk.lines と同数であること、または両描画経路が同じガードを持つことをテストで固定する
- [ ] #3 修正を戻すと落ちることを確認したテストがある
<!-- AC:END -->
