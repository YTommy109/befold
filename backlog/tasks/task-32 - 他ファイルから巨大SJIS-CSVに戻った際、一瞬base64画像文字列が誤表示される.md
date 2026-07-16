---
id: TASK-32
title: 他ファイルから巨大SJIS CSVに戻った際、一瞬base64画像文字列が誤表示される
status: To Do
assignee: []
created_date: '2026-07-16 13:44'
labels: []
dependencies: []
type: bug
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーで別ファイルを表示した後、巨大SJIS CSVタブ(またはファイル)に戻ると、一瞬 'iVBORw0KGgo...' のようなbase64エンコード画像(PNG)らしき文字列がそのままテキストとして表示され、その後しばらくして正しいCSV内容に置き換わる現象が観測された。CSVファイルにこの内容が含まれるはずはなく、直前に見ていた別ファイル(画像)のレンダリング結果、またはキャッシュされたコンテンツが誤って一瞬適用されている可能性がある。ViewerStore の loadGeneration による世代管理、ViewerWebView.Coordinator の lastRenderedContentRevision 判定、NormalizedTextCache/textCache の再利用ロジックに、ファイル切替時の競合や取り違えがないか調査する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 base64文字列が一瞬表示される再現条件が特定されている(どのファイル間の切替で発生するか、タイミング条件を含む)
- [ ] #2 誤表示の原因(世代管理・レンダリングキャッシュ・コンテンツ取り違えのいずれか)が特定されている
- [ ] #3 原因箇所に対する修正方針、または追加調査が必要な場合はその範囲が明確になっている
<!-- AC:END -->
