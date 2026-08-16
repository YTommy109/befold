---
id: TASK-488.3
title: リクエスト先ホストと旧経路へのアクセスを記録・表示する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-16 02:07'
updated_date: '2026-08-16 05:02'
labels: []
milestone: m-7
dependencies:
  - TASK-488.1
parent_task_id: TASK-488
priority: medium
ordinal: 725000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-488 の計測範囲のうち、配布 URL の一本化（TASK-489 / m-8）が判断材料として必要とするもの。もとは TASK-489.2 として起票したが、計測基盤の変更は 488 側に集約する（TASK-489.2 はアーカイブ済み）。

## なぜ必要か

配布サイトは 3 世代の URL すべてで応答している（GitHub Pages / `befold.tommy109.workers.dev` / `befold.degino.com`。2026-08-16 実測で全て稼働中）。旧世代を止めてよいかは「旧ホストを叩くクライアントがゼロか」で決まるが、`events` テーブルにはリクエスト先ホストの列が無いため（`site/schema/schema.sql:5-26`）、**今は数えられない**。ADR 0007 は停止条件をこの観測に置いているので（`docs/adr/0007-distribution-site-custom-domain.md:117-118`）、観測できないままでは条件を永久に判定できない。

## 記録したいもの

1. **リクエスト先ホスト**（旧ホスト `befold.tommy109.workers.dev` / 正規ホスト / staging）。`update_check` は既に記録されている（`site/src/routes/public.tsx:146`）ので、ホストの次元を足せば旧ホスト分を分離できる
2. **R2 ミスによる GitHub フォールバックの発生**。`site/src/routes/public.tsx:73-76` の 302（`/dl/`）、`site/src/lib/github.ts:10-12` の appcast プロキシ、`/download` の GitHub API 経路。ここが 0 でないうちは GitHub 側を止められない

## 既に取れているもの（作り直さないこと）

**GitHub Pages からの流入は既に記録されている。** `docs/index.html` は `?ref=gh-pages` を付けて遷移し、`resolveReferrer`（`site/src/lib/referrer.ts`）は `?ref=` を最優先で採用する。その doc コメントには「GitHub Pages は静的ホスティングのためサーバーサイドリダイレクトができず meta refresh / JS になり Referer は取りこぼしが出る。明示パラメータなら影響を受けずに数えられる」とあり、**gh-pages の計測がこの仕組みの動機**。参照元別の内訳もダッシュボードに既にある（`site/src/analytics.ts:424` の `breakdown(db, referrer)`）。

足りないのは人間とロボットの分離だけで、これは TASK-488.2 の対象。したがってこのサブタスクで `?ref=gh-pages` の記録を作り直す必要はない。

## 観測できないもの

GitHub 直の appcast（`https://github.com/YTommy109/befold/releases/download/appcast/appcast.xml`）を見ている v1.10.0 以前のクライアントは、サイトを経由しないため Worker では観測できない。GitHub のリリースアセットのダウンロード数 API など別手段の可否を調べ、結果を記録する。

## 制約

- スキーマ変更は TASK-488.1 と重複させない（同じマイグレーションにまとめるか後続で足すかを判断する）
- ボット判定は既存の `ua_summary` の `bot:` 接頭辞を流用する（`site/src/lib/visitor.ts:104-123`）
- `summarize()` のクエリ数上限テスト（`site/test/query-count.test.ts:35`）に触れないこと
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 リクエスト先ホスト（旧ホスト / 正規ホスト）が events に記録される
- [x] #2 旧ホストへのアクセス数が人間とロボットに分けてダッシュボードで確認できる
- [x] #3 R2 ミスによる GitHub フォールバックの発生が観測できる
- [x] #4 GitHub 直 appcast を見ているクライアントの観測可否と方法が調査結果として記録されている
- [x] #5 ?ref=gh-pages の既存の記録経路を作り直していない
- [x] #6 TASK-488.1 のスキーマ変更と列設計が重複していない
- [x] #7 site の vitest と typecheck が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. スキーマ: events に列を 2 本足す（1 マイグレーション）。
   - host TEXT: リクエスト先ホスト。全 kind で記録する。値は `lib/hosts.ts` の既知
     ホスト名そのもの（befold.degino.com / befold.tommy109.workers.dev / staging 2 本）
     か、それ以外は 'other'。ホスト名リテラルを増やさない（ADR 0007 決定 6）。
   - fallback TEXT: GitHub へ落ちた経路。'appcast' / 'dmg' / 'release-api'。
     kind='github_fallback' のときだけ値を持つ。
2. kind を 2 つ足す（schema.ts の eventKindSchema）。
   - 'github_fallback': R2 ミスで GitHub へ落ちた事実。serveDMG の 302、loadAppcast の
     プロキシ、/download の GitHub API 経路の 3 箇所で記録する。
   - 'legacy_redirect': 旧ホストの HTML ページを 301 した事実（index.ts のミドルウェア）。
     visit として記録すると、301 を追った先の canonical 側 visit と二重計上になる。
   - MetricKey = EventKind | 'update_download' なので METRIC_FILTERS に 2 件が
     型で強制される。ただし KIND_LABELS（カード・グラフの系列）には足さない——
     系列色は 5 スロットしかなく、この 2 つは製品指標ではなく運用観測だから。
     KIND_LABELS ∪ OPERATIONAL_KINDS が全 MetricKey を覆うことをテストで担保する。
3. 記録: host は recordEvent（events.ts）で URL から一括導出する。経路ごとの配線に
   しない（付け忘れが黙って欠測になる）。fallback は呼び出し側が明示する。
4. 集計: クエリを増やさない（query-count.test.ts の上限 14 に触れない）。
   visitBreakdowns を全 kind に広げ、GROUP BY を host / kind / page / display_lang /
   browser_lang / fallback / is_bot にする 1 本へ畳む。行数は列挙の組でしか増えず
   高々数百行。軸ごとの集計は TS 側（foldSplits）で畳む。byPage / byDisplayLang /
   byBrowserLang は kind='visit' の行だけを畳む（従来と同じ意味を保つ）。
   byHost / byFallback を足す。
5. 表示: ダッシュボードに「配布ホストと旧経路（全期間の累計）」セクションを足す。
   ホスト別（人間 / ロボット）・旧ホストからの 301・GitHub フォールバックの内訳。
   appcast のフォールバックは caches.default（300 秒）に載ると Worker を通らず
   過小になることを注記する。
6. 調査（AC#4）: GitHub 直の appcast を見ているクライアントの観測可否。
   実測済み: releases API のアセットに download_count がある
   （appcast.xml / appcast-develop.xml とも現在 0）。ただしアセットを差し替えると
   カウンタが 0 に戻るため、appcast を更新するたびにリセットされる。結論と
   採否を Notes と site/README.md に記録する。
7. テスト: analytics（新軸 3 つ）・dashboard（新セクション）・public（3 箇所の
   フォールバック記録）・index（301 の記録）・schema（新 kind / 新列）。
   vitest と typecheck を通す。

## /review-design の結果（実装前）

前提と裏付けを併記する。裏付けの種類は 実測 / コード参照 / ドキュメント参照。

- **F1（項目 2: 既存の不変条件との衝突）**: 1 本に畳むクエリを全 kind へ広げると
  `COALESCE(page, '/')` が `kind = 'visit'` の外へ出る。これは
  `schema/schema.sql` の page 列コメントと `analytics.ts` の `metricExpression` が
  明示的に禁じている形で、download / update_check の行が LP 訪問として
  ラベル付けされる（ドキュメント参照 + コード参照）。
  → SQL では raw な `page` を返し、'/' への丸めは TS 側で `kind = 'visit'` の行だけに
  適用する。判定の同居関係は保ったまま置き場所だけを移す。
- **F2（項目 9: 決めたことを守らせるもの）**: 3 つとも「破れたら落ちる」形にする。
  - host は `EventAttributes` に持たせない（呼び出し側から渡せない = 構造で強制）
  - host の値は zod enum（`lib/hosts.ts` 由来）にし、分類外の文字列は parse で落とす
  - `fallback` は「kind='github_fallback' のときだけ非 NULL」を zod の refine で強制
  - 新しい kind が KIND_LABELS にも運用セクションにも載らずに消えないよう、
    「全 MetricKey が KIND_LABELS ∪ OPERATIONAL_KINDS に含まれる」テストを置く
- **F3（項目 7: 測るものと守るものの一致）**: ADR 0007:101-102 の停止条件は
  「旧ホストの **appcast** を叩くクライアントがゼロ」（ドキュメント参照）。本命は
  update_check × host であり、301 の記録は人間側を見るための補助。
  記録されないギャップが 2 つ残る（注記する）: 旧ホストの静的アセット
  （`index.ts` の notFound → ASSETS.fetch）と `/healthz`。
- **F4（項目 5: 順序）**: appcast のフォールバックは `caches.default`（300 秒）に
  当たった周期では `loadAppcast` 自体が走らないため過小になる（コード参照:
  `public.tsx` の proxyAppcast）。update_check はキャッシュ判定より前に記録して
  いるので影響を受けない。ダッシュボードに注記する。
- **F5（項目 3: 消費経路の全列挙）**: GitHub へ落ちる経路は 3 つで全部
  （実測: `rg 'RELEASES_LATEST_URL|releaseAssetURL|APPCAST_UPSTREAM|latestDMG'` の
  src 側ヒットは public.tsx の 61 / 63 / 92 / 208 行のみ）。最新イベント表への
  host 列追加は AC 外なので行わない（必要になったら `RECENT_COLUMNS` の 1 箇所）。
- **F6（項目 6: 高頻度経路のコスト）**: GROUP BY の対象が visit 行から全行へ広がる。
  `summarize()` は SSE の周期のうち**新着があった周期でだけ**再実行される
  （コード参照: `routes/dashboard.tsx` の `if (arrived)`）。累計系は元から全表
  スキャンであり、現行のデータ量では許容する。
- **F7（項目 4: 新しい状態に対応する表示）**: ホスト別は 0 件の行を落とさない。
  「旧ホストが 0 件であること」自体が停止条件の材料であり、0 行を落とす既存の
  `splitRows` を使うと「まだ 0」と「そもそも計測していない」が画面上で区別できなく
  なる。既知ホストは常に行として出す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（TASK-488.3）

### スキーマ

`events` に 2 列（マイグレーション `20260816..._add_host_and_fallback.sql`、いずれも
ADD COLUMN なので CI が自動適用する）。

- `host`: 応答したホスト。全 kind で値を持つ。`recordEvent` がリクエスト URL から
  一括導出し、`EventAttributes` には持たせていない（呼び出し側から渡せない = 付け忘れが
  起きない構造）。値は `lib/hosts.ts` の既知ホスト名か 'other'（`classifyHost`）。
- `fallback`: R2 ミスで GitHub へ落ちた経路（'appcast' / 'dmg' / 'release-api'）。
  `kind='github_fallback'` のときだけ非 NULL であることを `eventSchema` の refine が強制。

### kind を 2 つ追加

`github_fallback`（3 経路すべてで記録）と `legacy_redirect`（旧ホストの 301）。
後者を visit にしないのは、301 を追った先の正規ホストでも visit が記録され二重に
数えられるため。どちらも製品指標ではないので `KIND_LABELS`（カード・グラフ）ではなく
`OPERATIONAL_KINDS` に入れ、専用セクションで見る。「全 kind がどちらかに含まれる」ことを
テストで担保した（記録だけされて画面に出ない状態を作らせない）。

### クエリ本数は 14 のまま

`visitBreakdowns` を `eventBreakdowns` に広げ、GROUP BY に host / kind / fallback を
足して全 kind を 1 本で集約する形にした。これに伴い `COALESCE(page,'/')` を SQL から
外し、'/' への丸めは TS 側で kind='visit' の行だけに適用している（SQL に残すと
download / update_check が LP 訪問としてラベル付けされる）。

### AC#4 の調査結果: GitHub 直 appcast の観測

Releases API がアセットごとの `download_count` を返すため**観測手段はある**
（実測 2026-08-16: `curl .../releases/tags/appcast` で appcast.xml / appcast-develop.xml
とも 0）。ただし**アセットを差し替えるとカウンタがゼロに戻る**。appcast はリリースの
たびに上書きするので「前回のリリース以降の取得数」しか表さず、上の 0 も 2026-08-15 に
差し替えた直後であることによる。累計として使うには差し替え前にスナップショットを取る
手順をリリースワークフローへ足す必要がある。**現時点では採らない**——このクライアントは
自動アップデートで新しいバージョンへ移れば Worker 側の update_check に現れるため、
ホスト別の推移で間接的に追える。結論は `site/README.md` に記録した。

### 観測できないまま残るギャップ（意図的）

- 旧ホストの静的アセット（notFound → ASSETS.fetch）と `/healthz`
- appcast のフォールバックは `caches.default`（300 秒）に当たった周期を数えられず過小。
  `update_check` 自体はキャッシュ判定より前に記録するので影響なし。両方とも画面に注記した。

### 検証

- `npx vitest run`: 236 passed（新規 15 件を含む）
- `npm run typecheck`: エラーなし
- `markdownlint-cli2`: 0 issues
- 新しいガードが「直す前は落ちる」ことを実測で確認した。visit 限定のフィルタ除去 /
  0 件ホストの行保持を除去 / 301 の記録を除去 の 3 つを一時的に戻したところ、
  対応する 6 件がすべて失敗した（通してから戻した）。
- ダッシュボードの新セクションを実レンダリングでダンプし、既知 4 ホスト + other が
  0 の行を含めて並ぶこと、フォールバックが経路別に出ることを目視で確認した。

### やらなかったこと

- 最新イベント表への host 列の追加（AC 外。必要になれば `RECENT_COLUMNS` の 1 箇所）
- `tools/seed-local.mjs` への新列の追加（page / browser_lang も入れていないため揃えた）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
events に host（応答したホスト）と fallback（GitHub へ落ちた経路）を足し、旧ホストへのアクセスと R2 ミスをダッシュボードで人間とロボットに分けて見られるようにした（ADR 0007 の停止条件の判断材料）。旧ホストの HTML ページは 301 するため visit にならないので legacy_redirect として別に数える。集計クエリは 1 本の GROUP BY へ列を足す形にして 14 本のまま。GitHub 直 appcast は Releases API の download_count で観測できるがアセット差し替えでゼロに戻るため採らない、と結論を記録した。vitest 236 passed / typecheck エラーなし / markdownlint 0 issues、新ガードは修正を戻すと 6 件落ちることを実測。
<!-- SECTION:FINAL_SUMMARY:END -->
