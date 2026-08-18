---
id: TASK-485.17
title: Markdown ソース表示でも見出し行へジャンプできるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-18 15:14'
updated_date: '2026-08-18 15:43'
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
- [x] #1 Markdown をソース表示にした状態で見出しジャンプを開くと、行頭の # / ## / ### が目印として数えられ前後移動できる
- [x] #2 同じ文書のレンダリング表示とソース表示で、見出しの件数と順序が一致することをテストが固定している（フェンス内の # を拾わないこと、レベルトグルが両モードで共有されることを含む）
- [x] #3 レベル選択トグルがソース表示でも効く
- [x] #4 読み込み済み範囲だけを数えていることが「表示範囲内」ラベルでユーザーに伝わる
- [x] #5 Markdown 以外のソース表示および差分表示では見出しの列挙へ入らず 0 件になる（capability では閉じない。その判断理由を Implementation Notes に残す）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. viewer-src/document-state.ts へ「直近の描画で実際に描いた形」を移す。render.ts:74 の _mmdRenderedAs を _mmdDocument が持ち、書き手は render() の 2 箇所（分岐前の仮置きと _renderSource の戻り値による上書き）だけに限定する。appendChunk はこれまでどおり同じ記録を読む。読み取り用アクセサを export し、jump-providers.ts は document-state.ts だけを import する（render.ts へは依存させない）。npm run check:viewer-cycles で循環が無いことを確認する。
2. jump-providers.ts の collectHeadings を分岐させる。描画形が "code" かつ _mmdDocument.type() === "md" のときだけソース行走査へ入り、それ以外は従来どおり h1/h2/h3 の要素セレクタを使う。**DOM セレクタで種別を判定しない**（table.code-table は差分テーブルも名乗る = diff-html.ts:353/491。TASK-318 と同型）。
3. ソース行走査の規則: table 内の行を上から順に見て、フェンス（``` / ~~~）の内外を状態として持つ。フェンス外の行だけを ATX 見出し（行頭の空白 3 つまで + #{1,3} + 空白）として判定し、selectedLevels でフィルタする。行テキストは td.line-content の textContent から取る（tr.textContent だと行番号セルが混ざる）。
4. anchor / highlight は td.line-content にする。tr にしない理由は jump-providers.ts:78-88 の実測（border-collapse の表では tr への outline が上下辺しか描かれない）。
5. ignoresTruncation は付けない。ソース表示は段階読み込みの実対象で、差分と違い appendChunk が実際に追記するため「表示範囲内」ラベルは正しい。追記後の _mmdJump.refresh() は無条件で走るので追加配線は不要。
6. Swift 側の capability は変更しない（AC #4 を書き換え済み）。canJump に fileType を持ち込むと TASK-485.4（ソースの関数定義ジャンプ）が来た時点で条件が反転する。「目印 0 個は 0/0 表示が伝える」は ViewerCapabilities.swift:22-24 で既に採用済みの立場。
7. テスト（BefoldKit/Resources/__tests__/viewer-main-jump.test.js）。**中心は不変条件 1 本**: 同じ Markdown をレンダリング表示とソース表示で描いたとき、見出しの件数と順序が一致する。これが破れるとフェンス内 # の誤検出もレベルトグルの共有漏れも同時に落ちる。加えて (a) フェンス内の # を拾わない、(b) レベルトグルがソース表示でも効く、(c) 段階読み込みで「表示範囲内」ラベルが出る、(d) Markdown 以外のソース表示（.swift 等）では 0 件、(e) 差分表示では見出し列挙へ入らない。修正を戻して落ちることを各テストで確認する。
8. npm test / npm run typecheck:viewer / npm run lint / npm run check:viewer-bundle（viewer-bundle.js の再生成コミットが必須）。
9. docs/dev/native-app-design.md の文書内ジャンプ節を更新する（見出しは「Markdown レンダリング表示が対象」と書いてあるため）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 見出しの列挙を 2 経路に分けた（collectRenderedHeadings / collectSourceHeadings）。どちらを使うかは _mmdDocument.shape() === "code" かつ type() === "md" だけで決める。

単純化の検討: 新しい状態・述語は増やしていない。既に render() が 1 箇所で確定させていた「実際に描いた形」(_mmdRenderedAs) を読むだけで判定できる形だったため、これを render.ts のモジュール変数から document-state.ts の owner へ移し、appendChunk と見出し列挙が同じ 1 つの記録を読む構造にした。Swift 側の変更はゼロ。

判定方式の理由: _mmdViewOptions.mode() と type から renderShape() を再計算する案と、#diagram-wrap のクラス／table.code-table を見る案は採らなかった。render.ts に「表示モードや type から推し直すな (TASK-414) / DOM の形で判定するな (TASK-339)」という既存方針が明記されており、さらに差分テーブルも table.code-table を名乗る (diff-html.ts:353/491) ため、セレクタ判定は TASK-318 と同型の穴になる。

capability を種別で閉じなかった理由 (AC #5): canJump に fileType を持ち込むと、TASK-485.4 (ソースの関数定義ジャンプ) が来た時点で「Markdown だけ true」を剥がすことになり、条件が 1 タスクで反転する。また「目印 0 個であることは 0/0 表示が伝える」は canJumpToChangeBlock の doc コメント (ViewerCapabilities.swift:22-24) で既に採用済みの立場で、heading にも同じ立場を適用するほうが一貫する。起票時の AC #4 は capability で閉じる前提だったため書き換えた。

既知の制限: setext 見出し (=== / --- の下線) はソース側で拾わない。ATX 見出しだけを対象にしており、両モード一致の不変条件も ATX で書かれた文書について成り立つ。行単位の走査で setext を正しく扱うにはパラグラフ境界の判定が要り、行スキャナが実パーサへ近づいていくため、いまは対象外とした（native-app-design.md にも明記）。

検証（実測）:
- npm test: 10 スイート / 532 件すべて成功（実装前ベースライン 525 件 + 新規 7 件）
- 修正を戻して確認: collectHeadings のソース分岐を無効化すると新規 7 件のうち 5 件が落ち、shape ゲートに依存しない 2 件（Markdown 以外のソース / 差分表示で 0 件）だけが通る。テストが空振りしていないことを確認済み
- npm run typecheck:viewer: エラーなし
- npm run lint (--type-aware): エラーなし
- node scripts/check-viewer-cycles.mjs: 循環 import なし（31 モジュール）
- npm run build:viewer: viewer-bundle.js 再生成済み（コミットに含む）
- markdownlint-cli2: 0 issues

docs/dev/native-app-design.md の文書内ジャンプ節を更新し、両モードの対象・判定の単一情報源・setext の制限・capability を種別で閉じない理由を記載した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Markdown をソース表示している間も、行頭の # / ## / ### へジャンプできるようにした。列挙は _mmdDocument.shape()（render が実際に描いた形）だけを見て分岐し、差分表示・CSV ソース・Markdown 以外のソースには入らない。レベルトグルは両表示で同じ状態を共有する。中心となるテストは「同じ文書のレンダリング表示とソース表示で見出しの件数と順序が一致する」という不変条件で、フェンス内の # を拾わないこととトグルの共有がこの 1 本で同時に落ちる。npm test 532 件成功、修正を戻すと該当 5 件が落ちることを確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
