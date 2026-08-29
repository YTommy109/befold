---
id: TASK-570
title: PDF 表示でも文書内検索をできるようにする
status: To Do
assignee: []
created_date: '2026-08-29 23:13'
updated_date: '2026-08-29 23:14'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 827000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PDF を開いているあいだ ⌘F が無効で、文書内検索ができない。これは ADR 0009（`docs/adr/0009-render-pdf-with-pdfkit.md`）で PDF の描画を viewer.html の `<iframe>` から PDFKit の `PDFView` へ移した際の意図的な帰結で、同 ADR の Consequences に「`PDFView` を使った PDF 内検索の実装は別タスクとする」と明記されている。本タスクがその別タスク。

現状（実測 / 2026-08-30 時点）:

- `ViewerCapabilities` の `canFind` は `onDocument && !isDirectHTMLMode && !isBinaryContent` で、PDF は `isBinaryContent` によって落ちる。画像も同じ条件で落ちている。
- `PDFDocumentRenderer.openFind` / `findNext` / `findPrevious` は空実装。doc コメントに「能力側で塞いであるのでここへは来ない。PDF 内検索を実装するときは、能力の条件と一緒に開けること」と書かれている。
- 検索 UI は viewer.html の `#mmd-bar` と `viewer-src/find.ts`（入力欄・3 トグル・件数表示・IME・前後移動）に閉じている。PDF 面（`PDFPreviewView` / `ZoomingPDFView`）には JS が居ないため、この UI をそのままは使えない。ここが実装コストの中心で、AppKit 側にバーを持つのか、バーだけを別の面として重ねるのかは設計判断になる。
- 検索そのものは PDFKit の公開 API で足りる（`PDFDocument` の文字列検索と `PDFView` の選択・移動）。追加の同梱物は不要で、ADR 0009 が pdf.js を採らなかった判断を覆す必要は無い。

設計上の論点（着手時に `/review-design` で扱うこと）:

- `canFind` の条件を `!isBinaryContent` から変えると画像も一緒に開いてしまう。画像には検索対象のテキストが無いので、種別の粒度を見直す必要がある。
- 検索の 3 トグル設定は `FindOptionsPreference` でアプリ全体に永続化されている。PDF 側が別の検索実装を持つと、同じトグルが面によって違う意味になりうる（PDFKit 側に正規表現・単語一致の直接の対応があるか要確認）。
- ADR 0002 の「能力が true なのに反応が無い形を作らない」に従い、能力を開けるのと adapter に実体を入れるのは同じ変更で行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PDF を開いた状態で ⌘F が有効になり、検索バーが開く
- [ ] #2 PDF 内の文字列を検索でき、ヒットが画面上で判別でき、次へ/前へで移動できる
- [ ] #3 ヒット件数と現在位置が既存の検索バーと同じ形で表示される
- [ ] #4 テキストを持たない画像では従来どおり ⌘F が無効のままである（canFind を緩めた副作用で開かない）
- [ ] #5 テキストレイヤーを持たない（スキャン画像のみの）PDF でヒット 0 件として振る舞い、無反応や誤動作にならない
- [ ] #6 検索の 3 トグル（大文字小文字区別・単語一致・正規表現）について、PDF で対応するもの／しないものを決め、しないものは押せない形にする
- [ ] #7 ViewerCapabilities の canFind の分岐がユニットテストで固定される（PDF は true、画像は false）
- [ ] #8 docs/dev/native-app-design.md の「PDF では検索とジャンプができない」旨の記述と ADR 0009 の Consequences を実態に合わせて更新する
- [ ] #9 ⌘F / ⌘G の Help ショートカット一覧（ViewerShortcutCatalog）の説明が PDF でも実態と合っている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査メモ（2026-08-30 / 起票時の実測。着手時は再確認すること）:

- PDF 検索の独立タスクは未起票だった。TASK-564.1 の Notes にも「PDF 内検索の実装（`PDFView` / `PDFDocument.findString`）… 必要になった時点で起票する」「未着手のまま」と残っている。本タスクがそれ。
- 現行の検索は完全に JS 側の DOM 走査（`viewer-src/find.ts` が `#diagram-wrap` 配下のテキストノードを走査し `Range` で `<mark class="mmd-find-match">` を挿入）。`WKWebView.find(_:configuration:)` などのネイティブ find API は使っていない。したがって PDFKit で描いている面には原理的に載らず、**別実装が要る**。
- PDF だけを開いた窓では WKWebView をそもそも作らない（TASK-564.7 / `DocumentSurfaceStack`）。検索バーを WebView 面に浮かせる案は成立しない見込みで、`PDFRotationOverlay` と同じくオーバーレイとして AppKit 側に新設する形が素直。
- **トグルの制約**: PDFKit の検索は `NSString.CompareOptions`（`.caseInsensitive` / `.literal` / `.backwards`）しか受けない。**正規表現と単語一致に対応する引数が無い**。3 トグルのうち PDF で成立するのは大文字小文字区別のみで、残り 2 つは自前実装するか PDF では出さないかの判断になる。
- 種別分岐の宛先決定は `DocumentSurfaces.operating(on:)` の 1 行に閉じている。ここは触らずに済むはず。
- 能力を開けるときは `isBinaryContent` を緩めるのではなく `FileType` 側に新しい述語（例: `supportsFind`）を足すのが素直（画像を巻き込まないため）。
- pdf.js 同梱で既存 JS 経路に載せる案は ADR 0009 で却下済み（バンドル増・CSP の `worker-src` / `blob:` 緩和・ベンダー監査対象増）。本タスクで蒸し返さない。
<!-- SECTION:NOTES:END -->
