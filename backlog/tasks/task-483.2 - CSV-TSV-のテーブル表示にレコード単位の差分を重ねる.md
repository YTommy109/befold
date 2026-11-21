---
id: TASK-483.2
title: CSV/TSV のテーブル表示にレコード単位の差分を重ねる
status: Done
assignee:
  - '@claude'
created_date: 2026-08-14 12:46
updated_date: '2026-11-21T00:17:00Z'
labels:
  - diff
  - csv
milestone: m-4
dependencies:
  - TASK-483.1
parent_task_id: TASK-483
priority: medium
type: feature
ordinal: 702000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CSV/TSV をテーブル表示したまま、追加・削除されたレコードを色分けして表示する。

`viewer-src/csv-html.ts` の `buildTableHtml` が組み立てる `<tr>` に、既存の `diff-add` / `diff-del` クラス（`BefoldKit/Resources/style.css` に定義済み）を当てる。削除されたレコードは新しい内容には存在しないため、削除行として表に挿入する。差分ジャンプが効くよう、変更のある行には `data-diff-block` を付ける（`viewer-src/jump-providers.ts` はこの属性で変更箇所を数える）。

差分の入口を開けるため、`BefoldKit/FileType.swift` の `supportsDiffDisplay` から `.csv` の除外を外し、`viewer-src/renderers.ts` の `_renderDiffHtmlIfAvailable` にある `type === 'csv'` による早期 return も見直す。`render.ts` の `renderShape` で `csv-table` の分岐が差分を通るようにする必要がある。CSV で `diff` モードが何を意味するかは親タスク TASK-483 の「差分モードの意味」の結論に従う。

起票後に CSV テーブルへ入った機能（列幅の自動測定・切り取りと検索ヒットの表示・数値書式・列幅変更・スクロールバー。TASK-906 ほか）と、挿入した削除行がどう噛み合うかを決める。

- 削除行を列幅の自動測定に含めるか
- 削除行を検索の対象にするか
- ヘッダ行が変わったときの見せ方
- 左右分割レイアウト（`ViewerDiffBridge.Layout.sideBySide`）でテーブル差分をどう扱うか

セル単位の色分け（追加行と削除行をペアリングして値の違う `<td>` だけ光らせる）は、`pairDiffLines`（`viewer-src/diff-parse.ts`）と単語差分の `diff-words.ts` が再利用できるが、まずレコード単位で成立させることを優先し、セル単位は必要と判断した場合のみ同タスク内で追加する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CSV/TSV でテーブル表示のまま差分表示モードを選べる
- [x] #2 追加されたレコードが追加色、削除されたレコードが削除色で表示される
- [x] #3 引用符内に改行を含む CSV でも、色が正しいレコードに当たる
- [x] #4 差分が取得できない場合（未追跡・バイナリ・変更なし・サイズ超過）は通常のテーブル表示に落ちる
- [x] #5 差分表示中のチャンク追記が表を壊さない
- [x] #6 変更のあった行に data-diff-block が付き、差分ジャンプ（次の変更へ）がテーブル表示でも効く
- [x] #7 削除行の列幅測定・検索対象・ヘッダ行の変更・左右分割レイアウトでの扱いが決まり、その通りに動く
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
前提: TASK-483 Notes の『差分モードの意味の決定』（renderedDiff を 4 つ目のモードにする）。

Swift
1. FileType.supportsRenderedDiff を足す（この段では .csv のみ。Markdown は TASK-483.4 で足す）。supportsDiffDisplay（ソース差分）は据え置き（CSV は false のまま）
2. ViewerDisplayMode に case renderedDiff（menuItemTag 4 / menu.view.showRenderedDiff）。isSourceMode = .source|.diff、showsDiff = .diff|.renderedDiff
3. supported(for:): renderedDiff は supportsRenderedDiff の種別だけ。不可なら .diff と同じ降格。.diff が不可で renderedDiff が可なら renderedDiff へ（CSV で ⌘3 の記憶が残っていてもテーブル差分になる）
4. ViewerCapabilities に必須引数 supportsRenderedDiff と canSelectRenderedDiffMode（git の可用性も見る）。canSelect(.renderedDiff)。canToggleDiffLayout は showsCodeContent も要求（レンダリング差分ではレイアウト切替が効かない）
5. ViewerDiffPresenter.refresh のゲートを canSelectDiffMode → canSelect(store.displayMode) に（renderedDiff でも取得する）
6. ModeSegments.all に renderedDiff、symbol / labelKey、xcstrings（menu.view.showRenderedDiff / toolbar.mode.renderedDiff の en/ja）
7. switch 網羅の追従（コンパイラに拾わせる）

JS
8. csv-diff.ts: buildCsvDiffTable(diffText, delimiter) → {html, formats} | null。parseUnifiedDiff → 1 ファイル 1 ハンク（-U1000000 の全文差分）でなければ null。新旧全文を復元し csvRecordLineRanges でレコードへ引き当て、削除行を含む旧レコード＝削除、追加行を含む新レコード＝追加として文書順に並べる（同じ位置では削除→追加）。tr に diff-add/diff-del と data-diff-block（削除の連なり＋直後の追加の連なりを 1 ブロック、assignChangeBlockIndexes と同じ畳み方）
9. _renderCsv がレンダリング表示かつ差分ありのとき buildCsvDiffTable を使い、実際に描いた形（'diff' / 'csv-table'）を返す。render() はそれを recordShape する → appendChunk の既存の shape==='diff' 早期 return で追記を止める（DOM 判定はしない）
10. renderers.ts の _renderDiffHtmlIfAvailable の csv 除外は残す（CSV のソース差分は作らない）

AC #7 の決定
- 削除行は表に実在する行として列幅測定・数値書式判定・検索の対象にする（見えている行を測らないと切れる／検索で見つからない）
- ヘッダ: thead は新ヘッダ 1 行（変わっていれば diff-add）。旧ヘッダは tbody 先頭へ削除行として置く（csv-resize が tHead.rows[0] を見出しとして扱うため 2 行目を thead に入れない）
- 左右分割: レンダリング差分は常に 1 カラム。canToggleDiffLayout を false にしてメニュー・セグメントでも切り替えられなくする
- 色だけに頼らないよう、変更行の先頭セルに CSS で +/− の記号を出す

テスト: buildCsvDiffTable の単体（引用符内改行・ヘッダ変更・ブロック番号・不正差分で null）、render 経路（差分あり/なし、追記抑止、ジャンプ件数）、Swift（supported(for:)・canSelect・ModeSegments）

/review-design の結果（2026-11-21）
1 判定の源: レンダリング差分の可否は Swift の事実（supportsRenderedDiff・git 可用性）とモード値で決め、JS は『diff() が非 null』で描き分ける。diff() は showsDiff のときしか非 null にならない（ViewerDiffPresenter.refresh / DocumentSurfaceStack.diffState）。差分が壊れていれば null を返して通常表へ落とす。DOM の形では判定しない
2 不変条件: isSourceMode / showsDiff はモード値だけの関数のまま。降格は supported(for:) の 1 箇所
3 兄弟判断: (a) ContentUpdatePlanner の pending 見送りコメント『pending はソース系モードでしか生成されず』が偽になる → holdsPreviousFrame の判定自体はモード非依存なので、コメントだけ直す (b) ViewerDiffPresenter.refresh の canSelectDiffMode ゲート → canSelect(displayMode) (c) canToggleDiffLayout / ModeSegments.action（renderedDiff の押し直しはレイアウト切替にしない） (d) JS: appendChunk は shape で判定済み。関数ジャンプ（jump-providers）は shape==='code' 限定で 'diff' を通らない。見出しジャンプは showsDiff で無効 (e) CSS: github-markdown-css の tr:nth-child(2n) の縞が diff-add/diff-del の地色を上書きするので .csv-body 配下で詳細度を上げる
4 新しい状態の表示: 差分が取れない（未追跡など）ときは通常テーブル。既存のソース差分と同じ扱い（toolbar.mode.diff.degraded 等の既存表示）
5 順序: 差分の pending 中はモード切替だけの再描画を見送る既存挙動がそのまま効く（holdsPreviousFrame はモード非依存）
6 高頻度: canSelect は対応表の参照のみ。差分取得は renderedDiff を選べる種別でだけ起きる
7 測るもの: supported(for:) と canSelect を種別ごとにテストし、ModeSegments.all と menuItemTag の対応もテストする
8 世代管理: 既存の ViewerDiffPresenter の着地時照合（URL・isDiffShown・比較基準）をそのまま使う
9 粒度: supportsRenderedDiff は FileType に置き、ViewerCapabilities の必須引数にする（デフォルト引数にしない）
10 行数: ViewerCapabilities 194 / ViewerDisplayMode 89 / ModeSegments 49 / FileType 241 行。いずれも 1 プロパティと 1 case の追加で、責務は増えない
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装メモ
- renderers.ts の _renderDiffHtmlIfAvailable にある CSV 除外は残した（CSV のソース差分は作らない方針。CSV は .diff を選べず renderedDiff へ降格する）
- 検証: jest 全 785 件（viewer-csv-diff.test.ts 10 件を追加）、swift test --skip PDF 2014 件通過、scripts/webview-smoke.swift に CSV レンダリング差分の検査を追加し実 WebKit で追加行 rgba(46,160,67,0.15) / 削除行 rgba(248,81,73,0.15) / 文脈行 透明 を確認（縞の上書きに勝っている）
- 実アプリでの目視（/run）は未実施。サイト（site/src/views/features.tsx・shared.tsx）のショートカット表記 ⌘1/⌘2/⌘3 はリリース時に更新する前提で触っていない
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerDisplayMode に 4 つ目の renderedDiff（⌘4・ツールバー 4 つ目のセグメント）を足し、CSV/TSV でテーブル表示のまま差分を出せるようにした。Swift: FileType.supportsRenderedDiff（CSV のみ）、supported(for:) の降格（CSV の .diff → renderedDiff、非対応種別の renderedDiff → .diff/.rendered）、ViewerCapabilities.canSelectRenderedDiffMode（必須引数 supportsRenderedDiff）、レンダリング差分中はレイアウト切替を無効、差分取得のゲートを canSelect(displayMode) に。JS: viewer-src/csv-diff.ts が全文差分から旧版・新版を復元し、csvRecordLineRanges でレコードへ引き当てて削除/追加レコードを文書順に並べる（data-diff-block 付き）。_renderCsv は実際に描いた形を返し、'diff' のとき appendChunk は追記しない。CSS で行の地色と +/- の記号を出す。docs/dev/viewer-ui.md を更新。
<!-- SECTION:FINAL_SUMMARY:END -->
