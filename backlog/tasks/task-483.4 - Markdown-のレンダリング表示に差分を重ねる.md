---
id: TASK-483.4
title: Markdown のレンダリング表示に差分を重ねる
status: To Do
assignee: []
created_date: 2026-08-14 12:47
updated_date: '2026-11-20T14:33:00Z'
labels:
  - diff
  - markdown
milestone: m-4
dependencies:
  - TASK-483.3
parent_task_id: TASK-483
priority: medium
type: feature
ordinal: 704000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-483.3 で決めた方式に沿って、Markdown をレンダリング表示したまま差分を表示できるようにする。

`viewer-src/markdown.ts` の `buildMarkdownRenderer` / `markdownRenderer` を通る描画経路に、ソース行とブロック要素の対応付けを組み込む。`viewer-src/render.ts` の `renderShape` で `markdown` の分岐が差分を通るようにし、`viewer-src/renderers.ts` の `_renderMarkdown` を差分対応にする。

`render.ts` の `appendChunk` には差分表示中はチャンク追記を DOM に反映しない扱い（`_mmdDocument.shape() === 'diff'` での早期 return）があるため、レンダリング差分でこれがどう働くべきかを確認する。

着手前に TASK-483.3 の結論を読むこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Markdown でレンダリング表示のまま差分表示モードを選べる
- [ ] #2 変更のあったブロックが TASK-483.3 で決めた表現で表示される
- [ ] #3 削除されたブロックが TASK-483.3 で決めた表現で扱われる
- [ ] #4 mermaid ブロック・コードブロック・表を含む Markdown でも表示が壊れない
- [ ] #5 差分が取得できない場合は通常のレンダリング表示に落ちる
- [ ] #6 既存のソース表示での差分表示が退行していない
- [ ] #7 差分ジャンプ（次の変更へ）がレンダリング差分でも効く
<!-- AC:END -->
