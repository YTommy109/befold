---
id: TASK-488.1
title: ページと閲覧言語を events に記録できるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-16 01:44'
updated_date: '2026-08-16 03:51'
labels: []
milestone: m-7
dependencies: []
parent_task_id: TASK-488
priority: medium
ordinal: 718000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-488 の記録側。ダッシュボードの表示は TASK-488.2 で扱う。

`events` テーブルにページと言語の情報を持たせ、`/features` を計上する。現状は `/` のみが `visit` として記録され（`site/src/routes/public.tsx:19`）、`/features` は「ページを区別する列が無く LP 指標に混ざるため」意図的に記録していない（同 `:23-34` のコメント）。言語はサーバ側で一切見ておらず、出し分けは `localStorage` の `befold-lang` を読むクライアント JS のみ（`site/src/views/shared.tsx:30-49`）。

このサブタスクで、親タスクに挙げた 2 つの論点（言語をどう判定するか、ページをどう持つか）を確定させる。判定方式を選んだ理由と、その指標が何を意味するか（例: Accept-Language はブラウザ設定であって実際に読んだ言語ではない）を Implementation Notes に残すこと。

ロボット判定は既存の `ua_summary` の `bot:` 接頭辞をそのまま使い、新しい判定を作らない（`site/src/lib/visitor.ts:104-123`、集約点は `site/src/analytics.ts:133,146`）。

スキーマ変更は Atlas 運用に従う（`site/schema/schema.sql` を更新 → `npm run migrate:diff` → `migrate:lint` → `migrate:local`。手順は `site/README.md:59-73`）。テーブル再構築を伴う差分は `scripts/check-destructive-migrations.sh` が検出するため `ADD COLUMN` で足す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 /features へのアクセスが events に記録され、/ の visit と区別できる
- [x] #2 閲覧言語の情報が events に記録される
- [x] #3 採用した言語判定方式と、その指標が何を意味するかが Implementation Notes に記録されている
- [x] #4 マイグレーションが Atlas 運用（schema.sql 更新 → diff → lint）で生成され、テーブル再構築を含まない
- [x] #5 記録処理のユニットテストがあり、ボット判定は既存の ua_summary の仕組みを流用している
- [x] #6 site の vitest と typecheck が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. schema/schema.sql に events.page / events.lang を ADD COLUMN で追加（どちらも NULL 許容）。npm run migrate:diff -> migrate:lint -> migrate:local。
2. src/schema.ts: pageSchema（'/' | '/features' の enum）と langSchema（'ja' | 'en' | 'other'）を足し、eventSchema に page / lang を追加。
3. src/lib/lang.ts（新規）: summarizeLang(acceptLanguage) を実装。Accept-Language の先頭タグを見て ja / en / other に丸め、ヘッダが無ければ null。
4. src/events.ts: EventAttributes に page を追加（source と同じく呼び出し側が明示。URL から導出すると /dl/:tag/:file でカーディナリティが発散するため）。lang は Accept-Language からリクエスト共通で導出。INSERT 文へ 2 列追加。
5. src/routes/public.tsx: / は page:'/' を付ける。/features は recordEvent(kind:'visit', page:'/features') を追加し、Cache-Control: max-age=3600 を外す（エッジ/ブラウザキャッシュに載ると Worker が動かず計上できないため）。コメントも書き換える。
6. src/analytics.ts: METRIC_FILTERS の visit に page 条件を足し、既存の 'ページアクセス' 系列は COALESCE(page,'/')='/' のまま（LP 新規獲得の意味と過去データの連続性を保つ）。ページ別内訳は TASK-488.2。
7. テスト: test/lang.test.ts（言語判定）、public.test.ts の /features のテストを「visit として記録し page='/features' を持つ」へ書き換え、events の page/lang 記録を検証。schema.test.ts も追随。
8. npm run test / typecheck。Implementation Notes に言語判定方式の選定理由と指標の意味を記録。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 採用した言語判定方式と、その指標が意味するもの

**方式**: `Accept-Language` の第一タグを `ja` / `en` / `other` に丸めて `events.browser_lang` に記録する（`site/src/lib/lang.ts` の `summarizeLang`）。q 値による並べ替えはしない（ブラウザは第一希望を先頭に置いて送るため）。地域差（en-US / en-GB）は畳む。LP は日英しか出し分けないので、区別しても読み手に何も伝わらず内訳のカーディナリティが増えるだけ。

**この指標が意味するもの**: **ブラウザの言語設定であって、実際に読まれた言語ではない。** LP は日英の本文を同一 HTML に持ち、表示言語は `localStorage` の `befold-lang` だけで決まる。未設定なら常に日本語を表示する（`site/src/views/shared.tsx` の LANG_SCRIPT: `if (saved && saved !== 'ja') switchLang(saved)`）。したがって Accept-Language が en の初回訪問者も、画面では日本語を読んでいる。この値が答えるのは「英語を求めて来た人がどれだけ居るか」であって「英語で読んだ人の数」ではない。

**他方式を採らなかった理由**:
- クライアント JS が cookie に `befold-lang` を書いてサーバが読む方式 → 実際の表示言語は測れるが、**初回訪問では必ず欠測する**（cookie がまだ無い）。欠測の意味づけと Cookie 同意の検討が要る割に、初回訪問こそ知りたい層なので費用対効果が合わない。
- 言語ごとに URL を分ける方式 → 表示言語を確実に測れて SEO 上も正しいが、canonical / og:url / sitemap / hreflang / 旧ホストからの 301（ADR 0007）へ全面的に波及する。計測の副産物として決めるべき話ではないので **TASK-496 として切り出した**。

Sparkle など Accept-Language を送らないクライアントでは NULL。言語の内訳は `kind='visit'` で絞ること（全 kind 横断だと update_check の NULL が支配する）。

## ページの持ち方

`events.page` は生パスではなく計上対象ページの列挙（`pageSchema` = `'/' | '/features'`）で、ルート側が明示して渡す（`source` と同じ持ち方）。URL から導出しない——`/dl/:tag/:file` のようにパラメータを含む経路があり、導出にすると内訳のカーディナリティが発散する。

NULL の意味は 2 つある: (a) 列の導入前に記録された visit（当時計上していたのは LP だけなので '/' と読んでよい）、(b) ページの概念が無い download / update_check。このため `COALESCE(page, '/')` は `kind='visit'` と同じ条件節の中でしか使えない。構造で担保した——page 条件は `metricExpression` が kind 条件と一緒にしか組み立てず、page 条件だけを書く形にはならない。

## 設計レビュー（/review-design）で方針を変えた点

着手前に 1 回回し、次を Plan から変更した。

1. **指標述語の一元化**（最優先の指摘）。当初案は `METRIC_FILTERS` に page を足すだけだったが、件数用の `KIND_COUNT_COLUMNS` が `SUM(kind = 'visit')` を手書きで持っており、そこだけ同期漏れを起こす形だった。放置すると累計・当日・日次・時間帯の 4 系列で /features が「ページアクセス」に混入し、さらに `perKind` の総数（cumulative 由来）と内訳（METRIC_EXPR 由来）が食い違う。述語を作る `metricExpression` を 1 つ立て、`METRIC_EXPR` / `metricCondition` / `KIND_COUNT_COLUMNS` の 3 者が共有する形へ畳んだ。
2. **破れたら落ちるテストを同じタスクで用意した**（`test/analytics.test.ts` の「ページの分離」）。/features の visit を入れて累計・当日・日次・時間帯・perKind の全系列が増えないことを固定する。`METRIC_FILTERS.visit.page` を null に戻すと 2 件落ちることを実測で確認済み。
3. **Cache-Control は削除でなく `no-store` を明示**。ヘッダを外すだけでは Cache-Control も Expires も無い 200 応答がブラウザのヒューリスティックキャッシュに載り得て、計上できるかが環境依存になる。
4. **命名を「閲覧言語」から「ブラウザ言語設定」へ**。列名も `lang` ではなく `browser_lang` にして、読み違えようがない形にした。

## 判断を確定させて記録するもの（コードは変えていない）

- **日次ユニーク訪問者（`COUNT(DISTINCT visitor_token)`）にページ条件は足さない。** 「何人来たか」を測るものなので、LP に絞ると /features へ直接来た訪問者が数から消える。= サイト全体のユニーク訪問者。テストで固定した。
- **国別・参照元別・UA 内訳（human/bot 比）の母集団は /features を含むようになる。** 現状も全 kind 対象で一貫しているため、明示的に「含める」と決めた。/features は sitemap 掲載でクローラが来るので、bot 比は上振れする。
- **D1 書き込み枠**: 実測で直近 24 時間のイベントは 61 件（うち visit 51 件）。/features の計上で概ね倍になっても無料枠（10 万/日）に対して桁が違う。`scripts/analytics-query.sh` で計測。

## 検証

- `npm test` = 11 files / 193 tests すべて成功（新規 12 件: lang.test.ts 5、public.test.ts 4、analytics.test.ts 3、schema.test.ts 1 に相当）
- `npm run typecheck` = エラーなし
- `npm run migrate:lint` = no diagnostics、`scripts/check-destructive-migrations.sh` = 破壊的な文なし（ADD COLUMN 2 本のみ、テーブル再構築なし）
- `npm run migrate:local` = 適用成功。本番・staging への適用は `.github/workflows/site.yml:128` / `site-migrate.yml:100` が deploy 時に行う
- 修正を戻すと落ちることを確認: `METRIC_FILTERS.visit.page` を null に戻す → analytics.test.ts が 2 件失敗。/features の `recordEvent` を消す → public.test.ts が 1 件失敗
- `markdownlint-cli2` = 0 issues

検証の最終確認: npm test = 11 files / 194 tests 成功（schema.test.ts に page 列挙の検査を追加した分で 193 → 194）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
events に page / browser_lang の 2 列を足し、/features を LP と区別できる visit として計上できるようにした。

記録側: ページは生パスでなく列挙（pageSchema）でルートが明示して渡す（URL 由来だと /dl/:tag/:file でカーディナリティが発散するため）。言語は Accept-Language の第一タグを ja/en/other に丸める。これはブラウザの言語設定であって表示言語ではない（LP は localStorage 未設定なら常に日本語）ため、列名・doc・README すべてを「ブラウザ言語設定」で統一し、実際の表示言語を測る案は TASK-496 へ切り出した。

集計側: 設計レビューで、件数用の KIND_COUNT_COLUMNS だけが指標述語を手書きで持っており page 条件の同期漏れを起こす形だと判明したため、述語を作る metricExpression を 1 つ立てて METRIC_EXPR / metricCondition / KIND_COUNT_COLUMNS の 3 者で共有する形へ畳んだ。「ページアクセス」指標は page='/' のままで、/features の計上で LP 新規獲得の系列は薄まらない。日次ユニーク訪問者はページで絞らない（サイト全体の訪問者数）ことを決めてテストで固定した。

/features は Cache-Control を no-store にした（キャッシュに載ると Worker を通らず計上できない。ヘッダを外すだけではヒューリスティックキャッシュに載り得る）。

検証: npm test 193 件成功 / typecheck エラーなし / migrate:lint no diagnostics + 破壊的変更なし（ADD COLUMN 2 本）/ migrate:local 適用成功 / markdownlint 0 issues。修正を戻すと新規テストが落ちること（METRIC_FILTERS の page を null に戻して 2 件、/features の recordEvent を消して 1 件）も実測で確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
