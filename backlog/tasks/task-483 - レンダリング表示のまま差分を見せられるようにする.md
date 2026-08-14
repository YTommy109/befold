---
id: TASK-483
title: レンダリング表示のまま差分を見せられるようにする
status: To Do
assignee: []
created_date: '2026-08-14 12:45'
labels: []
dependencies: []
documentation:
  - docs/dev/native-app-design.md
priority: medium
type: feature
ordinal: 700000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
いま差分表示は「ソース相当の表示にだけ重なる」構造になっている。差分が描かれるのは `viewer-src/render.js` の `renderShape` のうち shape が `code` / `csv-source` の分岐だけで、`markdown` / `csv-table` の分岐には差分の入る余地がない。`renderers.js` の `_renderDiffHtmlIfAvailable` は `type === "csv"` を明示的に弾いており、`BefoldKit/FileType.swift` の `supportsDiffDisplay` がその JS の挙動に合わせて `.csv` を false にしている。

つまり現状の制約は技術的な不可能性ではなく、差分を描く経路が 1 本しか通っていないことによる。CSV/TSV のテーブル表示と Markdown のレンダリング表示については、ソース行とレンダリング後の要素の対応付けが取れるため、レンダリングされた見た目のまま差分を重ねられる。

HTML / SVG は対象外とする。ソース行とレンダリング結果を対応付ける手段（markdown-it の token.map に相当するもの）が無いため。

サブタスクは CSV/TSV → Markdown の順に進める。CSV/TSV は表という表現がもともと行単位で差分の概念と噛み合い、削除行を赤い行として自然に挿入できるため設計判断が少ない。Markdown は「レンダリング結果に存在しない削除ブロックをどう見せるか」の設計が先に要る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CSV/TSV をテーブル表示したまま、追加・削除されたレコードが色分けして表示される
- [ ] #2 Markdown をレンダリング表示したまま、変更のあったブロックが色分けして表示される
- [ ] #3 HTML / SVG の差分表示はソース表示のままで、挙動が変わらない
- [ ] #4 既存のソース表示での差分（inline / side-by-side）の見た目と操作が退行していない
<!-- AC:END -->
