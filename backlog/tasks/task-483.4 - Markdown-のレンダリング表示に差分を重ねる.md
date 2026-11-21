---
id: TASK-483.4
title: Markdown のレンダリング表示に差分を重ねる
status: Done
assignee:
  - '@claude'
created_date: 2026-08-14 12:47
updated_date: '2026-11-21T00:36:00Z'
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
- [x] #1 Markdown でレンダリング表示のまま差分表示モードを選べる
- [x] #2 変更のあったブロックが TASK-483.3 で決めた表現で表示される
- [x] #3 削除されたブロックが TASK-483.3 で決めた表現で扱われる
- [x] #4 mermaid ブロック・コードブロック・表を含む Markdown でも表示が壊れない
- [x] #5 差分が取得できない場合は通常のレンダリング表示に落ちる
- [x] #6 既存のソース表示での差分表示が退行していない
- [x] #7 差分ジャンプ（次の変更へ）がレンダリング差分でも効く
- [x] #8 削除ブロック内の見出し id が外れ、新版の見出しと二重にならない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計: docs/superpowers/specs/2026-11-21-rendered-markdown-diff-design.md（TASK-483.3）

1. csv-diff.ts の行→単位の割り当てと並べ替え（orderCsvDiffRecords）を、まばらな単位（どの単位にも属さない行がある）も扱える共通関数 orderDiffUnits に一般化し、新モジュール diff-units.ts へ移す。CSV はそれを使う
2. markdown-diff.ts: buildMarkdownDiffHtml(diffText) → string | null。全文差分から新旧を復元し、それぞれ markdownRenderer().parse してトップレベルブロック（level 0 の開き〜閉じ）を単位にする。単位ごとに renderer.render(tokens.slice, options, env) → sanitizeRenderedHtml。変更単位は <div class="md-diff-block diff-add|diff-del" data-diff-block=n> で包む。削除ブロック内の id を外す
3. _renderMarkdown が実際に描いた形（'diff' / 'markdown'）を返し、render() が recordShape する（appendChunk の既存の早期 return が効く）
4. CSS: .md-diff-block の地色・左帯・+/- の記号
5. Swift: FileType.supportsRenderedDiff に .markdown を足す（テスト更新）
6. 既存 jest『レンダリング表示の Markdown は差分が届いていてもチャンクを追記する』は前提（差分はモードを問わず届く）が誤りになったので、差分なしでの追記継続を見るテストへ置き換える

/review-design の結果（2026-11-21、TASK-483.3 として実施）
- 判定の源: 変更の有無は差分行の種別だけで決め、DOM では判定しない。縮退は差分本文の形（1 ファイル 1 ハンク・開始行 ≤1）
- 兄弟判断: 見出しジャンプは showsDiff で既に無効（ViewerCapabilities）。見出し id は削除ブロックから外して二重化を防ぐ。reveal-line は shape 'code'/'csv-source' 限定で 'diff' を通らない。mermaid は #diagram-wrap 配下の pre.mermaid を全部描くので包みの div の中でも描かれる。差分ジャンプは data-diff-block を数える（包みの div に付ける）
- 新しい状態の表示: 追加なし（差分が無ければ通常表示）
- 高頻度経路: render 時に新旧 2 回 parse するだけ。追記は止まる
- 既知の限界（参照リンク定義の変更・リスト全体の差し替え）は spec に記録
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: jest 全 794 件（viewer-markdown-diff.test.ts 10 件追加。旧テスト『レンダリング表示の Markdown は差分が届いていてもチャンクを追記する』は前提『差分はモードを問わず届く』が TASK-483 以後は偽なので削除し、差分なしでの追記継続は『描けない差分では通常のレンダリング表示へ落ち、追記も続く』で見る）、swift test --skip PDF 2015 件通過、webview-smoke に Markdown レンダリング差分の検査を追加（差分ブロック内で mermaid 2 図が SVG 化、帯色 add rgb(26,127,55) / del rgb(207,34,46)）。CSV と並べ替えを diff-units.ts に共通化した。実アプリの目視（/run）は未実施。

レビュー後の修正（2026-11-21）
- 未変更の判定を『反対側に同じ文脈行だけを覆う単位があるか』へ変えた（diff-units.ts）。『削除行を含む旧単位／追加行を含む新単位』だと、削除だけ・追加だけの変更（リスト項目の追加・削除、空行追加による段落の分割、CSV の引用符内への行追加）で片側にしか色が付かなかった。テストを追加
- レンダリング差分の組み立てを try/catch で包み、投げたら通常表示へ落とす（renderers.ts の _renderedDiff）。CSV の列数を Math.max(...rows) で求めていたのをループへ（JavaScriptCore の引数上限。webview-smoke で 20 万行を実測）
- サニタイズを連結後に 1 回だけにし（ブロックをまたぐ details を保つ）、削除ブロックの id は旧版のトークンから外す形にした
- 旧ヘッダの削除行を列の書式判定から外した
- 差分ジャンプの目印が Markdown の差分ブロックの地色を潰さないよう CSS で打ち消した。両面で差分ジャンプを辿る jest を追加
- Swift: DocumentSurfaceStack.rendererDiffState を純関数に切り出し、.rendered/.source には差分を渡さず .renderedDiff では渡すことを DocumentSurfaceDiffStateTests で固定
- 検証: jest 802 件、swift test --skip PDF 2018 件・--filter PDF 通過、webview-smoke 通過
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Markdown をレンダリング表示のまま差分表示できるようにした（⌘4）。viewer-src/markdown-diff.ts が全文差分から旧版・新版を parse し、トップレベルブロックを token.map で差分行へ引き当て、削除ブロック→追加ブロックを文書順に並べて div.md-diff-block（地色・左帯・+/-・data-diff-block）で包む。削除ブロック内の id は外す。並べ替えは CSV と共通の diff-units.ts（orderDiffUnits / wholeFileDiffSides）に移した。_renderMarkdown は描いた形を返し、'diff' のとき appendChunk は追記しない。FileType.supportsRenderedDiff に Markdown を追加し、⌘3 のソース差分は残る。docs/dev/viewer-ui.md を更新。
<!-- SECTION:FINAL_SUMMARY:END -->
