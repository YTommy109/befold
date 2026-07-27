---
id: TASK-173
title: コードブロック表示にインデントガイド(縦線)を追加する
status: To Do
assignee: []
created_date: '2026-07-27 11:55'
labels: []
dependencies: []
ordinal: 248000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Zed や VS Code のように、ソースコード表示でインデントの深さを示す縦のガイド線を表示したい。

事前調査の結果:
- vendored の highlight.js (BefoldApp/BefoldKit/Resources/highlight.min.js, v11.11.1) 自体にはインデントガイド機能はなく、純粋なCSSだけで確実に実現するのは難しい。
- 行番号なし表示のパスでは viewer.js の highlightCode()/renderCodeHtml() (viewer.js:144, 267-281) が <pre><code> 単一ブロックとして出力しており、white-space: pre-wrap で折り返すため、CSSのrepeating-linear-gradient背景だけでは長い行の折り返しでガイド位置がズレる。
- style.css に tab-size 指定が一切ない(grep で0件)ため、タブ/スペース混在時にガイド間隔が崩れる。
- 一方、行番号表示を有効にしたパス(buildLineNumberRows(), viewer.js:248-256)は既に1行ずつ <tr><td class="line-content"> にDOM分割されており、こちらをベースにする方が確実。

実現方針の見立て(実装時に再検討):
1. style.css に tab-size を明示的に固定する
2. 行番号の有無に関わらず、コード表示は常に行単位のDOM構造(buildLineNumberRows 相当)を使うようにまとめる(新しい描画パスを追加するのではなく、既存の line-numbers 用パスに統合する方向で単純化を優先検討する)
3. 各行の先頭空白からインデント深さをJSで計算し、data-indent 属性や階層的なspanなどでCSSがガイド線を描画できる情報を付与する
4. CSS側でその情報を元に縦のガイド線を描画する

純粋CSSでは信頼性のある実現が困難なため、viewer.js に軽微な変更を加える前提で設計する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 コードブロック表示(行番号あり/なし双方)でインデントの深さに応じた縦のガイド線が表示される
- [ ] #2 タブとスペースが混在するソースファイルでもガイド線の位置がずれない
- [ ] #3 長い行が折り返し表示される場合でもガイド線が崩れない、または折り返し時の扱いが明文化されている
- [ ] #4 ライト/ダークいずれのテーマでもガイド線が視認でき、既存のシンタックスハイライト色と衝突しない
<!-- AC:END -->
