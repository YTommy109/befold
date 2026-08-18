---
id: TASK-488.2
title: ダッシュボードにページ別・言語別の内訳を人間とロボットに分けて表示する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-16 01:44'
updated_date: '2026-08-16 04:35'
labels: []
milestone: m-7
dependencies:
  - TASK-496
parent_task_id: TASK-488
priority: medium
ordinal: 719000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-488 の表示側。記録は TASK-488.1 が用意する。

TASK-488.1 で `events` に入ったページ・言語の情報を、ダッシュボード（`site/src/views/dashboard.tsx`）に内訳として出す。人間とロボットの分離は既存の仕組みに合わせる。集計は `site/src/analytics.ts` の `HUMAN_ONLY`（`:146`）を使い、ボット除外条件を新しく書かない（1 箇所集約は規約テスト `site/test/analytics.test.ts:299` が担保）。表示形式は既存の「人間の訪問とロボットの巡回」セクション（`site/src/views/dashboard.tsx:350-369`）を参考にする。

既存行はページ・言語が NULL で遡及分類できないため、同ダッシュボードに既にある「遡及分類不可」の注記と同じ形で示す。

`summarize()` の発行クエリ数には上限テストがある（`site/test/query-count.test.ts:35` の `MAX_QUERIES = 13`）。指標ごとに 1 クエリ増やす作りにせず、既存の `metricBreakdown`（`site/src/analytics.ts:364-397`）のように `ROW_NUMBER() OVER (PARTITION BY ...)` でまとめる方針を検討する。SSE の差分配信（`site/src/analytics.ts:454-478`）にも新しい内訳が反映されること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 / と /features の参照数が区別して表示される
- [x] #2 ブラウザ言語設定（ja / en / other）の内訳が表示される
- [x] #3 言語の内訳に「これはブラウザの言語設定であって実際に読まれた言語ではない」ことが分かる表示（ラベルまたは注記）がある
- [x] #4 ページ別・言語別のどちらの内訳も人間とロボットに分けて表示される
- [x] #5 ボット除外条件が新規に書かれておらず、既存の HUMAN_ONLY に集約されたままである
- [x] #6 遡及分類できない既存行についての注記が表示されている
- [x] #7 summarize のクエリ数が上限テストの範囲に収まっている
- [x] #8 SSE による更新でも新しい内訳が反映される
- [x] #9 dashboard のテストが新しい内訳の描画と 0 件時の挙動を検証している
- [x] #10 最新イベント表で / と /features の visit が見分けられる（recentEvents / eventsAfter の SELECT に page が含まれている）
- [x] #11 COALESCE(page, '/') を kind='visit' と同じ条件節の外で使っていない（page が NULL の download / update_check に '/' を与えないこと）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. `visitBreakdowns` を追加。visit を page / display_lang / browser_lang の 3 列で集約し、ボットかどうかを `BOT_MATCH` で分ける **1 本のクエリ**。軸ごとの集計は TS 側で畳む（`foldSplits`）。
2. `Summary` に `visits` を追加し `summarize` の Promise.all へ組み込む。
3. `RecentEvent` に `page` を追加。`recentEvents` と `eventsAfter` の SELECT 句は `RECENT_COLUMNS` で共有する。
4. `test/query-count.test.ts` の `MAX_QUERIES` を 13 → 14 にし、内訳コメントを更新。
5. ダッシュボードに「ページ別の訪問」「言語別の訪問」の 2 セクションを追加。既存の `CountTable` / `.grid` / `.note` を再利用し CSS は足さない。見出しは `内訳` で始めない（`dashboard.test.ts` の節切り出しが前方一致のため）。
6. 最新イベント表にページ列を追加。visit 以外は空欄（'/' を補わない）。
7. テスト: analytics 側 5 件（3 軸の分離 / kind の絞り込み / 列導入前の行 / 0 件 / SELECT 句の一致）、dashboard 側 8 件（ページ別・言語別の描画、注記、未記録、最新イベントのページ列、0 件、SSE 配信 HTML）。
8. `npm run test` / `typecheck` / markdownlint、README 更新。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-488.1 からの申し送り（設計レビューで確定した論点を AC 化した）:
- 言語は Accept-Language 由来の**ブラウザ言語設定**であって表示言語ではない。LP は日英を同一 HTML に持ち localStorage の befold-lang 未設定なら常に日本語を表示するため、en 設定の初回訪問者も日本語を読んでいる（site/src/views/shared.tsx の LANG_SCRIPT）。旧 AC #2「日本語で読んでいる人と英語で読んでいる人の別」は事実と食い違うため書き換えた。
- events.page の NULL には「列の導入前の visit（LP のみ = '/' と読んでよい）」と「ページの概念が無い download / update_check」の 2 つの意味がある。COALESCE(page,'/') は kind='visit' と同じ条件節の中でしか使えない（site/schema/schema.sql の page 列コメント、site/src/analytics.ts の metricExpression）。
- 「ページアクセス」指標は page='/' に絞ってあり、/features は含まない。ページ別内訳はこの系列とは別に出すこと。
- 日次ユニーク訪問者・国別・参照元別・UA 内訳の母集団は /features を含む（ページで絞っていない）。
- recentEvents / eventsAfter は SELECT に page を持たないため、現状ダッシュボードの最新イベント表では / と /features の visit が見分けられない。

TASK-496 完了後の追記: 表示言語は `events.display_lang` から直接読める（`browser_lang` は「求めた言語」、`display_lang` は「実際に出した言語」）。AC の「ブラウザ言語設定の内訳」は両方を出す形に読み替えてよい。なお `BreakdownColumn`（site/src/analytics.ts）の union には `browser_lang` も `display_lang` も入っていないため、列を足しただけではダッシュボードに出ない。union の拡張が 488.2 の作業に含まれる。

## 実装した形

**3 つの内訳をクエリ 1 本で賄った。** ページ別・表示言語別・ブラウザ言語設定別は「visit を何かの軸で割った」ものなので、軸ごとに引かず `SELECT COALESCE(page,'/'), display_lang, browser_lang, ${BOT_MATCH}, COUNT(*) ... WHERE kind='visit' GROUP BY ...` の 1 本にまとめ、軸ごとの集計は TS 側で畳んだ（`foldSplits`）。結果は高々「2 ページ × 3 言語 × 3 言語 × 2」= 36 行にしかならない。`MAX_QUERIES` は 13 → 14（1 本だけ増）。軸ごとに引く形なら 16 本になり上限テストで落ちる。

**AC #5（ボット判定の集約）**: 人間とロボットの両方を数えるので `HUMAN_ONLY` は使えないが、`BOT_MATCH` をそのまま使う形にした（`uaSplit` と同じ）。`ua_summary LIKE 'bot:%'` のリテラルは実測で 1 箇所のまま。既存の構造ガード（analytics.test.ts）は `BOT_MATCH` を exempt に持つのでそのまま通る。

**AC #11（COALESCE の位置）**: `COALESCE(page,'/')` の出現は 2 箇所（`metricExpression` と `visitBreakdowns`）で、どちらも `kind='visit'` と同じ式・同じ WHERE の中にある。実測で確認した。`kind='visit'` を外すとテストが 2 件落ちることも確認済み。

**AC #10 で構造の穴を 1 つ塞いだ。** `recentEvents`（初期表示）と `eventsAfter`（SSE）は同じ `RecentEvent` を返す契約だが、SELECT 句が 2 箇所に手書きで重複していた。実測: `eventsAfter` からだけ `page` を落としても **typecheck も既存テスト 42 件も全部通る**（`.all<RecentEvent>()` のジェネリクスは実際の列を検査しないため）。初期表示にはあるのに SSE で流れる行にだけ列が無い、という形で静かに壊れる。SELECT 句を `RECENT_COLUMNS` に括り出して共有し、両者の戻り値のキー集合が一致することをテストで固定した。

**AC #8（SSE）**: 調査の結果、SSE は集計セクションの HTML を毎周期まるごと再送し `#summary` を innerHTML で置き換える設計だった（クライアント JS は個別イベント行を DOM に反映していない）。したがって `SummarySections` に置けば差分配信でも更新される。クライアント JS の変更は不要で、`renderSummarySections` の出力に新セクションとページ列が含まれることをテストで固定した。

## 判断

- **見出しを「内訳」で始めなかった。** `dashboard.test.ts` の節切り出しヘルパは `<h2>見出し` の前方一致で探すため、「内訳（ページ別）」にすると既存の「内訳（全期間の累計）」の切り出し先が順序に依存して変わる。「ページ別の訪問」「言語別の訪問」にした。
- **0 件の区分は表から落とす**（`splitRows`）。ページ別・言語別は取りうる値がすべて出そろうため、落とさないと「ロボット: 表示言語別」に 0 の行が並んで読めなくなる。0 件時は既存の「データなし」に倒れることをテストで固定した。
- **最新イベント表のページ列は visit 以外を空欄にする。** `COALESCE` で '/' を補うと、ダウンロードが LP の訪問に見える。
- **ページ別は「ページアクセス」指標と合計が一致しない**（指標は `page='/'` のみ）。注記で明示した。日本語 LP と英語 LP はどちらも `page='/'` で、言語は別の軸として出す。
- **CSS は 1 行も足していない。** 既存の `.block` / `.grid` / `.note` / `CountTable` の組み合わせで既存セクションと同じ見た目になる。

## 検証

- `npm test` = 11 files / 218 tests 成功（新規 13 件）
- `npm run typecheck` = エラーなし、`markdownlint-cli2` = 0 issues
- 破れたら落ちることの実測: (a) `visitBreakdowns` から `WHERE kind='visit'` を外す → 2 件失敗、(b) `RECENT_COLUMNS` から page を落とす → 2 件失敗
- 実レンダリング確認: 7 行の実データ（人間 5・ボット 1・download 1・列導入前の行 1 を含む）を入れて `renderSummarySections` の出力をダンプし、6 つの表の中身・注記・最新イベント表のページ列（download は空欄）を目視で確認した
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ダッシュボードにページ別・表示言語別・ブラウザ言語設定別の内訳を、人間とロボットに分けて追加した。最新イベント表にもページ列を足した。

3 つの内訳は「visit を何かの軸で割った」ものなので、軸ごとにクエリを引かず 1 本にまとめた（visit の行を 3 列の組で集約すると高々数十行にしかならず、軸ごとの集計は TS 側で畳める）。summarize のクエリは 13 → 14 本で、軸ごとに引く形なら 16 本になり上限テストで落ちる。ボット判定は BOT_MATCH をそのまま使い、判定リテラルは 1 箇所のまま（構造ガードが検査）。COALESCE(page,'/') の 2 箇所はどちらも kind='visit' と同じ式の中にある。

AC #10 の対応で構造の穴を 1 つ塞いだ。recentEvents（初期表示）と eventsAfter（SSE）は同じ RecentEvent を返す契約なのに SELECT 句が 2 箇所に手書きで重複しており、実測で「eventsAfter からだけ page を落としても typecheck も既存テスト 42 件も全部通る」ことを確認した。SELECT 句を RECENT_COLUMNS に括り出して共有し、両者の戻り値のキー集合が一致することをテストで固定した。

SSE は集計セクションの HTML を毎周期まるごと再送して #summary を置き換える設計だったため、SummarySections に置くだけで差分配信にも反映される。クライアント JS の変更は不要。CSS も 1 行も足していない（既存の .block / .grid / .note / CountTable の組み合わせ）。

検証: npm test 218 件成功（新規 13 件）/ typecheck エラーなし / markdownlint 0 issues。破れたら落ちること（WHERE kind='visit' を外す → 2 件、RECENT_COLUMNS から page を落とす → 2 件）を実測し、7 行の実データを入れて描画結果もダンプして目視確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
