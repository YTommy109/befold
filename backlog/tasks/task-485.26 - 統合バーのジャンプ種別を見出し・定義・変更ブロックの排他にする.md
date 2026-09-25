---
id: TASK-485.26
title: 統合バーのジャンプ種別を見出し・定義・変更ブロックの排他にする
status: Done
assignee: []
created_date: '2026-09-25 07:44'
updated_date: '2026-09-25 08:01'
labels: []
dependencies: []
parent_task_id: TASK-485
type: bug
ordinal: 827000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
統合バーの右上の選択肢は常に「検索」と「ジャンプ 3 種のどれか 1 つ」の 2 つにする。見出しは Markdown（レンダリング・ソース）、定義は対応言語のソース表示、変更ブロックは差分表示の担当。現状は ViewerCapabilities.canJump(to: .heading) が表示モードに依らず true で、差分表示中は見出し+変更ブロック、Swift 等のソース表示中は見出し+定義が同時に出る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 差分表示中は変更ブロックだけが選べ、見出し・定義は選べない
- [x] #2 定義ジャンプ対応言語のソース表示中は定義だけが選べ、見出しは選べない
- [x] #3 それ以外の表示では見出しだけが選べる
- [x] #4 どの表示でもジャンプ種別がちょうど 1 つになることをユニットテストで担保する
- [x] #5 CSV/TSV の差分表示でないときはジャンプ種別を持たず、統合バーは検索だけになる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
ViewerCapabilities に canJumpToHeading を足し、見出しを変更ブロック・定義の裏返しとして導く（状態は増やさない）。CSV/TSV を見分けるため FileType.supportsHeadingJump を足し、既定値なしの引数で渡す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化の検討: 見出しは差分・定義の否定で決まるので新しい状態は持たない。CSV 判定は supportsDiffDisplay（CSV/TSV で false）に相乗りできるが、将来 CSV 差分に対応したとき見出しが黙って出るので別の述語にした。
旧仕様を固定していたテストを書き換えた: OpenBarCommandTests（差分表示中でも見出しを明示すれば開く→開かない）、DocumentJumpCommandTests（同期集合が 2 種→1 種、全種類の網羅は 3 状態の和で見る）。
ruby 等の非対応言語のソース表示では見出しが出る（目印 0 件）。対応言語は順次広げる方針なのでそのまま（ユーザー確認済み）。
検証: swift test 全 1995 件合格、/swiftlint-baseline 新規 0・解消 0、markdownlint 0 件。アプリでの目視確認は未実施。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
統合バーのジャンプ 3 種（見出し・定義・変更ブロック）を排他にし、選択肢を常に「検索 + 1 つ」にした。CSV/TSV の非差分表示は検索だけ。ViewerCapabilities.canJumpToHeading と FileType.supportsHeadingJump を追加し、viewer-ui.md を更新。swift test 全件合格・swiftlint 差分 0 で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
