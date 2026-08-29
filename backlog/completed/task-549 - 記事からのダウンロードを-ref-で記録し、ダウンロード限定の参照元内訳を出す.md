---
id: TASK-549
title: 記事からのダウンロードを ?ref= で記録し、ダウンロード限定の参照元内訳を出す
status: Done
assignee: []
created_date: '2026-08-24 14:39'
updated_date: '2026-08-24 15:05'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 797000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布サイトのアナリティクスで「どの記事がダウンロードに繋がったか」が測れない。事例記事の末尾にはダウンロード導線（`{{cta}}`）が置いてあるが、記録の上では LP のボタンと区別が付かない。

## 現状（2026-08-24 に実測・コード確認）

3 つが独立に効いていて、どれか 1 つを直しても測れない。

| 何が | どうなっている | 場所 |
| --- | --- | --- |
| `source` | `'lp' \| 'sparkle' \| 'archive'` の 3 値のみ。`/download` は**どこから押されても `'lp'` 固定** | `site/src/schema.ts:39` / `site/src/routes/public.tsx:156` |
| `page` | download イベントには載らない。`page` を持つのは visit だけで、`byPage` は `kind === 'visit'` に絞ってから畳む | `site/src/analytics.ts:771` |
| `referrer` | 自サイト内の遷移は `null`。外部でも `origin` だけでパスは保存しない | `site/src/lib/referrer.ts:47`, `:49` |

visitor 単位でイベントを突き合わせる集計は `updateConversion`（`site/src/analytics.ts:1145-1190`）の 1 つだけで、対象は `update_check → update_download` のみ。軸は `day` と `channel` で、`page` は SELECT にも GROUP BY にも無い。ダッシュボードにファネル表示も無い。

## やること

読む側は既に実装済みで、`/download?ref=xxx` を踏めば `xxx` がそのまま referrer 列に入る（`site/src/events.ts:103` → `site/src/lib/referrer.ts:31-34`、64 文字で切り詰め）。`/download` 固有の除外も無い。**にもかかわらず `?ref=` を付けているリンクが 1 つも無い**のが現状。

1. **記事の CTA に `?ref=` を付ける。** 記事からのダウンロードリンクは `site/src/views/article-bodies.ts` の `{{cta}}` 展開 1 箇所に集約されているので、そこで記事 slug を載せる。スキーマ変更も移行も不要。
2. **ダウンロード限定の参照元内訳を足す。** いまの「参照元別」は `breakdown(db, 'referrer')` を**指標フィルタ無し**で呼んでいる（`site/src/analytics.ts:1334`）ため、記事 slug が Google などの外部流入元と同じ表に混ざる。`breakdown()` は `metric` 引数を既に持つ（`site/src/analytics.ts:619-637`）ので、`breakdown(db, 'referrer', 'download')` を別カードとして出す。

## 着手前に決めること

- **LP / features のボタンにも `?ref=` を付けるか。** 付けないと、それらのダウンロードは referrer が `NULL` になり、`breakdown()` の `WHERE ${column} IS NOT NULL` で新カードから丸ごと落ちる。結果「記事からのダウンロードしか出ない表」になり、記事の寄与が全体の何割かを読めない。付けるなら `lp` / `features` のような値を決めること。
- **`ref` の値の付け方。** 記事は `Article['page']`（`/usecases/medical-expenses`）から導けるが、64 文字の切り詰めがあるので slug だけにするか、接頭辞を付けるか（`usecase-medical-expenses` 等）を決める。値をリテラルで散らかさず、`lib/pages.ts` の `pathFor` と同じく 1 箇所から導く形にすること。
- **`?ref=` は外部参照元を上書きする**（`resolveReferrer` の最優先分岐）。download イベントの referrer は内部遷移で元々 `null` なので失うものは無いが、この性質は把握した上で入れること。

## 背景

TASK-548 の作業中に「事例記事では宣伝を前に出したくないので CTA を外したい」という話が出て、一度外す変更を入れた。その後「記事がダウンロードに結びついたか計測できるなら残す」という判断で戻したが、調べた結果**その計測は成立していなかった**。CTA を残すか外すかの判断を、実際に測れる状態にしてからやり直せるようにするのがこのタスクの狙い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 記事の CTA からのダウンロードが、LP / features からのダウンロードと区別して数えられる
- [x] #2 ダッシュボードにダウンロード限定の参照元内訳が出る（既存の全 kind 混在の「参照元別」とは別のカード）
- [x] #3 ref の値がリテラルの散らかしではなく 1 箇所から導かれている（記事を足したときに付け忘れが起きない形）
- [x] #4 上の「着手前に決めること」3 点の結論が Implementation Notes に残っている
- [x] #5 site の vitest が通り、?ref= 付きのリンクが出ることと、参照元内訳が download に絞られていることをテストが固定している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
実装前に /review-design を 1 回実施し、設計を 2 点変更した（下の「レビューで変えた点」）。

## 決めたこと（タスク記載の「着手前に決めること」への回答）

1. **LP / features のボタンにも ?ref= を付ける。** 付けないと referrer が null になり、
   `breakdown()` の `WHERE referrer IS NOT NULL`（analytics.ts:621-639）で新カードから
   丸ごと消える。「LP 経由が 0 件」ではなく「行が存在しない」形になるため必須。
2. **ref の値は `Page`（schema.ts:50-63）から機械的に導くスラグ**。`'/'` → `lp`、
   それ以外は先頭 `/` を落として `/` を `-` に畳む（`features` / `usecases-medical-expenses`）。
   対応表を持たないので記事を足したときの同期漏れが起きない。
3. **`?ref=` が外部参照元を上書きする件は問題にならない。** `/download` は visit を
   記録しない（routes/public.tsx:143-158）ので visit の referrer は壊れない。
   `/download` への外部直リンクは README の `?ref=readme` だけで、既に明示値。

## レビューで変えた点

### (1) ref の語彙をパスからスラグへ
当初案は `Page` の値（`/usecases/medical-expenses`）をそのまま入れるつもりだった。
しかし `?ref=` は**既に運用中**で、値は短いチャネル識別子（`gh-pages`＝docs/index.html:12,
`readme`＝README.md:19,20,77）。referrer 列には既に「外部オリジンの絶対 URL」と
「チャネル名」の 2 種があり、パス形式を足すと 3 種目になるうえ外部オリジンと
目視で区別しづらい。スラグに揃えると referrer の意味が
「**ダウンロードが始まった面**」で一貫する（README も LP も記事も同じ軸）。

### (2) 新カードは独立クエリにしない
`site/test/query-count.test.ts:35` の `MAX_QUERIES_PER_PAGE = 8` に対し、流入面は
**現状ちょうど 8 本**。`breakdown` を 1 本足すと 9 本で落ちる。
`docs/dev/development.md:158-163` が「上限を上げるのではなく既存クエリへ列を足すか
UNION ALL で束ねる」と明記しており、前例も `trafficSplit`（analytics.ts:684-690、
TASK-490）と os/as_org の UNION ALL（TASK-491.2）がある。
既存の `breakdown(db,'referrer')` を **scope を行に持たせた 1 本**へ畳む。

## 実装

### 1. site/src/views/shared.tsx
- `downloadRef(from: Page): string` — 上の規則でスラグを導く
- `downloadHref(from: Page): string` — `/download?ref=<slug>`。**デフォルト引数を置かない**
  （リンクを足すとき ref の指定を省けない = 破れない構造）
- `DOWNLOAD_PATH` は JSON-LD 用に残すが、doc コメントで「人がクリックするリンクには
  downloadHref を使う」と明示する

### 2. リンク側の差し替え（人がクリックする 5 箇所）
- landing.tsx:152,302,311 → `downloadHref('/')`
- features.tsx:308 → `downloadHref('/features')`
- article-bodies.ts:76（`{{cta}}`）→ `downloadHref(article.page)`
  - `TOKENS` の署名を `(lang, page) => string` にし、`expandTokens` に page を足す。
    トークンは 1 つ、`expandTokens` の呼び出し元も 1 箇所（:154）で、同スコープに
    `article` があるためそのまま渡せる
- landing.tsx:103（JSON-LD `downloadUrl`）は素の `DOWNLOAD_PATH` のまま

### 3. site/src/analytics.ts
- `breakdown(db,'referrer')` を `referrerBreakdowns(db)` に置き換え、
  `UNION ALL` + `ROW_NUMBER() OVER (PARTITION BY scope)` で
  `{ all: Count[]; download: Count[] }` を **1 クエリ**で返す
  - `all` は現状どおり `referrer IS NOT NULL`（既存カードの挙動を変えない）
  - `download` は `METRIC_FILTERS.download`（kind='download' AND source='lp'）で絞り、
    `COALESCE(referrer, UNRECORDED_LABEL)` にする。ref の無いダウンロードが
    黙って消えると「LP 経由しか無い」と読み違えるため
- `TrafficSummary` に `byDownloadReferrer: Count[]` を足す
- `summarizeTraffic` の doc「（8 クエリ）」は **8 のまま**（本数を増やさない）

### 4. site/src/views/dashboard.tsx
- `:710` の直後に `<CountTable title="ダウンロード（LP）: 参照元別" ...>` を足す
  （既存の指標別テーブルの命名規則に合わせる）

### 5. ドキュメント
- `site/README.md:340-342` の「国別・参照元別は指標を分けても読み取れる情報が
  増えないため 3 種合算のまま残している」を更新する。`?ref=` が
  「ダウンロードが始まった面」を運ぶようになったことで前提が変わり、
  download に絞った参照元は全体とは別の問いに答えるため

## テスト（退行の担保）

- LP / features / 記事の HTML に `href="/download?ref=..."` が出ること、
  **素の `href="/download"` が残っていないこと**（downloadHref を迂回した書き方の検出）
- `/download?ref=usecases-medical-expenses` を叩くと events.referrer にその値が入ること
- `byDownloadReferrer` が kind='download' AND source='lp' に絞られること
  （sparkle / archive の行と visit の行が混ざらないこと）
- ref を持たない download が `未記録` として出ること
- 既存の落ちるテストを直す: `site/test/public.test.ts:122`、`:913-914`、
  `site/test/articles.test.ts:340,346` が `href="/download"` を完全一致で固定している
- `site/test/query-count.test.ts` が緑のままであること（流入面 8 本を超えない）

## チェックリストで該当しなかった項目

- 項目 1（判定の真実の源）: 新しい述語は増やさない。ref は「どのリンクを描いたか」
  という事実から出る値で、データの中身の有無で決める判定ではない
- 項目 5（ライフサイクル・順序）: 集計はリクエストごとに毎回実行され、
  キャッシュ化・常駐化はしない
- 項目 8（非同期の世代管理）: 非同期で置き換わる表示状態を足さない
- 項目 10（型グループの行数）: Swift 専用の指標で、今回は site/ の TypeScript のみ
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装した形

- `site/src/views/shared.tsx`: `downloadRef(from: Page)` と `downloadHref(from: Page)` を追加。
  `downloadHref` は**デフォルト引数を持たない**ので、リンクを足すとき ref の指定を省けない。
  `DOWNLOAD_PATH` は JSON-LD 用に残し、doc コメントで「人がクリックするリンクには
  downloadHref を使う」と明示した
- ref の値は `Page` から機械的に導くスラグ（`'/'` → `lp`、それ以外は先頭 `/` を落として
  `/` を `-` に畳む）。対応表を持たないので同期漏れが起きない
- 差し替えたリンクは 5 箇所: landing.tsx の 3 箇所（`'/'`）、features.tsx の 1 箇所
  （`'/features'`）、article-bodies.ts の `{{cta}}`（`article.page`）。JSON-LD の
  `downloadUrl` は素の `DOWNLOAD_PATH` のまま
- `TOKENS` の署名を `(lang, page) => string` にし、`expandTokens` に page を足した
  （呼び出し元は `renderAll` の 1 箇所で、同スコープに `article` がある）
- `site/src/analytics.ts`: `breakdown(db,'referrer')` を `referrerBreakdowns(db)` に置き換え、
  `UNION ALL` + `ROW_NUMBER() OVER (PARTITION BY scope)` で全体とダウンロード（LP）の
  2 母集団を**1 クエリ**で返す。`breakdown()` の `metric` 引数は使い手がいなくなったので削除した
- ダウンロード側だけ `COALESCE(referrer, UNRECORDED_LABEL)`。ref の無いダウンロードが
  `IS NOT NULL` で消えると「LP 経由しか無い」と読み違えるため
- `site/src/views/dashboard.tsx`: 「参照元別」の直後に「ダウンロード（LP）: 参照元別」を追加

## 検証

- `npm test`（site）: 422 passed / 13 files（変更前は 409）
- **修正を戻すと落ちることを 2 通り実測**:
  - features.tsx のリンクを素の `DOWNLOAD_PATH` に戻す → public.test.ts が 5 件失敗
    （「?ref= が付く」「素の href="/download" が残っていない」ほか）
  - `referrerBreakdowns` の download 側から `AND ${downloadFilter}` を外す →
    「kind=download かつ source=lp の行だけを数える」が失敗
- `query-count.test.ts`: 7 passed。流入面は 8 本のままで `MAX_QUERIES_PER_PAGE` を超えない
- `npm run lint` / `format:check` / `tsc --noEmit` / `markdownlint-cli2`: 指摘なし

## 承知のうえで残した挙動

**ドラフト記事の CTA も公開後の記事スラグを載せる。** `articleHtml` はモジュール読み込み時に
記事ごと 1 回だけ組み立てるため、ドラフト経路と公開経路で同じ HTML を配る。href を
ドラフトかどうかで分けるには本文を 2 通り描くことになり、割に合わない。
visit の page がドラフトを `DRAFT_PAGE` へ畳んでいる理由は
「記事ごとの粒度に価値がなくカーディナリティだけ増える」（routes/public.tsx:76-77）で、
ref はスラグが既存の enum 由来なのでカーディナリティは増えない。

## 未対応（今回の範囲外）

`docs/adr/0007-distribution-site-custom-domain.md:172` が旧名 `DOWNLOAD_URL` と
`shared.tsx:13` を指したままずれている（現状は `DOWNLOAD_PATH` / `shared.tsx:27`）。
このタスクで作り込んだずれではないので触っていない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイト内のダウンロードリンクを downloadHref(from: Page) 経由に一本化し、?ref= に「ダウンロードが始まった面」のスラグ（lp / features / usecases-medical-expenses）を載せた。ref は Page から機械的に導くので対応表の同期漏れが起きず、引数に既定値を置かないのでリンクを足すとき省けない。ダッシュボードには「ダウンロード（LP）: 参照元別」を追加し、既存の referrer クエリへ scope を行として畳んで 1 クエリのまま実現した（流入面はクエリ本数の上限ちょうどのため）。ref を持たないダウンロードは未記録として並べ、黙って消えないようにした。site の vitest 422 件が通り、リンクを素の /download に戻すと 5 件、download の絞り込みを外すと 1 件が落ちることを実測で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
