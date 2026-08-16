---
id: TASK-488
title: アクセス統計でページ別・閲覧言語別の内訳を人間とロボットに分けて見られるようにする
status: Done
assignee: []
created_date: '2026-08-16 01:43'
updated_date: '2026-08-16 05:14'
labels: []
milestone: m-7
dependencies: []
priority: medium
ordinal: 717000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ダッシュボードで「日本語で読んでいる人と英語で読んでいる人の別」と「/features の参照数」を、それぞれロボットと人間に分けて把握できるようにする。

## 現状（実測）

**ページの区別が無い。** `events` テーブルにパス／URL の列は存在せず（desired state は `site/schema/schema.sql:5-26`。列は id / timestamp / kind / version / channel / country / os / ua_summary / visitor_token / referrer / as_org / source）、記録は各ルートハンドラが `recordEvent` を明示的に呼ぶ方式（`site/src/events.ts:28`）。`visit` として計上されるのは `/` のみ（`site/src/routes/public.tsx:19`）。

`/features` は**意図的に記録していない**。`site/src/routes/public.tsx:23-34` のコメントに「visit として記録しない。events テーブルはページを区別する列を持たないため、ここを計上すると LP からの新規獲得を測る指標に別ページの訪問が混ざる」とある。つまり単に計上を足すのではなく、既存の LP 指標を汚さない形にする必要がある。

**閲覧言語を記録していない。** サーバ側で `Accept-Language` を読む箇所は無く、`events` に言語列も無い。言語の出し分けは完全にクライアント側で、`site/src/views/shared.tsx:30-49` の `LANG_SCRIPT` が `localStorage` の `befold-lang` を見て `[lang]` 要素の `hidden` を切り替える。SSR は常に `<html lang="ja">` を出し、日英両方のマークアップを含める。**既定は常に日本語**で、英語話者が来ても切り替えなければ日本語のまま。

**ロボット判定は既にある。** UA からボットを判定し、`ua_summary` に `bot:` 接頭辞付きで保存する（`site/src/lib/visitor.ts:104-123`、既知 28 トークン + 一般パターン）。集計側は接頭辞だけで分離し（`site/src/analytics.ts:133` の `BOT_MATCH`）、`HUMAN_ONLY`（`site/src/analytics.ts:146`）が全集計の WHERE に付く。ダッシュボードには既に「人間の訪問とロボットの巡回」セクションがある（`site/src/views/dashboard.tsx:350-369`）。ボット除外条件が 1 箇所に集約されていることは規約テスト `site/test/analytics.test.ts:299` が担保している。**この仕組みは作り直さず、そのまま使う。**

## 決めるべきこと

- **言語をどう判定するか。** (a) `Accept-Language` ヘッダをサーバ側で記録する（JS 不要・ボットにも付くが、ブラウザ設定であって実際に読んだ言語ではない）、(b) `localStorage` の切替結果を記録する（実際に読んだ言語だが JS 必須で、既定 ja の利用者は切り替えないため「日本語を選んだ人」と「切り替えていない人」が区別できない）、(c) 両方を別の列／別イベントとして持つ。この選択は指標の意味そのものを決めるため、実装前に確定させる。
- **ページをどう持つか。** 列を足して既存クエリを `/` 限定にするか、`kind` を分けるか。いずれにせよ既存の LP 指標（累計・当日・日別・時間帯・バージョン別など）の意味を変えないこと。

## 注意

- 既存行はページ・言語が NULL のままになり遡及分類できない。ダッシュボードには既に同種の注記（`site/src/views/dashboard.tsx` の「遡及分類不可」）があるので、同じ形で示す。
- スキーマ変更は Atlas 運用に従う（desired state を `site/schema/schema.sql` で更新 → `npm run migrate:diff` → `migrate:lint` → local → remote。詳細は `site/README.md:59-73`）。列の改名・再構築は `scripts/check-destructive-migrations.sh` に引っかかるため、追加は `ADD COLUMN` で行う。
- `summarize()` の発行クエリ数には上限テストがある（`site/test/query-count.test.ts:35` の `MAX_QUERIES = 13`）。指標を足す際はクエリ数を線形に増やさない。
- 状態と列を新設する変更のため、各サブタスクで実装着手前に `/review-design` を 1 回回す（`.claude/CLAUDE.md`「実装着手前の設計レビュー」）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 /features の参照数が、/ の参照数と区別してダッシュボードで見られる
- [x] #2 閲覧言語（日本語 / 英語）の別がダッシュボードで見られる
- [x] #3 ページ別・言語別のどちらの内訳も、人間とロボットを分けて表示される
- [x] #4 既存の LP 指標（累計・当日・日別・時間帯・バージョン別など）の意味と数値が、/features の計上によって変わらない
- [x] #5 遡及分類できない既存行の扱いがダッシュボード上で注記されている
- [x] #6 site の vitest と typecheck が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 親タスクの完了処理（2026-08-16）

実装はサブタスク 488.1 / 488.2 / 488.3 が担い、親タスク自体のコード変更は無い。親の受け入れ条件をコードと実行結果で検証して締めた。

### 受け入れ条件の裏付け

- **#1 / #3（ページ別・人間/ロボット別）**: `site/src/views/dashboard.tsx:411-423` の「ページ別の訪問」セクションが `splitRows(summary.visits.byPage, false/true)` で人間・ロボットの 2 表を並べる。
- **#2 / #3（言語別・人間/ロボット別）**: 同 `:425-453` の「言語別の訪問」セクション。表示言語（URL が決める）とブラウザ言語設定（Accept-Language 由来）を別軸で持ち、それぞれ人間・ロボットに分ける計 4 表。
- **#4（既存 LP 指標が変わらない）**: `site/src/analytics.ts:51` で `visit: { kind: 'visit', source: null, page: '/' }`。`/features` を visit として記録し始めても「ページアクセス」系列は LP 限定のまま。同 `:81-86` の doc コメントが `COALESCE(page,'/')` を `kind='visit'` と同じ式の中にしか置かない理由（page NULL には「列導入前の LP visit」と「ページの概念が無い download / update_check」の 2 種があり、後者に '/' を与えると嘘になる）を明示している。
- **#5（遡及分類不可の注記）**: `dashboard.tsx:413-418`（ページ列導入前は LP のみ計上だったため '/' に数える）、`:427-437`（言語別 URL 導入前は表示言語が確定せず「未記録」）、`:459-465`（ホスト列導入前は復元不可）、`:492-499`（ボット分類適用日より前は遡及分類不可）。
- **#6（vitest / typecheck）**: 実測。`npm run typecheck` は `tsc --noEmit` が無出力で通過。`npm test` は **11 ファイル / 236 テストすべて通過**（Duration 3.17s）。

### 現在仕様への反映

`docs/dev/native-app-design.md` の更新は不要。同文書は macOS アプリ（BefoldApp/）の構成を扱うもので、本タスクの変更は配布サイト（`site/`、Cloudflare Worker）に閉じている。サイト側の仕様は実装コミット 50dd6674 で `site/README.md` と `docs/adr/0007-distribution-site-custom-domain.md` に反映済み。

### 申し送り

言語別内訳のうち「ブラウザ言語設定」は Accept-Language 由来でボットにも付く。TASK-490（ボット判別の精度見直し）でデータセンター由来の自動アクセスの分類が変わると、この表の人間側の数も動く。490 の完了後に数値の見え方を確認すること。

### #4 の但し書き（検証で判明）

`METRIC_FILTERS.visit` の `page: '/'` は `metricExpression`（`site/src/analytics.ts:80-84`）を唯一の定義元として、`METRIC_EXPR`（`:94`）・`KIND_COUNT_COLUMNS`（`:166`）・`metricCondition`（`:262`）の 3 経路すべてに同じ `COALESCE(page,'/') = '/'` が入る。よって受け入れ条件が列挙する累計・当日・日別・時間帯・バージョン別はすべて LP 限定のまま保たれている。

ただし **国別・参照元別の内訳（`breakdown(db,'country')` / `'referrer'`）は metric 指定なしで全 kind が対象**のため、元々 LP 限定ではなく、`/features` の計上ぶんだけ数値が増える。受け入れ条件が挙げた指標には含まれないので #4 は満たすが、「visit の内訳表はすべて LP 限定」と誤読しないこと。

意図的な例外がもう 1 つある。日次ユニーク訪問者の `COUNT(DISTINCT visitor_token)` はページで絞らない（サイト全体の訪問者数を意味するため）。これは `site/test/analytics.test.ts:444`「日次ユニーク訪問者はページで絞らない（サイト全体の訪問者数）」が意図として固定している。

### 内訳を担保しているテスト

- `site/test/analytics.test.ts`: describe「ページの分離」(:409) 3 件、describe「visit の内訳（ページ別・言語別）」(:457) 4 件、ホスト別の人間/ロボット分離 (:570)
- `site/test/dashboard.test.ts`: ページ別の人間/ロボット描画 (:256)、表示言語とブラウザ言語設定の別表 (:294)、注記の検証 (:323, :339, :372, :381)、0 件時「データなし」(:436)、SSE 再配信に内訳が含まれる (:651)
- `site/test/public.test.ts`: `page=/features` の visit 記録 (:614)、表示言語の記録 (:876)
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サブタスク 488.1（events への page / display_lang / browser_lang 記録）・488.2（ダッシュボードのページ別・言語別内訳）・488.3（リクエスト先ホストと旧経路）で実装済み。親タスクとしては受け入れ条件 6 件を検証して締めた。ページ別・言語別のいずれも人間とロボットを別表に分けて表示され（dashboard.tsx:411-454）、既存の LP 指標は METRIC_FILTERS.visit の page:'/' により LP 限定のまま保たれている（analytics.ts:52, 80-86）。遡及分類できない既存行は 4 箇所の注記で示している。検証は npm run typecheck（tsc --noEmit 無出力）と npm test（11 ファイル / 236 テスト全通過）の実測、および analytics/dashboard/public のテスト計 20 件超が内訳の描画・分離・0 件時の挙動を担保していることの確認による。
<!-- SECTION:FINAL_SUMMARY:END -->
