---
id: TASK-902
title: 検索ハイライトを Custom Highlight API に一本化し、`<mark>` 挿入経路を削除する
status: Done
assignee: []
created_date: '2026-10-30T10:20:00Z'
updated_date: '2026-10-30T11:28:00Z'
labels: []
dependencies:
  - TASK-903
priority: low
ordinal: 862000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #741（外部コントリビュータ、大きな CSV の描画・検索の高速化）は、検索ハイライトを CSS Custom Highlight API（`StaticRange` + `::highlight`）で描く経路を追加したが、適用対象を CSV の表・ソースに限定している（`find-scan.ts` の `walk` が `root.matches(".csv-body, .code-body:has(code.csv-source)")` で判定）。そのため Markdown・ソースコード・差分は従来の `<mark>` を DOM へ挿入する経路を通り、二つの経路が日常的に並走する。片方にしか無い不具合（現在位置の付け替え・スクロール・再描画後の索引破棄など）が出やすい形である。

最低対応 OS を macOS 14.2 へ上げれば（TASK-903）API が常に使えるため、形式による分岐だけでなく `<mark>` 経路そのもの（`clearMarks` の unwrap / normalize、`matchScope` の `extractContents` / `insertNode`、`pruneEmptyAncestors`、`supportsHighlights` による判定、`mark.mmd-find-match` の CSS）を削除でき、検索は 1 本の経路になる。大きなソースコード・差分でも DOM 書き換えが消えて速くなる。また `<mark>` を差し込めないため検索対象外にしている mermaid の SVG（`find-scan.ts` の `skipTags`）を対象にできる可能性がある（WebKit が SVG テキストに `::highlight` を描くかは未確認）。

注意点: PR #741 の `find-highlight.ts` の `updateNativeHighlights` は、画面付近のヒットだけを登録するために「文書順のヒットは画面上でも上から下へ並ぶ」前提で二分探索する。CSV・code-table では成り立つが、Markdown では閉じた `<details>` の中身の矩形が 0 になるなどで崩れ、見えているヒットが塗られない恐れがある。

現在位置の印付けはジャンプバーと共通の `navigation.ts` の `moveCurrentHighlight`（要素へ class を付ける方式）を使っている。検索側だけが Highlight API に移ると、この共通経路から外れる点も設計時に扱う。

着手条件: PR #741 がマージされていること（未マージなら、この経路自体が main に無い）と、TASK-903 の完了。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 全形式（CSV・Markdown・ソースコード・差分）の検索が `<mark>` を DOM に挿入せず、`<mark>` 挿入経路のコードと CSS が削除されている
- [x] #2 経路の選択が形式（クラス名・要素の一致）にも API の有無にも依存しない
- [x] #3 Markdown で閉じた `<details>` など画面上の並びが文書順と一致しない内容でも、表示されているヒットがすべてハイライトされる（回帰テストあり）
- [x] #4 大量ヒット（数万件以上）のソースコードで、1 打鍵の検索時間が PR #741 の CSV と同程度に収まることを実測で確認し、数値を Notes に残す
- [x] #5 mermaid の SVG テキストを検索対象に含めるかを実測のうえ決め、結果を Notes に残す
- [x] #6 `docs/dev/` の検索の仕様記述を新しい経路に合わせて更新する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
前提（裏付け）:
- 最低対応 14.2 で Custom Highlight API は常にある（TASK-903 Notes: WebKit Safari 17.2 ブログ）。
- 左右分割の差分は外側 1 行に左右の内側 <tr> が 1 つずつ（diff-html.ts renderSideBySideDiffHtml）→ closest("tr") の矩形は文書順に単調。CSV・code-table も単調。崩れるのは閉じた <details> 等の非表示内容（矩形 0）。
- markdown-it は html:true + DOMPurify（markdown.ts）なので <details> / <mark> は文書に現れうる。

1. find-scan.ts: <mark> 経路を削除（supportsHighlights / usingNativeHighlights / matchScope の ranges・domRange・extractContents・insertNode / pruneEmptyAncestors / clearMarks の unwrap）。walk は常に StaticRangeInit を返し、索引キャッシュ（indexedScopes）は全形式で使う。FindMatch は StaticRangeInit に一本化。skipTags から MARK を外し bridgeTags に加える（利用者が書いた <mark> の中身も検索できるようにする。以前は自前の mark と区別できないので除外していた）。
2. find-host.ts: moveFindHighlight を Highlight API だけにし、instanceof 分岐と moveCurrentHighlight の import を削除。navigation.ts の moveCurrentHighlight はジャンプ専用として残し、コメントの「検索とジャンプで実装を 1 箇所に」を実態（検索は scrollFindRange で同じ center/smooth を再現）に合わせて直す。
3. find-highlight.ts: 画面付近だけ登録する間引き（二分探索）は、ヒット件数が閾値を超えたときだけ行う。閾値以下は全件登録し、文書順と縦の並びが一致しない内容（閉じた <details> 等）でも見えているヒットを落とさない。閾値は実 WebKit で N 件登録のコストを測って決める。閾値超えかつ非単調な内容は既知の上限として ponytail コメントに残す。
4. style.css: mark.mmd-find-match / -current を削除。PDFFindHighlighter.swift の色の参照コメントを ::highlight に直す。
5. テスト: CSS.highlights / Highlight / rAF のモックを viewer-test/support/viewerMainHarness へ移し全テストで有効にする。viewer-main-find.test.ts の mark 前提のアサートを highlights 前提に書き換え、find-highlight.test.ts の mark フォールバックのテスト（170-191, 289-312）を全形式ネイティブの検証へ反転。閉じた <details> の回帰テスト（間引きを強制すると落ちることを確認）。
6. 計測: scripts/benchmark-csv.swift に種別引数を足し（mark 計数も削除）、大きなソースコードで 1 打鍵の検索時間を測る。SVG テキストへの ::highlight 描画は独立ハーネス + takeSnapshot で実測し、描かれれば利用者に確認のうえ SVG を対象に含める、描かれなければ除外のまま記録。
7. 文書: docs/dev/viewer-ui.md の検索の節、docs/dev/csv-performance.md の mark 記述を更新。viewer-bundle.js 再生成、Jest 全件・oxlint type-aware・format check。

設計レビュー（/review-design, 2026-10-30）の結論:
- (a) 間引きは閾値超えのときだけ。caretRangeFromPoint 案は WebKit の実測と変更量が大きく採らない。閾値以下ではスクロール・リサイズ・style 変更の通知で何も測らずに戻る（高頻度経路のコスト = 項目 6）。閾値は module 定数 1 つ。
- (b) 索引キャッシュの無効化: #diagram-wrap の本文を書き換えるのは render（開始時 invalidate、着地時 refresh が clearFindCache）と appendChunk（末尾で _mmdFindRefreshAfterRender）だけ（rg で DOM 変更呼び出しを列挙: render.ts / renderers.ts / path-refs.ts / zoom.ts は render 内、csv-resize.ts の fitColumn の probe は同期で append→remove）。<mark> 経路が唯一の帯域外の書き換えだったので、削除後は MutationObserver を足さない。PR #741 の CSV 限定のキャッシュ追随テストを Markdown・ソースにも広げて担保する（項目 3・5・8）。
- (c) MARK は bridgeTags へ（利用者の <mark> の中身が検索対象になる挙動変化として Notes に残す）。SVG は実測で決める。
- (d) 検索とジャンプは同時に開かない（registerBar が排他）。中央寄せ・smooth の UX は検索側 scrollFindRange と navigation.ts の scrollIntoView の 2 箇所になるため、scrollFindRange の中央寄せを既存テスト（200% ズームの 2 軸スクロール）で担保し、navigation.ts のコメントを直す。
- 経路選択はクラス名でも API 有無でもなくなる（項目 1）。型グループ行数（項目 10）は Swift 向けで該当なし、find-scan.ts は縮む。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-30: PR #741 は main へ squash マージ済み（637e6faf）。残る着手条件は TASK-903 の完了のみ。

実装: find-scan.ts の <mark> 経路（clearMarks の unwrap / normalize、matchScope の extractContents / insertNode、pruneEmptyAncestors、supportsHighlights と root.matches による形式判定）を削除し、walk は常に StaticRangeInit を返して Highlight に登録する。索引キャッシュは全形式で使う。find.ts の currentHighlight（直前の <mark> のクラスを外すためだけの状態）も削除。style.css の mark.mmd-find-match* を削除。テストの Highlight API モックは viewerMainHarness の installBrowserStubs へ移し、findHighlights で登録内容を読む。

MARK を skipTags から bridgeTags へ移した。挙動の変化: 利用者が Markdown に書いた <mark> の中身が検索対象になる（以前は自前の mark と区別できないため除外していた）。

間引き: 一致が 2,000 件（CULL_THRESHOLD）を超えるときだけ画面付近に絞る。閾値以下はスクロール等の通知でも測り直さない。回帰テスト「document order that disagrees with vertical order still paints every visible match」は、閾値を一時的に 0（常に間引く）にすると "hit one" が塗られず落ち、2,000 に戻すと通ることを確認した。

実測（macOS 27.2、scripts/benchmark-csv.swift、1200×800、前後交互に各 3 回の中央値（最大）。前 = main 637e6faf の Resources、後 = この変更）。20,000 行の Swift ソース（.tmp/csv-perf/large-source.swift、行番号付き、--type=code --lang=swift）: s（149,737 件）1,593ms(1,603) → 78ms(80)、sa（30,070 件）1,405ms(1,438) → 4ms(5)、sample（30,070 件）1,037ms(1,037) → 4ms(4)、不一致 788ms(801) → 2ms(2)。描画 1,560ms → 1,550ms で差なし。変更前は 149,737 個の <mark> を挿入していた。

閾値の妥当性（同条件、--type=md）: 1,990 件を全件登録しても 1 打鍵 3〜5ms（s 5.0 / sa 3.0 / sample 3.0、登録 1,990）。2,200 件（間引き、登録 80）は 1〜4ms。2,000 件以下で全件登録のコストは問題にならない。計測値は workMs + layoutMs で、描画（paint）時間は含まない。

SVG: 独立 WKWebView（macOS 27.2）で ::highlight(probe){background red} を HTML の <p>・SVG の <text>・SVG 内 <foreignObject> の HTML に登録して takeSnapshot した結果、赤画素は HTML 6,961 / SVG text 0 / foreignObject 5,907。WebKit は SVG の <text> に ::highlight を描かない。mermaid は図の種類によって <text> と foreignObject のラベルを使い分けるため、含めると件数に入るのに見えない一致が出る。SVG は対象外のまま（skipTags に SVG を残す）。foreignObject のラベルだけ対象にする案は挙動の拡張なので本タスクでは行わない。

/code-review high の指摘への対応（同コミットへ amend）: (1) 間引きが崩れる原因の説明を訂正——閉じた <details> の矩形 0 は「窓の内側」と判定され登録範囲を広げるだけで害がなく、本当に崩すのは float / position で文書順より上に描かれる内容。コメント・docs・テストの説明を直した。(2) setNativeHighlights が自分で前回の登録と描画済み区間を捨てる（件数が同じ別クエリで古い範囲が残る穴を呼び出し側の手順に頼らず塞ぐ）。(3) スクロール・リサイズ・style 変化の監視は閾値超えのときだけ付ける。(4) 図のズーム操作（.diagram-zoom-controls）を索引と検索対象から外す（倍率変更で label のテキストノードが差し替わり、索引が切り離されたノードを指していた。テストはスキップを外すと落ちることを確認）。(5) clearFindHighlights / invalidateFindDocument の別名を削除し、find.ts が clearNativeHighlights を直接呼ぶ。(6) 閾値超えの Markdown（Range の矩形で測る経路）の間引きとスクロール追従のテストを追加。(7) 2,000 件超かつ並びが食い違う文書は既知の上限のまま（ponytail コメント）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
検索ハイライトを全形式（Markdown・ソース・差分・CSV）で CSS Custom Highlight API に一本化し、<mark> を DOM へ挿入する経路を削除した。経路の選択は形式にも API の有無にもよらない（最低対応 14.2 は TASK-903）。間引きは 2,000 件超のときだけにし、文書順と縦の並びが一致しない内容でも見えている一致を落とさない（回帰テストは閾値 0 で落ちることを確認）。利用者が書いた <mark> の中身も検索対象になった。SVG は WebKit が <text> に ::highlight を描かない（実測）ため対象外のまま。検証: Jest 724 件、型チェック 2 面、oxlint type-aware、oxfmt、markdownlint。実測で 20,000 行のソースの s 検索（149,737 件）が 1,593ms → 78ms。
<!-- SECTION:FINAL_SUMMARY:END -->
