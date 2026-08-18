---
id: TASK-485.17
title: Markdown ソース表示でも見出し行へジャンプできるようにする
status: To Do
assignee: []
created_date: '2026-08-18 15:14'
updated_date: '2026-08-18 15:15'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
priority: medium
type: feature
ordinal: 764000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

見出しジャンプは現在 Markdown レンダリング表示でしか使えない。列挙が
`viewer-src/jump-providers.ts:42 collectHeadings` で `h1, h2, h3` の DOM 要素を
`querySelectorAll` する形になっているため（`headingSelector` :31）、ソース表示の
DOM（`table.code-table` の行、`viewer-src/code-html.ts buildLineNumberRows`）には
目印が 1 つも無く、バーを開いても 0 件になる。

ユーザー要望: 同じ .md をソース表示で読んでいるときにも `#` / `##` / `###` の
行へ前後移動したい。

## TASK-485.4 との関係

TASK-485.4 は「ソースコード表示で**関数定義**へジャンプする」で、hljs トークンか
言語別正規表現かという不確実性の高い検出方式の選定を含む。本タスクは対象が
Markdown の ATX 見出し行に限られ、検出規則が 1 つ（行頭 `#{1,3}` + 空白）で
確定しているため別タスクとして切る。ただし **「ソース表示の行を目印にする」
という機構は共通**なので、先に本タスクを実装して行ベース JumpTarget の形を
確定させ、485.4 はそれに乗る形にするのが望ましい。

## 論点

- レベル選択 UI（h1/h2/h3 トグル）をソース表示でも同じものとして共有するか。
  共有するなら `selectedLevels` は表示モードをまたいで 1 つでよいか
- 段階読み込み（`StringChunkReader`、1000 行 / 1MB 単位）で未読み込み範囲の
  見出しは DOM に無い。既存の検索と同じ「表示範囲内」の見せ方に揃える
- フェンス（``` 内）やコメント内の `#` を見出しと誤検出しない
  （setext 見出し `===` / `---` を対象にするかも決める）
- `ViewerCapabilities.canJump` の条件をソース表示でも真にする必要があるが、
  Markdown 以外のソース表示では偽のままにする（種別の見分けが要る）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Markdown をソース表示にした状態で見出しジャンプを開くと、`#` / `##` / `###` の行が目印として数えられ前後移動できる
- [ ] #2 レベル選択トグルがソース表示でも効き、レンダリング表示との状態の持ち方が Implementation Notes に明記されている
- [ ] #3 フェンスドコードブロック内の `#` 行を見出しと誤検出しないことをテストで示している
- [ ] #4 Markdown 以外のソース表示では見出しジャンプが無効であることが操作前に分かる
- [ ] #5 読み込み済み範囲だけを数えていることがユーザーに伝わる
<!-- AC:END -->
