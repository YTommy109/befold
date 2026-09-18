---
id: TASK-528
title: 差分表示で変更行の単語単位の差分も見せる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-19 07:14'
updated_date: '2026-09-18 11:03'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 770000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
行が変更されたとき、いま差分表示は行全体を赤／緑で塗るだけで、行のどこが変わったのかが分からない。1 文字だけ直した長い行と、行ごと書き換えた行が同じ見た目になる。変更行の中で実際に変わった語だけを強調して、変更箇所を目で追えるようにする。

前提（調査済み、2026-08-19 時点）:

- 同梱している libgit2 1.9.0 に word-diff 機能は無い。公開ヘッダ `include/git2/diff.h` に `word` を含む識別子は 0 件、`src/` にも `word-diff` 相当の実装は無い（実測）。git CLI の `--word-diff` は git 本体の `diff-words.c` にある後処理で、libgit2 は移植していない。したがって「libgit2 のオプションを 1 つ足せば済む」形にはならず、単語分割と差分計算はこちら側で用意する。
- ただし libgit2 の diff エンジン自体は流用できる。`git_diff_buffers`（`include/git2/diff.h:1303`）と `git_patch_from_buffers`（`include/git2/patch.h:130`）が任意の 2 バッファを行単位で diff できるので、「単語ごとに改行した文字列」を渡せば単語単位の差分が得られる（git 本体と同じ発想）。
- 現状の差分は Swift 側で構造化されていない。`GitDiffReader` が `git_diff_to_buf(GIT_DIFF_FORMAT_PATCH)` で作った unified diff を生テキストのまま `GitFileDiff.diff(String)` として持ち（`BefoldApp/befold/App/GitDiffReader.swift:112`, `BefoldApp/befold/App/GitFileDiff.swift:8`）、`ViewerDiffBridge.textScript` がそのまま JS へ渡す（`BefoldApp/BefoldKit/ViewerDiffBridge.swift:21`）。行構造への分解は `viewer-src/diff-html.ts:53` の `parseUnifiedDiff` が唯一の場所で、行の型は `DiffLineType = 'context'|'add'|'del'` の 3 値しかない（`viewer-src/diff-html.ts:14`）。
- 行内の文字差を計算するコードは Swift・TS のどちらにも存在しない。`BefoldKit/Resources/style.css:693-695` に「語単位の差分は出していない」ためジャンプ候補の下線を消す、という記述があり、この前提が今回覆る。

主な設計論点（着手時に `/review-design` で決める）:

1. **計算をどこで行うか。** (a) Swift 側で `git_diff_buffers` を使い、ブリッジの契約を生 unified diff から構造化データへ変える。(b) JS 側の `diff-html.ts` で完結させ、Swift とブリッジには一切触れない。(b) は影響範囲が小さいが単語分割アルゴリズムを自前で持つことになり、(a) は libgit2 に寄せられるがブリッジ契約の変更が QuickLook 拡張（`BefoldRenderKit`）まで及ぶ。
2. **削除行と追加行の対応付け。** 単語差分は「どの削除行とどの追加行が同じ行の変更か」が決まって初めて計算できる。side-by-side 用の `pairDiffLines`（`viewer-src/diff-html.ts:361`）が既にあるが、inline レイアウトでも同じ対応付けが要るか、両レイアウトで見せ方を揃えるかを決める。
3. **構文ハイライトとの重ね合わせ。** 行の内容セルは hljs が出した span 構造をそのまま入れている（`viewer-src/diff-html.ts:138`, `:174`、`viewer-src/code-html.ts` の `reflowSpanBalancedLines`）。単語強調の span を後から重ねると入れ子が壊れうるので、どちらを外側にするかを決める。
4. **単語の切り方。** 空白区切りか、CJK・記号・識別子まで踏み込むか。befold は日本語文書を主対象にしているので、空白区切りだけだと日本語の行でほぼ効かない。
5. **やらない場合の線引き。** 行が丸ごと書き換わったときに全語を強調すると、いまと同じ見た目になるうえ計算が無駄になる。類似度の下限を設けて単語差分を出さない判断が要るか。

対象範囲: ソース表示上の差分（inline / side-by-side の両方）。TASK-483 系のレンダリング表示への差分重ねは対象外で、そちらが入ったあとに単語差分を持ち込むかは別途判断する。

本機能は `FeatureGate.isSourceDiffEnabled` 配下にあるため、コミット件名に `(gate)` を付ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 変更行のうち実際に変わった語だけが、行全体の色とは区別できる強調で表示される
- [x] #2 inline レイアウトと side-by-side レイアウトの両方で単語単位の差分が表示される
- [x] #3 日本語（空白で区切られない文）の行でも単語単位の差分が機能する
- [x] #4 構文ハイライトの表示が単語強調によって崩れない
- [x] #5 単語単位の差分が出せない・出さないと判断した行は、従来どおり行全体の色分けで表示され退行しない
- [x] #6 計算場所（Swift / JS）の選択と、その理由が Implementation Notes に記録されている
- [x] #7 style.css:693-695 の「語単位の差分は出していない」前提に依存した既存の記述・挙動が更新されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 起票時の前提を実コードで検証し、ずれを Notes に残す（済: FeatureGate.isSourceDiffEnabled は現存せず差分表示は stable 済みのため (gate) は付けない。style.css の「語単位の差分は出していない」記述も現存しない）。
2. 計算場所は JS 側（viewer-src/diff-html.ts）に決める。ブリッジは生 unified diff 文字列を渡す契約（BefoldKit/ViewerDiffBridge.swift）で、構造化に変えると BefoldRenderKit / QuickLook まで波及する。libgit2 の git_diff_buffers は行あたり 1 回の diff 呼び出し + 新しい Swift↔JS 契約が要る。
3. 単語分割は Intl.Segmenter(granularity:'word') を使う（自前の分割器を持たない）。macOS 14+ = Safari 17 で利用可、Node 24 のテスト環境でも利用可。日本語も辞書分割される（実測: 'これは日本語の文です。' → これ|は|日本語|の|文|です|。）。未提供環境では語差分を出さずに従来表示へ落とす。
4. 対応付けは既存の pairDiffLines を唯一の経路にする。ハンク単位で「行添字 → 強調範囲配列」を 1 回作り、inline / side-by-side の両方が同じ結果を添字で引く（レイアウトで見え方が食い違わないことを構造で担保）。
5. 語差分は共通接頭辞・共通接尾辞の除去で求める（中間を強調）。行全体が強調になる場合は語差分を出さず従来の行単位色分けに落とす（計算の無駄と見た目の同一化を避ける）。
6. 強調はハイライト済み行 HTML のテキスト実行部だけを分割して包む（タグ境界をまたがない）ので hljs の span 入れ子は壊れない。復号後の文字数が元テキストと一致しない行は防御的に強調を諦める。
7. CSS に語強調のスタイルを足す（色だけに頼らず下線を併用）。
8. viewer-test にテストを足す: 行内の一部だけが強調される / inline と side-by-side で同じ強調になる / 日本語行で語単位に割れる / hljs の span 構造が壊れない / 行全体変更では強調しない。

## /review-design の結果（着手前・10 項目）

1. 判定の真実の源: 対応付けは行テキストの類似度や DOM ではなく unified diff の構造（pairDiffLines の del/add の連なり）で決める。語差分を出さない判定も「範囲が空か」ではなく「行全体が強調になるか」という事実で決める。Intl.Segmenter の有無も typeof で事実判定。
2. 既存の不変条件: highlightedDiffLines の「戻り値は hunk.lines と同じ長さ・同じ添字で引ける」(diff-html.ts のコメント)を、語強調範囲の配列にも同じく課す。ずれると呼び出し側が undefined を掴む。
3. 消費経路の全列挙（実測）: jump-providers.ts の .line-content textContent 読み（span 追加で不変）/ 同ファイルの hljs-comment・hljs-string 存在判定（hljs の span は分割しないので不変）/ path-refs.ts の _PATH_ANNOTATE_TAGS に span は無い（注釈単位を割らない）/ render.ts の appendChunk は shape()==='diff' には来ない（document-state.ts の記述）/ find.ts は Range.extractContents で既に hljs span をまたぐ形を扱っており新しい壊れ方は増えない。絞り込み点は「範囲算出 1 本 + HTML 適用 1 本」で、両レイアウトはこの 2 本しか呼ばない。
4. 新しい状態の表示: 新状態は「語差分を出さない行」だけで、従来の行全体色分けがそのまま表示になる（新しい文言は不要）。
5. ライフサイクル: 同期描画のみ、キャッシュ追加なし。Intl.Segmenter はモジュールスコープで 1 回だけ生成（純粋・syscall なし）。
6. 高頻度経路のコスト: 語分割が走るのは対になった変更行だけ。差分全体は Swift 側で 1 MiB 上限（GitDiffReader.swift の maxDiffBytes = 1 << 20）なので、総量は既に hljs がハイライトしている量と同じオーダー。→ 根拠を持てない行長上限は置かない。
7. 測るものと守るもの: テストは「どの部分文字列が強調されたか」を測る（クラス名や範囲の数え方という実装の決め打ちではなく）。
8. 非同期の世代管理: 非同期処理を足さないので該当しない。
9. 粒度を守らせるもの: 「inline と side-by-side で同じ強調」は、経路を 1 本にする構造と、両レイアウトの強調部分文字列が一致することを見るテストの両方で担保する。
10. 型グループの行数: Swift ではないので check-type-group-size.sh の対象外。diff-html.ts は現行 521 行。語分割・範囲計算・HTML 適用は新規モジュール viewer-src/diff-words.ts へ置き、diff-html.ts には呼び出しだけを足す。

レビューで変えた点: (a) diff-html.ts を太らせず diff-words.ts を新設する、(b) 速度のための行長上限は置かない（1 MiB 上限が既にある）、(c) 範囲配列に長さ不変条件を課す、(d) レイアウト間一致のテストを担保に加える。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 起票時の前提のうち、実コードと違っていたもの

- **`FeatureGate.isSourceDiffEnabled` は存在しない。** `rg 'isSourceDiffEnabled' --include=*.swift` が 0 件で、`FeatureGate` に残る名前付きプロパティは `isDocumentJumpEnabled` だけ（BefoldApp/befold/App/FeatureGate.swift）。差分表示自体は stable 済みなので、コミット件名に `(gate)` は付けない。
- **style.css の「語単位の差分は出していない」という記述は現存しない**（AC#7 が指していた 693-695 行）。現在その位置にあるのは図のズームコントロールで、`.diff-table .mmd-jump-target` を打ち消している理由も「変更ブロックは地色で既に全部見えており、そのうえに別の地色を重ねると差分の色分けが読めなくなる」で、語差分の有無とは独立していた。したがって挙動の変更は不要。語差分を前提にしていた記述は libgit2 の ADR 側にあり、そちらへ追記した（docs/adr/0006）。

## AC#6: 計算を Swift ではなく JS で行う理由

- ブリッジの契約は生の unified diff 文字列（`BefoldKit/ViewerDiffBridge.swift` の `textScript`）。構造化データへ変えると `BefoldRenderKit` 経由で QuickLook 拡張まで波及する。
- 起票時の調査どおり libgit2 1.9 に word-diff は無い。`git_diff_buffers` を使う案は、行ごとに diff 呼び出しを 1 回ずつ足したうえで**単語分割は結局こちらで用意する**ことになり、Swift 側でやる利点が消える。
- 語差分は行テキストだけで完結するので、JS 側に閉じると Swift・ブリッジ・QuickLook のいずれにも触らずに済む（実際この変更の Swift 差分は 0）。

## 実装の要点

- 新規 `viewer-src/diff-words.ts`（分割・範囲計算・HTML への適用）と、`diff-html.ts` の `wordRangesForHunk` / `diffLineHtml`（表への載せ方）で責務を分けた。diff-html.ts は 521 → 約 570 行。
- 単語分割は `Intl.Segmenter(granularity:'word')`。自前の分割器は持たない。無い環境では語差分を出さず従来表示へ落ちる。
- 語差分は共通接頭辞・接尾辞の除去のみ（LCS ではない）。行内に離れた変更が 2 箇所あると間の共通部分も含む上位集合になる。読みづらい実例が出たら LCS へ上げる、とコメントに書いてある。
- 対応付けは `pairDiffLines` 1 本。インラインと左右分割はどちらもここから引く。

## 検証

- `npx jest`: 17 suites / 658 tests 全通過。うち新規 `viewer-test/viewer-diff-words.test.ts` が 8 件。
- **修正を外すと落ちることを確認した**: `WORD_SEGMENTER` の判定を `false` に固定して再実行すると新規 8 件のうち 5 件が落ち、残りの 44 件（既存の差分表示）は通ったまま = 語強調が無い状態でも従来表示は退行しない（AC#5 の裏付けでもある）。
- `npm run lint`（--type-aware）/ `format:check` / `typecheck:viewer` / `typecheck:viewer-test` / `check:viewer-cycles` すべて通過。`markdownlint-cli2` / `check-doc-citations.sh` / `check-doc-symbols.sh` も 0 件。
- 既存テスト 2 件を、生 HTML の部分一致から textContent ベースへ直した（`&lt;script&gt;` の連続と `let b = 2` の連続を見ていたもの）。語強調で文字の間に span が入ると、意味が同じままテストだけが落ちる形だったため。守りたい内容（マークアップではなくテキストとして出る / 削除と追加が同じ行に並ぶ）は変えていない。
- **レンダリング後の見た目そのものは確認できていない。** WKWebView の `takeSnapshot` ハーネスを非対話のバックグラウンドで回したところ応答が返らず、Chrome 経由の確認も拡張が応答しなかった。代わりに (a) セレクタ `.diff-add .diff-word` / `.diff-del .diff-word` が両レイアウトの DOM に一致すること、(b) 地色変数がライト・ダークの両方で定義されていることをテストで測った。実際の配色・下線の見え方はリリース前の手動チェックに委ねる（CLAUDE.md の「WebView/GUI 層は自動テスト対象外」に沿う）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
差分表示の変更行に語単位の強調（.diff-word）を入れた。計算は JS 側（新規 viewer-src/diff-words.ts）に閉じ、Swift・ブリッジ・QuickLook には触れていない（差分 0 行）。単語分割は Intl.Segmenter に任せるので日本語の行でも語に割れ、分割器が無い環境では従来の行単位色分けへ落ちる。強調はハイライト済み行 HTML のテキスト実行部だけを包むので hljs の span を 1 つも分割せず、対応付けは pairDiffLines だけを使うのでインラインと左右分割で結果が食い違わない。行全体が強調になる行と、対にならない行には出さない。
検証: npx jest 658 件全通過（新規 viewer-diff-words.test.ts 8 件）。Intl.Segmenter を無効化して再実行すると新規 8 件中 5 件が落ち既存 44 件は通る（= 語強調が無くても従来表示は退行しない）ことを実測。lint / format / typecheck / viewer-cycles / markdownlint / doc citations・symbols もすべて 0 件。レンダリング後の見た目は自動では撮れなかったため、セレクタが両レイアウトの DOM に届くことと地色がライト・ダーク両方で定義されていることをテストで測り、配色の確認はリリース前の手動チェックに委ねた。
仕様は docs/dev/viewer-ui.md の「差分表示の見え方」に集約。起票時の前提のうち FeatureGate.isSourceDiffEnabled と style.css の記述は現存しないことを実測して Notes に残した（(gate) は付けない）。
<!-- SECTION:FINAL_SUMMARY:END -->
