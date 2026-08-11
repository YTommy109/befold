---
id: TASK-455
title: ソース表示でハイライトの span に割られたパス参照が注釈されない
status: To Do
assignee: []
created_date: '2026-08-11 21:59'
labels:
  - bug
dependencies: []
priority: medium
type: bug
ordinal: 679000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 事象

ソース表示（`.swift` 等のコード種別・`source` モード）で、行の中のパス文字列が highlight.js の span で分割されると `.befold-path-ref` の注釈が付かず、クリックで開けない。

## 実測

`highlight.js@11.11.1` の common ビルドで `see ./notes.md for details` を swift としてハイライトすると

```
see <span class="hljs-operator">./</span>notes.md <span class="hljs-keyword">for</span> details
```

となり `./notes.md` が 2 つのテキストノードに割れる。`viewer-src/path-refs.js` の注釈はテキストノード単位で正規表現を当てるため、割れた側は一致しない。コメント行（`// see ./notes.md for details`）は 1 つの `hljs-comment` span に収まるため注釈される。

## いつ分かったか

TASK-432.5 でベンダーを npm 依存へ移し、jest ハーネスが本番と同じく hljs 付きでソース表示を描くようになって表面化した。それまでハーネスは `window.hljs` を注入しておらず、ソース表示が常に非ハイライトだったため、この差はテストから見えていなかった（`viewer-main-source-append.test.js` の「.md のソース表示と .swift で挙動が一致する」はコメント行を使う形へ書き換えて通している）。

## 方針の候補

- 注釈をテキストノード単位ではなく行単位のテキストで行い、一致範囲を span をまたいで DOM へ写す
- ハイライト前のテキストで一致位置を求め、位置ベースで注釈する
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ソース表示で span に割られたパス参照（例: swift の `see ./notes.md for details`）が注釈され、クリックで開ける
- [ ] #2 コメント行・非ハイライト表示など既存の注釈経路が退行していない
- [ ] #3 span 分割ありのケースを固定するテストがある
<!-- AC:END -->
