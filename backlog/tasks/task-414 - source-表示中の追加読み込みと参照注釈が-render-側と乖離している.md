---
id: TASK-414
title: source 表示中の追加読み込みと参照注釈が render 側と乖離している
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 07:27'
updated_date: '2026-08-10 11:20'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 501500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
viewer-main.js の render() と appendChunk() が同じ関心（表示モードに応じた描画）を 300 行離れた場所でそれぞれ判定しており、同型のズレが 2 件出ている。CLAUDE.md の「同型のバグが 2 回目に出たら個別修正をやめて構造で塞ぐ」に該当する。

1. appendChunk が表示モードを見ない（viewer-main.js:1423）: `if (type === "md")` だけで分岐し _mmdViewOptions.mode() を一切参照しない。大きな .md（StringChunkReader が分割し「さらに読み込む」バナーが出るもの）を開き、source 表示に切り替えてから「さらに読み込む」を押すと、Swift 側 applyAppend（ViewerRenderer+RenderHelpers.swift:69）が ViewerBridge.appendChunkScript(chunk:fileType:) で FileType しか渡さないため JS は type === "md" と判断し、md.render(text) の結果を source の <pre><code><table class="code-table"> の下へ insertAdjacentHTML する。行番号のない描画済み Markdown が生ソースの下に挟まり、以降の行番号も連続しない。2 行下の CSV 分岐は同じ事故を避けるために実 DOM（pre code.csv-source）を見に行っており、md だけが漏れている。

2. source 表示でパス参照が注釈されない（viewer-main.js:1707）: render() の source 分岐（:1706-1710）は _renderSource → _mmdRestoreScrollPosition → return で、共通の末尾にある _annotatePathRefs()（:1740）と _mmdResolveReferences()（:1741）へ到達しない。.md の source 表示ではパス文字列がただのテキストになる一方、同じ文字列が .swift（type === "code" は source 分岐から除外され _renderCode 経由で末尾へ到達する）ではクリックできる。さらに同じ source 表示の中でも、チャンク追加後は appendChunk が _walkTextNodes（:1489）と _mmdResolveReferences（:1499）を呼ぶため、追加された行だけリンクになり上の行は死んだままになる。同一文書で 3 通りの挙動になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 source 表示中に「さらに読み込む」を押しても、追加分がソース表示（行番号つき・行番号連続）として追記される
- [x] #2 source 表示の初回描画でもパス参照が注釈・解決される（.md と .swift で挙動が一致する）
- [x] #3 チャンク追加の前後でパス参照の挙動が変わらない
- [x] #4 render と appendChunk が表示モード判定を共有し、片方だけ直せる構造になっていない（判定を複製したら落ちるテスト、または共通経路への一本化）
- [x] #5 Node テスト（viewer.js 側の純粋ロジック）で表示モード判定を検証する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー（/review-design のチェックリスト適用）

1. 判定の真実の源: appendChunk は「DOM の形(pre code.csv-source)」と「type だけ」で描画形を推測している。DOM の形はユーザーコンテンツでも作れる(TASK-339 の再来)。判定を「render が実際に何を描いたか」の内部状態 1 つへ移す。なお Swift から mode を渡す必要は無い——canConsumePendingAppend が isSourceMode を含む RenderedStateMirror 全体比較でモード不変を保証しており(ViewerRenderer+RenderHelpers.swift:201-209)、append 時点の _mmdViewOptions.mode() は正しい。それでも記録すべきは mode ではなく「描いた形」(差分が出ているかは mode だけでは決まらない)。
2. 既存の不変条件との衝突: source の早期 return をやめて共通末尾へ流すと _mmdPdfBlob.release() と _mmdRunMermaid が source 経路でも走る。前者は解放漏れの解消。後者は .mermaid 要素 0 件で即 return（viewer-main.js:1654 実測）なので mermaid.min.js の遅延ロードも起きない。
3. 消費経路と兄弟判断の全列挙: 表示形の判定は 3 系統（render:1706 の mode 判定 / appendChunk:1422-1434 の type+DOM / _mmdDiffInDom:1187,1418,1790）。加えて _renderCode と _renderSource が「ソース表示の入口」を二重に持ち、コード自身のコメント(1624-1626)が『片方だけに足すと .md では差分が出るのに .swift では出ない抜けになる』と過去の実例を記録している。2 つの入口を 1 つの builder へ統合する。
4. 新しい状態に対応する表示: 表示状態は増えない（既存の描画形に名前を付けるだけ）。ユーザー向け文言の追加は不要。
5. ライフサイクル・順序: _renderSource が自前で呼んでいた _mmdFindRefreshAfterRender / _mmdApplyZoom は共通末尾へ移り、描画→mermaid→注釈→参照解決→検索→ズーム→スクロール復元の順序が全経路で一本化される。
6. 高頻度経路のコスト: 該当しない。render/appendChunk は文書更新時のみ。追加分は source 経路での querySelectorAll('.mermaid') 1 回（0 件で即 return）。
7. 測るものと守るもの: 純粋関数のテストだけでは配線の抜けを検出できないため、viewer.js の純粋関数テストと jsdom での追記テストの両方を置く。
8. 非同期の世代管理: _mmdRenderedAs は render() の同期区間で確定し、_renderDiffHtmlIfAvailable が差分成立時に上書きする。await _mmdRunMermaid より前に確定するため、await 中に届く appendChunk が古い値を読むことはない（現行 _mmdDiffInDom と同じ位置づけ）。
9. 決めた粒度を守らせるもの: (a) viewer.js の純粋関数の全組み合わせテスト、(b) jsdom で source 表示中の追記がソース行として入るテスト、(c) _renderCode を消して入口を 1 つにする（構造で破れなくする）。

## 実装手順

1. viewer.js に純粋関数 renderShape(type, mode) を追加し export する。返す値は追記戦略と 1 対 1（markdown / csv-table / csv-source / code / mmd / svg / html / image / pdf）。
2. viewer.test.js に (type × mode) 全組み合わせのテーブルテストを追加する。
3. viewer-main.js: _mmdDiffInDom を _mmdRenderedAs へ置き換え、_renderCode を _renderSource へ統合し、render() は renderShape の結果で分岐して source でも共通末尾（_annotatePathRefs / _mmdResolveReferences）へ到達させる。
4. appendChunk は _mmdRenderedAs だけで分岐する（type による分岐と DOM 検索を撤去）。
5. jsdom テスト: source 表示中の追記が行番号つきで連続すること、source 初回描画でパス参照が注釈されること、追記の前後で挙動が変わらないこと。
6. ドキュメント: docs/dev/viewer-rendering-dataflow.md のソースモード節と appendChunk 節、text-loading-dataflow.md の用語表（markdown を非行指向=全量と書いているが isChunkable は true。ViewerLoadPipeline.swift:82-95 が実際にチャンク化する）。
7. 検証: npx jest（4 スイート約 380 件）、swift test、markdownlint。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装結果

判定を「表示モード」ではなく「render() が実際に描いた形(shape)」へ寄せ、render と appendChunk の 2 つの判定を 1 つの記録へ畳んだ。

1. viewer.js に純粋関数 renderShape(type, mode) を追加。返す値は追記戦略と 1 対 1（markdown / csv-table / csv-source / code / mmd / svg / html / image / pdf）。
2. viewer-main.js: _mmdDiffInDom（真偽値）を _mmdRenderedAs（描いた形）へ置き換え。render() が renderShape の結果で分岐すると同時に記録し、_renderDiffHtmlIfAvailable だけが 'diff' へ上書きする。
3. appendChunk は _mmdRenderedAs だけで分岐する。type による分岐と DOM 検索（pre code.csv-source）を撤去した。type は ViewerBridge の共通呼び出し形で届くため引数には残すが、分岐に使わない旨を doc コメントで明示した。
4. source の早期 return を撤去し、共通末尾（_annotatePathRefs / _mmdResolveReferences）へ到達させた。これで .md のソース表示でもパス参照が注釈される。
5. ソース表示の入口だった _renderCode と _renderSource を 1 本へ統合した。両者は言語写像だけが違い（_sourceLanguage が吸収）、コード自身のコメントが『片方だけに足すと .md では差分が出るのに .swift では出ない抜けになる』と過去の実例を記録していた。

Swift 側は変更不要だった。canConsumePendingAppend が isSourceMode を含む RenderedStateMirror 全体を比較しており、モードが変われば追記ではなく全文 render へ倒れるため、追記時点の JS 側のモードは常に直前の描画と一致している（appendChunkScript にモードを足す案は不要と判断）。

## 検証（すべて実測）

- npx jest: 6 スイート 417 件すべて通過（変更前 391 件 + 新規 26 件）。
- 修正前に失敗を確認: 新規 jsdom テスト 6 件中 5 件が失敗し、対照の『レンダリング表示では従来どおり』1 件だけが通る状態から着手した。純粋関数テストは 18 件全滅（renderShape 未実装）。
- トリップワイヤの実効性を実測: appendChunk の判定を type ベースへ戻すと 3 件失敗、CSV を type のみの判定にすると 4 件失敗することを確認してから元へ戻した。
- swift test: 1385 tests / 202 suites 通過。
- swiftlint: origin/main とのベースライン差分なし。swiftformat --lint 0 件。markdownlint-cli2: 67 ファイル 0 issues。

## 契約テストの更新（レビュー時に見てほしい点）

ViewerBridgeContractTests の『FileType.jsValue が render() の type 分岐に対応している』は、viewer-main.js に type === '<jsValue>' の文字列があることを検査していた。render() が shape で分岐するようになったため、jsValue → 描画形の対応表を持たせ、viewer.js に renderShape があること・viewer-main.js に shape === '<形>' 分岐があることを検査する形へ書き換えた。検査の目的（種別を足したときに描き手がいない状態を見逃さない）は変えていない。

## ドキュメント

- docs/dev/viewer-rendering-dataflow.md: 描画形の表を追加し、appendChunk が type で分岐しないこと・Swift が追記時にモードを渡さない理由を明記。
- docs/dev/text-loading-dataflow.md: 用語表が markdown を『非行指向＝全量一括』としていたが、FileType.isChunkable は markdown を含み ViewerLoadPipeline.swift:82-95 が実際にチャンク化する。『ブロック指向』として実態に合わせ、新フロー図も修正した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
render() と appendChunk() が「表示モードに応じた描画」を別々に判定していたことによる 2 件のズレを、判定の一本化で解消した。viewer.js に純粋関数 renderShape(type, mode) を置き、render() がその結果で分岐すると同時に _mmdRenderedAs へ記録、appendChunk はその記録だけで追記戦略を決める。これに伴い _mmdDiffInDom（真偽値）と CSV の DOM 検索と type 分岐が 1 つの値に畳まれ、ソース表示の入口だった _renderCode と _renderSource も 1 本へ統合した。source 分岐の早期 return を撤去して共通末尾へ流したことで、.md のソース表示でもパス参照が注釈される。Swift 側は canConsumePendingAppend がモード不変を保証しているため変更不要。jest 417 件・swift test 1385 件通過、swiftlint ベースライン差分なし、markdownlint 0 issues。判定を type ベースへ戻すと新規テストが 3〜4 件落ちることを実測で確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
