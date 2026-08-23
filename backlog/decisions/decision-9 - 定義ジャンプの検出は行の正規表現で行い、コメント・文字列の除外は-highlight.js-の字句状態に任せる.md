---
id: decision-9
title: 定義ジャンプの検出は行の正規表現で行い、コメント・文字列の除外は highlight.js の字句状態に任せる
date: '2026-08-23 16:28'
status: accepted
---
## Context

文書内ジャンプ（TASK-485）の 3 つ目の対象として、ソースコード表示で関数・型の定義へ
前後移動する機能を入れる（TASK-485.4）。ソース表示の DOM は `table.code-table` の
`tr` で行という単位を持つが、「この行は定義である」という意味情報は持っていない。

取りうる方式は 2 つあった。

1. **hljs トークン方式** — `span.hljs-title.function_` / `.class_` を拾う
2. **行テキストの正規表現方式** — 言語ごとの規則を書く

いずれの方式でも、コメント・文字列の中にある紛らわしい行（`// func foo() {}`、
複数行文字列の中の `def x():`）を定義と誤検出しないことが要る。

## Decision

**「この行は定義か」は言語別の行テキスト正規表現で決め、「その行は本当にコードか」は
highlight.js の字句状態（`.hljs-comment` / `.hljs-string` のスパン）で決める。**
判定を 2 つの役に分け、それぞれ得意な側に任せる。

対応言語は swift / python / javascript / typescript の 4 つから始める。集合は
JS 側 `FUNCTION_JUMP_LANGUAGES` と Swift 側 `FunctionJumpLanguages.supported` の
2 箇所に存在するため、`ViewerFunctionJumpLanguageContractTests` がバンドルを読んで
ずれを落とす。

### hljs トークンを「定義である」ことの判定に使わない理由

実測（highlight.js 11.11.1、common ビルド）で、**JS/TS は呼び出し側にも
`span.hljs-title.function_` が付く**。`foo(1)` / `obj.method(2)` / `compute()` が
定義と同じクラスを名乗るため、トークンだけでは区別できない。Swift / Python では
定義にしか付かないので、言語によって意味の変わる判定を共通経路に置くことになる。

### コメント・文字列の除外を自前で持ち回らない理由

先行する Markdown ソース見出しの検出（TASK-485.17）は、`CODE_FENCE` の開閉状態を
上から順に持ち回ってコードブロック内の `#` を除外している。これを 4 言語へ広げると、
ブロックコメント・行コメント・生文字列・ヒアドキュメント・テンプレートリテラルの
規則を言語ぶん抱えることになり、「文脈が要る判定を行単位のパターン一致だけで決める」
形（TASK-316 と同型）へ戻る。

highlight.js は既にその字句解析をしている。`reflowSpanBalancedLines`
（`viewer-src/code-html.ts`）が行末で開いたままの `<span>` を閉じて次行の先頭で
開き直すため、**複数行コメント・複数行文字列の途中の行も、自分の
`td.line-content` の中に `hljs-comment` / `hljs-string` を持つ**。行の td だけを
見れば「コメントの中か」が分かるので、状態を持ち回る必要が無い。

## Consequences

- **今後の言語追加は「正規表現を 1 本足す」で済む。** コメント・文字列の規則は
  highlight.js 側が既に持っているため、言語ごとに除外規則を書かない
- **highlight.js の出力形式に依存する。** `reflowSpanBalancedLines` が行ごとに
  span を開き直すことと、コメント・文字列に `hljs-comment` / `hljs-string` が
  付くことが前提になる。この前提はテストで縛る必要があり、
  `viewer-main-jump-function.test.js` は手書きのダミー HTML ではなく
  `main.render()` を通した**実 highlight.js の出力**に対して検証している
- **highlight.js が言語を解釈できない場合は誤検出しうる。** 素のテキストで足切りし、
  コメント・文字列のスパンがある行だけ再判定するため、ハイライトが崩れている
  ファイルでは除外が効かない。ただし崩れた表示そのものが利用者に見えている状態なので、
  ジャンプだけが静かに間違う形にはならない
- **行あたりの正規表現は言語ごとに 1 本へ結合する。** `collect` は
  `_mmdJump.rebuild()` のたびに全行を走査し、段階読み込み中は appendChunk ごとに
  呼ばれるため
- **JS/TS のメソッド短縮記法（`foo() {`）は対象外にした。** `if (x) {` /
  `while (x) {` / `} catch (e) {` と行の形が同じで、除外語彙を抱えないと
  誤検出する。クラスメソッドを拾うのは別タスクとする

