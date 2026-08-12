---
id: TASK-455
title: ソース表示でハイライトの span に割られたパス参照が注釈されない
status: Done
assignee: []
created_date: '2026-08-11 21:59'
updated_date: '2026-08-12 00:26'
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
- [x] #1 ソース表示で span に割られたパス参照（例: swift の `see ./notes.md for details`）が注釈され、クリックで開ける
- [x] #2 コメント行・非ハイライト表示など既存の注釈経路が退行していない
- [x] #3 span 分割ありのケースを固定するテストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
注釈をテキストノード単位から「最も内側の対象タグ（_PATH_ANNOTATE_TAGS）の要素」単位へ変更した。単位配下のテキストを連結して _PATH_RE を当て、一致範囲をノードごとの区間へ割り戻して span で包む。ノードをまたぐ一致は片ごとに span を作り、どの片も data-path はパス全体を指す（ハイライトの span 構造を壊さない）。

単位を最内側にしたのは、ソース表示が <pre><code><table><tr><td class=line-content> の形で、<code> 全体を 1 単位にすると行間に区切り文字が無く前行末と次行頭がつながって誤検出になるため。td を単位にすることで単位＝1 行になる。<pre> 直下のリセット・<a>/svg/.mermaid/.befold-path-ref のスキップは従来どおり。

検証: cd BefoldApp && npx jest → 6 suites / 417 tests 全通過（追加テスト 2 件: span 分割の注釈、分割された片からのクリック）。npm run lint:viewer / typecheck:viewer / check:viewer-cycles も通過。viewer-bundle.js は build:viewer で再生成済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ソース表示でハイライトの span に割られたパス参照が注釈されない問題を修正。path-refs.js の注釈単位をテキストノードから最内側の対象タグ要素へ変更し、単位テキスト全体で一致を取って span をまたぐパスも包むようにした。jest 417 件通過・lint/typecheck/循環チェック通過で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
