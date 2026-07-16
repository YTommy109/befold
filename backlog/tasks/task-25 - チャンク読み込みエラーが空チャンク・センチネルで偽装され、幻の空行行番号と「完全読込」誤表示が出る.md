---
id: TASK-25
title: チャンク読み込みエラーが空チャンク・センチネルで偽装され、幻の空行行番号と「完全読込」誤表示が出る
status: To Do
assignee: []
created_date: '2026-07-16 10:55'
updated_date: '2026-07-16 12:11'
labels: []
dependencies:
  - TASK-29
references:
  - BefoldApp/befold/Viewer/ViewerStore.swift
  - BefoldApp/befold/Viewer/ViewerWebView.swift
  - BefoldApp/BefoldKit/Resources/viewer.html
priority: medium
type: bug
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerStore.loadMoreLines のエラーパス（ViewerStore.swift:161-169）が ("", isTruncated:false) のセンチネルを返す設計のため 2 つの実害がある。(a) Coordinator が appendChunk("") を送り、行番号 ON のコード表示では buildLineNumberRows("") が空内容の行番号付き <tr> を 1 行追加する（reflowSpanBalancedLines("") は [""] を返し pop 条件 length>1 を満たさない）— 幻の空行が末尾に残る。(b) isTruncated=false でバナーが消えるため、部分読込のファイルが完全表示として提示される。検索全量読込パスでも _mmdOnAllLinesLoaded が発火し、欠落コンテンツに対する検索が「完了」として実行される。エラーは UI にいっさい表出しない。テスト loadMoreLinesErrorKeepsContentAndStops はこの契約を意図として固定している。単純化検討: エラーをタプルのセンチネル値でなく明示的な結果（chunk / completed / failed(reason) の enum）として Store→Coordinator→JS に流し、バナーで「残りを読み込めませんでした」を表示する設計が本筋。最低限の修正は result.chunk.isEmpty のとき appendChunk をスキップし、エラー表示を追加する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 チャンク読込エラー時に幻の空行（空内容の行番号行）が追加されない
- [ ] #2 エラーで部分表示になったことがユーザーに視認できる（完全読込と区別される）
- [ ] #3 検索全量読込がエラーで途切れた場合、検索結果が部分的である旨が示される
<!-- AC:END -->
