---
id: TASK-928
title: チャンク追記で data-processed 付きの生 HTML の Mermaid 要素が包まれなくなった
status: To Do
assignee: []
created_date: '2026-11-09T11:24:00Z'
labels:
  - bug
  - viewer
dependencies:
  - TASK-925
references:
  - BefoldApp/viewer-src/zoom.ts
  - BefoldApp/viewer-src/mermaid.ts
priority: low
type: bug
ordinal: 893000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`/code-review high` の指摘で、コードを読んだだけの未検証の主張。TASK-925 で `_mmdWrapDiagrams` の対象を渡された図に限定した。後続チャンクの生 HTML に `<div class="mermaid" data-processed="true">` があると、`.mermaid:not([data-processed])` に選ばれないので包まれない。修正前は別の図の実行が容器全体を走査するので、ズーム操作が付いていた。同じ記述が、最初の render では描画され、追記では描画されない。

実用上の文書にこの記述が現れるかは未確認で、現れないなら対応は不要の可能性がある。テストのフィクスチャはこの要素を含むが、包まれるかどうかを検証していない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 最初の render と追記で data-processed 付き要素の表示がどう違うかの実測が Notes に記録されている
- [ ] #2 直す場合はチャンクによらず同じ扱いになり、修正を戻すと落ちる回帰テストがある。直さない場合はその根拠が Notes に記録されている
<!-- AC:END -->
