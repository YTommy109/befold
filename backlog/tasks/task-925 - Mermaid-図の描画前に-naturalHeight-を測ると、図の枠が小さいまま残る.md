---
id: TASK-925
title: Mermaid 図の描画前に naturalHeight を測ると、図の枠が小さいまま残る
status: To Do
assignee:
  - '@claude'
created_date: '2026-11-09T04:58:00Z'
labels:
  - bug
  - viewer
dependencies:
  - TASK-924
references:
  - https://github.com/YTommy109/befold/pull/771
priority: low
type: bug
ordinal: 890000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #771 のレビュー中の実測で見つけた既存の不具合で、PR が持ち込んだものではない。_mmdWrapDiagrams は naturalHeight をラップ時に 1 回だけ測るので、SVG の描画前に包まれた図は枠の高さが古いまま残り、図の大部分が枠内スクロールの向こうに隠れる。

実測（WKWebView、1200x800、図は 8 エッジの graph TD、2 回とも同じ結果）: 図 1 個の描画後に appendChunk を同じ tick で 2 回呼ぶと、3 個目の図が natural 154 / 枠 116px / 中身 639px になる。PR 適用前の main（4771f4d0 以降）でも、入れ子の内側のラッパーが natural 154 / 枠 116px になる。appendChunk の間隔が 0ms / 30ms、または描画完了を待つ場合は再現しなかった。

未確認: 実際のアプリでこの状況が起きるか。Swift 側は isLoadingMoreLines で追記の交錯を防いでおり（ViewerRenderer+RenderHelpers.swift の handleLoadMoreLines）、同じ tick の 2 回呼び出しは通常の経路では起きない可能性がある。描画に時間がかかる図で間隔を空けた場合、再現しなかった理由、mermaid.run の並行実行が原因かどうかも未確認。原因の説明はこの実測からの推定で、確定ではない。PR #771 のガードが無い状態を前提に直すと二度手間になるので、取り込み後に着手する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 実際のアプリの追記経路で再現するかどうかが、測定条件（図の重さ・追記の間隔）とともに Notes に記録されている
- [ ] #2 再現条件を満たす追記の後でも、すべての図の枠の高さが描画後の図の高さに追従している。アプリの経路で起きないと判断して直さない場合は、その根拠が Notes に記録されている
- [ ] #3 直す場合は、修正を戻すと落ちる回帰テストがある
<!-- AC:END -->
