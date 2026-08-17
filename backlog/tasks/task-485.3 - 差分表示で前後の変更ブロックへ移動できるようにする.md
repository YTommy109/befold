---
id: TASK-485.3
title: 差分表示で前後の変更ブロックへ移動できるようにする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-14 13:18'
updated_date: '2026-08-17 13:11'
labels: []
milestone: m-6
dependencies:
  - TASK-485.1
parent_task_id: TASK-485
priority: medium
type: feature
ordinal: 714000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

差分表示は行ごとに `tr.diff-line.diff-add / .diff-del / .diff-context` を持つ
（`viewer-src/diff-html.js:132 diffRow`）。連続する add/del をひとまとまりの
「変更ブロック」として畳めば、前後移動の対象列が作れる。

## 実装上の落とし穴（調査済み）

- **ハンク単位では使えない。** `tr.diff-hunk` の区切り行（:147）は存在するが、
  `GitDiffReader` が `-U1000000` を使うためファイル全体が 1 ハンクになりうる
  （`BefoldKit/GitDiffReader.swift:101` のコメント）。さらに先頭ハンクには
  区切り行を置かない（:162-163）。**連続する変更行のグルーピングで数えること。**
- **左右分割（`renderSideBySideDiffHtml` :221）では `tr` に diff-add/diff-del が付かない。**
  クラスは側セル `td.diff-side.diff-add/.diff-del` に付く。インラインと分割で
  列挙のセレクタが変わるため、レイアウト切り替え（`ViewerDiffBridge.setDiffLayout` :27）
  のたびに列を作り直す必要がある。
- 差分表示中は `appendChunk` が DOM 追記をスキップする（`render.js:176`）ため、
  ソース表示と違って部分読み込みの考慮は不要（要確認）。

## 論点

- 分割表示で左右どちらを基準に数えるか（両側で対応する行を 1 ブロックとみなす）
- 変更ブロックのハイライト表現。行単位のハイライト CSS は現状無い
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 インライン差分で、前後の変更ブロックへ移動できる
- [x] #2 左右分割差分でも同じ数・同じ順序で移動できる
- [x] #3 レイアウトを切り替えても現在位置が保たれる、または明示的に先頭へ戻る（どちらかを決めて実装する）
- [x] #4 ファイル全体が 1 ハンクになる差分でも、変更ブロック数が正しく数えられる
- [x] #5 連続変更行のグルーピングに JS のユニットテストがある
- [x] #6 行（tr）のハイライトが border-collapse 下でも四辺とも描かれることを、スナップショットで確認している（TASK-485.1 の実測では tr への outline は上下辺しか出なかった。JumpTarget.highlight は複数要素を取れるので、行ではなく各セルへ当てる等の対処を選ぶこと）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 【単純化】DOM のクラス走査で連続変更行をグルーピングするのではなく、生成時に番号を振る。diff-html.ts の純関数 assignChangeBlockIndexes(lines, startIndex) が、連続する del 群 + 直後の add 群を 1 ブロックとして hunk.lines へ通し番号を割り当てる。インライン／左右分割のどちらの描画も同じ hunk.lines を入力にするため、両レイアウトの数と順序が構造的に一致する（AC#2/#4 を実装ではなく構造で担保）。
2. 変更行の tr に data-diff-block="N" を出す（インラインは diffRow、左右分割は pair 行）。
3. jump-providers.ts の changeBlockJumpProvider（id: 'changeBlock'）が [data-diff-block] を文書順に拾い、属性値でまとめる。anchor はブロック先頭の tr、highlight は各 tr 直下の td 群（tr への outline は border-collapse 下で上下辺しか出ないため。AC#6）。
4. バー内オプションは JumpProvider.optionsElementId で宣言し、jump.ts が active な種類のものだけ表示する（見出しレベルのトグルは見出しのときだけ出す）。
5. Swift: DocumentJumpKind に changeBlock（tag 2 / menu.edit.jumpToChangeBlock）、Localizable.xcstrings に文言。
6. ViewerCapabilities に canJumpToChangeBlock（= canJump && showsDiff）と canJump(to:) を足し、ViewerMenuValidator を種類ごとに分岐（複雑度の上限を超えるため validateDocumentJumpItem へ抽出）。
7. テスト: assignChangeBlockIndexes の純関数テスト（AC#5）、両レイアウトで data-diff-block が同数・同順であること（AC#2）、ファイル全体 1 ハンクでも個別に数えること（AC#4）、DOM 側の列挙・セルへのハイライト・truncated ラベル抑止・オプション表示。
8. viewer-src を変更したら npm run build:viewer でバンドルを再生成してコミットする。

--- /review-design の結果（実装前レビュー・4 件を設計へ反映）---
【項目1】メニューの活性は「変更ブロックが 0 件か」ではなく事実（showsDiff）で決める。
【項目3】ViewerMenuValidator は documentJump アクション 1 本で canJump を返しており種類別の活性を持たない → タグから復元して分岐。
【項目4/7】差分表示中でも truncated は立つ（truncation.ts）が、差分の表は setDiff の全文から組まれ appendChunk はスキップされる（render.ts）ため「表示範囲内」ラベルは事実と食い違う → JumpProvider.ignoresTruncation を足す。
【項目9】「両レイアウトでブロック番号が一致」は純関数テストでは守れない → 同じ diff を両レイアウトで描画して data-diff-block の個数・並びを比較するテストで担保。
【項目5】レイアウト切替は Swift が setDiffLayout の直後に render を送るため refresh 経路に乗り、modeJustSwitched は rendered/source 切替でしか立たないので位置が維持される。AC#3 は「保たれる」を選ぶ。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

変更ブロックの列は **DOM のクラス走査ではなく描画時の番号付け**で作った。インライン表示は
tr に diff-add/diff-del が付き、左右分割では側セル(td.diff-side)に付くため、クラスで数えると
レイアウトごとに列挙が変わる。代わりに diff-html.ts の純関数 assignChangeBlockIndexes が
hunk.lines へ通し番号を振り、両レイアウトの描画が同じ番号を data-diff-block として出す。
列挙側(collectChangeBlocks)はこの属性だけを見るので、件数・順序の一致は構造で保証される。

ハイライトは行ではなくセルへ当てた(JumpTarget.highlight が配列であることを使う)。
border-collapse の表では tr への outline が上下辺しか描かれない(TASK-485.1 の実測)。

## 検証（実測）

- JS: npm test で 506 件通過。左右分割の data-diff-block 出力を一時的に外すと 3 件失敗する
  ことを確認済み(テストが空振りしていないことの確認)
- Swift: swift test で 1625 件通過
- lint: oxlint(--type-aware) / tsc --noEmit / oxfmt すべてゼロ件。swiftlint は main との
  ベースライン差分ゼロ(cyclomatic_complexity が 1 件新規に出たため validateDocumentJumpItem
  へ抽出して解消)
- ハイライトの四辺: 実 style.css を link した WKWebView ハーネスで takeSnapshot し、
  セルへ当てた outline が四辺とも描かれ .diff-add/.diff-del の地色も残ることを画像で確認
- 実機: 2 箇所を別々に変更した .md を差分表示で開き「変更箇所へジャンプ…」で 1/2 と表示、
  先頭ブロックだけが枠付きになることを確認。差分表示でないときはメニュー項目が無効、
  見出しジャンプのときだけ H1/H2/H3 トグルが出ることも確認

## 注意（このセッションでの事故）

実機確認の後始末で git reset --hard を打ち、未コミットの実装を一度全消しした。
scratchpad の diff-html.ts のバックアップとビルド済み .app 内の style.css から 2 ファイルを
復元し、残りは再適用してテストで同一性を確認した。実機確認用の一時ファイルは
git add/commit せず、変更したファイルは git checkout -- <path> で個別に戻すこと。

## 追記: 目印の当て方を絞った（レビュー指摘）

当初は変更ブロックの全行・全セルへ枠を出していたが、行数の多いブロックで画面が
枠だらけになるという指摘を受け、**ブロック先頭行のガター（行番号セル）だけ**に絞った。
行番号を出していない表にはガターが記号セル（+/-）しか無いので、そちらへ落とす。
分割表示では左右それぞれのガターが対象（対で 1 つの目印であることが両側に出る）。
実測: 独立ハーネスのスナップショットと実機（左右分割）で、先頭行のガター 2 セルだけが
枠付きになることを確認。JS テスト 509 件通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
差分表示の変更ブロック（連続する削除行 + 直後の追加行）を文書内ジャンプの目印にした。列挙は DOM のクラス走査ではなく、描画時に hunk.lines へ振った通し番号（data-diff-block）を読む形にし、インライン／左右分割で件数・順序が一致することを構造で保証した。現在位置のハイライトは border-collapse 対策で行ではなくセルへ当てる。メニューの活性は ViewerCapabilities.canJump(to:) で種類ごとに分け、変更ブロックは差分表示中だけ有効。検証は JS 507 件 / Swift 1625 件のテスト通過、swiftlint はベースライン差分ゼロ、四辺のハイライトは WKWebView スナップショット、前後移動とメニュー活性は実機（2 箇所変更した .md で 1/2 表示）で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
