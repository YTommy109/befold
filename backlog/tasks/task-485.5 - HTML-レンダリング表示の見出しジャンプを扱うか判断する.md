---
id: TASK-485.5
title: HTML レンダリング表示の見出しジャンプを扱うか判断する
status: To Do
assignee: []
created_date: '2026-08-14 13:18'
labels: []
dependencies:
  - TASK-485.2
parent_task_id: TASK-485
priority: low
type: task
ordinal: 716000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

HTML の描画は `viewer-src/renderers.js:78 _renderHtml()` が
`&lt;iframe sandbox="allow-same-origin" srcdoc=…&gt;` へ流し込む形で、親文書からは
DOM が隔離されている。既存の検索窓も `#diagram-wrap` 配下しか走査しないため
（`find.js:101 collectScopes`）、**HTML では検索自体が効いていない**
（`ViewerCapabilities` の `canFind` が直接 HTML モードを除外している、
`befold/Viewer/ViewerCapabilities.swift:59`）。

同一オリジンなので `iframe.contentDocument` へは理屈上アクセスでき、
実際に `renderers.js:90` で触っている前例がある。

## このタスクで決めること

1. HTML レンダリングでも見出しジャンプを提供するか、ソース表示に限定するか
2. 提供するなら、iframe 越しに目印を列挙・ハイライト・スクロールする経路を
   新設することの妥当性（sandbox 属性・セキュリティ上の含意を含む）
3. ついでに検索窓も HTML で使えるようにするか（同じ経路を共有できる可能性がある）

判断だけを行うタスクで、実装する結論になった場合は別タスクを起票する。
見送る結論の場合も、理由を残して閉じる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 HTML レンダリングで見出しジャンプを提供するか否かの結論が理由付きで記録されている
- [ ] #2 提供する結論なら実装タスクが起票されている
- [ ] #3 iframe 越しにアクセスする場合のセキュリティ上の含意が検討されている
<!-- AC:END -->
