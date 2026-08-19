---
id: TASK-528
title: 差分表示で変更行の単語単位の差分も見せる
status: To Do
assignee: []
created_date: '2026-08-19 07:14'
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
- [ ] #1 変更行のうち実際に変わった語だけが、行全体の色とは区別できる強調で表示される
- [ ] #2 inline レイアウトと side-by-side レイアウトの両方で単語単位の差分が表示される
- [ ] #3 日本語（空白で区切られない文）の行でも単語単位の差分が機能する
- [ ] #4 構文ハイライトの表示が単語強調によって崩れない
- [ ] #5 単語単位の差分が出せない・出さないと判断した行は、従来どおり行全体の色分けで表示され退行しない
- [ ] #6 計算場所（Swift / JS）の選択と、その理由が Implementation Notes に記録されている
- [ ] #7 style.css:693-695 の「語単位の差分は出していない」前提に依存した既存の記述・挙動が更新されている
<!-- AC:END -->
