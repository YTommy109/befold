---
id: TASK-149
title: viewer-main.js の解決マップ参照をプロトタイプ安全にし、リンク先をツールチップで可視化する
status: To Do
assignee: []
created_date: '2026-07-25 11:31'
labels:
  - path-reference
  - security
dependencies: []
priority: medium
type: task
ordinal: 225000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
セキュリティレビュー指摘（低 L-1 / L-2）。(1) `_mmdApplyResolvedReferences` の `map[t.raw]`（viewer-main.js L304-315）が Object.prototype 継承値を拾うため、`constructor` 等をパス参照として書いた Markdown で未解決パスが befold-link 化される（偽リンク表示）。`uniq` への `__proto__` 代入も参照が静かに dead 扱いになる。(2) DOMPurify は class / data-* を許可するため、生 HTML の span で表示文字列と無関係な実在パスへ誘導する「解決済み風リンク」を作れる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 解決マップの参照を Object.prototype.hasOwnProperty.call（または Map）で判定する
- [ ] #2 uniq を Object.create(null) か Set にする
- [ ] #3 dataset.resolved を title（ツールチップ）等で表示し、実際の遷移先を可視化する
- [ ] #4 `constructor` / `__proto__` をパス参照に含む文書の Jest 回帰テストを追加する
<!-- AC:END -->
