---
id: TASK-551
title: ダッシュボードの主指標を LP 限定から人のサイト訪問全体へ移し、概要面を組み替える
status: To Do
assignee: []
created_date: '2026-08-25 01:51'
updated_date: '2026-08-25 01:56'
labels: []
dependencies: []
priority: high
type: feature
ordinal: 799000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ダッシュボードの概要面が「人がサイトをどれだけ訪れているか」を答えられていない。実際、`/usecases/medical-expenses` へのアクセスがイベント面には出るのに、概要面の「ページアクセス」は 2 のまま動かない。

## 現状（2026-08-25 にコード確認）

| 何が | どうなっている | 場所 |
| --- | --- | --- |
| 「ページアクセス」指標 | `kind='visit' AND COALESCE(page,'/') = '/'`。**LP（`/`・`/en`）への訪問だけ**を数える。TASK-488.1 で features・releases・usecases・記事も visit として記録し始めたが、この系列は過去データの連続性のため意図的に page で絞っている | `site/src/analytics.ts` の `METRIC_FILTERS.visit` |
| 記事・下層ページの記録 | **既に記録されている。** 固定ページのループと `registerArticle` の両方が `kind:'visit'` を入れる。`page` は `pageSchema` の列挙に限定（`/`, `/features`, `/releases`, `/usecases`, `/usecases/medical-expenses`, `/usecases/ai-code-review`, `/drafts`） | `site/src/routes/public.tsx`, `site/src/schema.ts` |
| ボット除外 | **既に効いている。** `HUMAN_ONLY = NOT (BOT_MATCH OR DATACENTER_MATCH)` が集計クエリのほぼ全てに入り、`analytics.test.ts` が「`FROM events` を含むクエリは `HUMAN_ONLY` を含む」ことを機械的に検査する | `site/src/analytics.ts` |
| 概要面の中身 | `KIND_LABELS` の 5 指標をカードと日次グラフに並べる。うち 4 つがダウンロード系（LP / 自動更新 / 旧版 / 更新確認）で、人のアクセスを表すのは LP 限定の visit 1 つだけ | `site/src/views/dashboard.tsx` の `OverviewSections` |

**スキーマ変更も移行も不要。** データは揃っていて、集計側のフィルタと画面の構成だけの問題。

なお Sparkle の appcast アクセスは `summarizeUA` が `'Sparkle'` に丸めるだけで `bot:` 接頭辞が付かず、`HUMAN_ONLY` を通過する。「ページアクセス」に混ざらないのは kind が `update_check` で分かれているからであって、除外されているからではない。この性質は「ユニークアクセス元（全種別）」には効いている。

## やること

ユーザーと合意した方針は次の 2 点。

1. **「サイト訪問（全ページ）」を主指標にする。** LP 限定は流入面の「ページ別の訪問」の内訳として見る。既存の LP 系列を捨てるのではなく、主従を入れ替える。
2. **概要面を人のアクセス中心に組み替える。** ダウンロードは合計 1 枚だけ概要に残し、内訳（自動更新 / 旧版 / 更新確認）は既存の配信面・利用者面へ寄せる。

## 着手前に決めること

- **過去データの段差をどう扱うか。** `page` 列は TASK-488.1 より前のイベントに無く、`metricExpression` の `COALESCE(page, '/')` がそれを LP 扱いしている。全ページ集計へ切り替えると、記録開始日を境に母数が増える段差が日次グラフに出る。実データであって不具合ではないので注記で説明する方針だが、注記の置き場（グラフ脇か、`ANALYTICS_COLUMN_START` 系の定数と同じ扱いか）は決めること。
- **`MetricKey` の語彙をどうするか。** 既存 `visit` の意味を全ページへ広げるのか、`visit`（全ページ）と LP 限定を別キーにするのか。後者は `KIND_LABELS` と `OPERATIONAL_KINDS` が全 `MetricKey` を覆うことを検査するテストに影響する。
- **クエリ本数の上限。** `site/test/query-count.test.ts` の `MAX_QUERIES_PER_PAGE = 8` があり、`docs/dev/development.md` が「上限を上げるのではなく既存クエリへ列を足すか UNION ALL で束ねる」と定めている。概要面へ系列を足すならこの制約の中で収めること。
- **概要面から外す指標の行き先。** 「消す」ではなく「どの面のどのセクションへ移すか」を明示すること。移し先が無い指標を黙って落とさない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 概要面の主指標が、ボットとデータセンター経由を除いた全ページの visit を数えている（/usecases/* や記事へのアクセスが反映される）
- [ ] #2 LP 限定の訪問数が失われず、流入面の「ページ別の訪問」から読み取れる
- [ ] #3 概要面に残るダウンロード指標は合計のみで、内訳（自動更新・旧版・更新確認）とアップデート確認は流入面「内訳（全期間の累計）」から読める
- [ ] #4 概要面から移動した指標の移動先が Implementation Notes に列挙されている（黙って消えたものが無い）
- [ ] #5 上の「着手前に決めること」4 点の結論が Implementation Notes に残っている
- [ ] #6 site の vitest が通り、主指標が page で絞られていないことと、query-count.test.ts の上限を超えないことをテストが固定している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
実装着手前に `/review-design` を 1 回実施した。チェックリスト 10 項目のうち 7 項目が該当し、うち 3 件は当初案のままでは破れるため設計を変更した（下の「レビューで変えた点」）。

## 決めたこと（タスクの「着手前に決めること」への回答）

### 1. 新しい `MetricKey` を足さず、既存 `visit` の述語を広げる

`METRIC_FILTERS.visit` を `{ kind: 'visit', source: null, page: null }` にする。`metricExpression` は `page === null` のとき `COALESCE(page,'/')` 句ごと落とすので、述語は `kind = 'visit'` になる。

**`visit`（全ページ）と `visit_lp`（LP 限定）の 2 キーに割る案は採らない。** `METRIC_EXPR` は `CASE WHEN ... THEN` の連鎖で**先頭一致が勝つ**ため、visit 系のキーを 2 つ持つと LP への訪問行は先に書いたほうへ吸われ、もう一方は `metricBreakdowns`（流入面の OS 別・接続元組織別・バージョン別）で**常に 0** になる。一方 `KIND_COUNT_COLUMNS` は指標ごとに独立した `SUM()` なので両方が数える。**同じ `METRIC_FILTERS` から派生する 2 つの消費先が食い違う**形になり、画面上は「カードは 2、内訳表は 0」という無音の矛盾として出る。

### 2. 過去データの段差は説明しない（無視する）

`page` 列の導入は 2026-08-16（`50dd6674`、`LANGUAGE_URL_START` / `HOST_COLUMN_START` と同じコミット）。それ以前の visit は LP でしか記録しておらず、`page` は NULL。

述語から page 条件が消えるので、**旧行は今までどおり数えられ、値は減らない**。段差は「2026-08-16 以降だけ下層ページのぶん増える」形で出る。

**この段差は画面で説明しない。** 下層ページ（`/usecases` と記事）を足したのが最近で、実データ上の差が無視できる規模だとユーザが判断したため（2026-08-25）。`PAGE_COLUMN_START` 定数は追加しない。他の 5 つの `*_COLUMN_START` は「その日より前は遡って分類できない」ことを説明するために要るが、ここは分類が変わるのではなく計測範囲が広がるだけで、しかも広がったぶんが小さい。

ただし流入面「ページ別の訪問」の注記にある「ページアクセスの指標は LP（/）だけを数えているため、ここの合計とは一致しない」は**この変更で偽になる**ので、これは必ず直す。

### 3. クエリ本数は増やさない（概要面は SSE で 2.5 秒ごとに再実行される）

`site/src/routes/dashboard.tsx` の `/dashboard/stream` は、新着イベントがあった周期で `renderOverviewSections(await summarizeOverview(db, Date.now()))` を丸ごと呼び直す。`POLL_INTERVAL_MS = 2500`、`MAX_STREAM_MS = 10 分`。つまり**概要面のクエリ本数は「開いたとき 1 回」ではなく「ブラウザを開いている間 2.5 秒ごと」のコスト**である。

`site/test/query-count.test.ts` は `summarizeOverview` を 1 回呼んで `prepare` を数えるだけなので、この周期コストを測っていない（項目 7 の該当。別タスクへ切り出す）。

したがって概要面へクエリを足さない。今回の変更は**既存 4 本（`cumulativeTotals` / `todayTotals` / `dailySeries` / `recentEvents`）のまま**で、表示する指標を減らす方向なので周期コストはむしろ下がる。

### 4. 概要面から外す指標の行き先

**「消す」ではなく「流入面で表示する」。** `summarizeTraffic` は既に `cumulativeTotals` を引いて `perKind[].total` に概要カードと**同一の数字**を持っているが、`TrafficSections` は `byOS` / `byAsOrg` / `byVersion` の `CountTable` しか描いておらず `entry.total` を画面に出していない。ここを描くだけで移設が済む（**新しいクエリは 0 本**）。

| 概要面から外すもの | 行き先 |
| --- | --- |
| アップデート確認（`update_check`）のカード | 流入面「内訳（全期間の累計）」の `perKind` に総数を描画 |
| ダウンロード（LP / 自動更新 / 旧バージョン）の各カード | 同上 |
| 推移グラフの `update_download` / `archive_download` 系列 | 同上（日次の内訳が要るなら別タスク。現状 利用者面の時間帯分布が直近 14 日を同じ 5 系列で持つ） |

## 実装

### 1. `site/src/analytics.ts`

- `METRIC_FILTERS.visit` の `page: '/'` → `page: null`。コメントを「LP 限定にしていた理由」から「サイト全体を数える。LP 限定は流入面のページ別で読む」に書き換える
- `KIND_LABELS` の `visit` のラベルを `'ページアクセス'` → **`'ページビュー'`** にする。`'サイト訪問'` にはしない（`UNIQUE_SOURCE_LABELS` の `visit` が既に `'サイト訪問'` で、そちらは**アクセス元の異なり数**。同名にすると利用者面と概要面で同じ語が別の単位を指す）
- **`KIND_LABELS` からは何も外さない。** `KIND_LABELS` は概要カード・概要推移グラフ・利用者面の時間帯分布・流入面 `perKind` の 4 箇所が消費しており、ここを削ると概要面以外の 3 箇所からも黙って消える
- 代わりに `OVERVIEW_METRICS: ReadonlySet<MetricKey>`（`visit` と `download` のみ）を新設し、概要面の描画だけがこれで絞る。**定義は `analytics.ts` に置き、`DOWNLOAD_METRICS` と同様に `METRIC_FILTERS` から導けるものは導く**

### 2. `site/src/views/dashboard.tsx`

- `metricCards(counts, idPrefix)` に**第 3 引数として対象集合を必須で渡す**形にする（デフォルト引数を置かない = 項目 9 の担保）。概要面は `OVERVIEW_METRICS`、他の呼び出し元は `KIND_LABELS` 全体を渡す
- `OverviewSections`:
  - 「累計」カード = ページビュー / ダウンロード合計 / 延べアクセス元（3 枚）
  - 「本日」カード = ページビュー / ダウンロード合計 / ユニークアクセス元（3 枚）
  - 「日毎の推移」の系列 = `OVERVIEW_METRICS` の 2 本（ページビュー・ダウンロード（LP））
  - 注記を足す: ボットとデータセンター経由を除いていること、LP 単独の数は流入面「ページ別の訪問」で読めること
- `TrafficSections` の「内訳（全期間の累計）」に `perKind[].total` を出す。「ページ別の訪問」の注記から「ページアクセスの指標は LP（/）だけを数えているため、ここの合計とは一致しない」という**もう成立しない文**を落とす

### 3. 系列数の上限（項目 4）

`SeriesChart` の色は `--series-1` 〜 `--series-5` の 5 本で、**宣言順に固定割当・5 系列が上限**。現在の概要推移グラフはちょうど 5 系列で上限に張り付いている。今回 2 系列へ減らすので上限から離れる。**この上限は設計上の制約として Notes に残す**（次に系列を足す人が 6 本目で無音に色を失わないように）。

## テスト（退行の担保）

- 既存テスト「「ページアクセス」の全系列が LP だけを数える」（`site/test/analytics.test.ts`）を**削除せず裏返す**: `/` と `/features` を入れて累計・当日・日次・時間帯・`perKind` の全系列が 3 を返すこと。この test は「述語を書き写す形への退行」を検知するためのもので、その役割は今回の変更後も要る
- 既存テスト「page 列の導入前に記録された visit は LP として数える」は、述語から page 条件が消えるので**「page が NULL の visit も数える」**へ書き換える（旧行が落ちないことの担保はそのまま要る）
- 新規: `/usecases/medical-expenses` への visit が概要面の `visit` に反映されること
- 新規: 概要面のカードと推移グラフに `update_download` / `archive_download` / `update_check` が**出ないこと**、かつ流入面の `perKind` に**出ること**（移設先が空でないことの担保 = 「黙って消えた」を検出する）
- 新規: `KIND_LABELS` と `OVERVIEW_METRICS` の関係 — `OVERVIEW_METRICS` が `KIND_LABELS` の部分集合であること（概要にだけ現れて他の面に無い指標を作らない）
- `site/test/query-count.test.ts` が緑のまま（概要面は 4 本のまま）であること
- `site/test/analytics.test.ts` の「自動アクセス除外の条件が 1 箇所に集約されている」が緑のまま
- 既存の `counts.visit` を固定している assertion 群（`analytics.test.ts` に約 20 箇所）は、LP のみを入れているケースは値が変わらない。`/features` を混ぜているケースだけ期待値が変わるので、1 件ずつ意図を確認して直す（機械的な一括置換をしない）

## レビューで変えた点

### (1) 新キー追加案 → 既存キーの述語変更（項目 1・3）
当初は `visit`（全ページ）と LP 限定を別 `MetricKey` にする案も検討したが、上の「決めたこと 1」のとおり `METRIC_EXPR` の `CASE` 先頭一致で `metricBreakdowns` 側が無音で 0 になる。LP 限定は**指標として持たず**、流入面「ページ別の訪問」の `/` 行（既存）で読む。

### (2) `KIND_LABELS` から外す案 → 面ごとの表示集合を新設（項目 2・3・9）
「概要面からダウンロード内訳を外す」を `KIND_LABELS` の削除で実現すると、利用者面の時間帯分布と流入面 `perKind` からも同時に消える（`KIND_LABELS` の消費先は 4 箇所）。さらに `analytics.test.ts` の `describe('kind の行き先')` が「全 `EventKind` が `KIND_LABELS` か `OPERATIONAL_KINDS` のどちらかに入る」ことを検査しているため、外すと `OPERATIONAL_KINDS`（＝運用観測）へ移すことになり、意味が変わる。

代わりに `OVERVIEW_METRICS` を新設し、`metricCards` の引数を**必須**にした。デフォルト引数を残すと、次に指標を足した人が渡し忘れてもコンパイルが通り、概要面へ静かに復活する（TASK-319 と同型）。

### (3) 「概要面にクエリを足してもよい」→ 足さない（項目 6・7）
`MAX_QUERIES_PER_PAGE = 8` に対し概要面は 4 本で枠が空いているが、SSE が 2.5 秒周期で `summarizeOverview` を丸ごと呼び直すため、概要面の 1 本は他の面の 1 本と重みが違う。移設先の流入面 `perKind` が既に同じ数字を持っていたため、クエリ 0 本増で済む形に寄せた。

## 別タスクへ切り出すもの

起票済み: **TASK-552**（`query-count.test.ts` の SSE 周期コストと内訳ずれ）、**TASK-553**（`eventBreakdowns` の visit 判定が `METRIC_FILTERS` の外に残っている件。TASK-551 を dep に持つ）。

## チェックリストで該当しなかった項目

- **項目 5（ライフサイクル・順序）**: SSE は `#summary` の `innerHTML` をサーバ生成 HTML で丸ごと差し替えるだけで、クライアント側に集計状態を持たない（`STREAM_SCRIPT` にリスナは `open` / `error` / `summary` の 3 つのみ、`event: event` のリスナは無い）。初期化順序も再計算回数も変わらない
- **項目 8（非同期の世代管理）**: 同上。部分的に置き換わる表示状態が無く、開始時の無効化・着地時の一致確認を要する箇所が生まれない
- **項目 10（型グループの行数）**: Swift 専用の指標（`scripts/check-type-group-size.sh`）で、今回は site/ の TypeScript のみ。なお `.oxlintrc.json` は `eslint/max-lines` を off にしており、TS 側に行数の機械的上限は無い。`dashboard.tsx` は 1,011 行で、今回は表示指標を減らす変更なので純増は注記ぶんに留まる
<!-- SECTION:PLAN:END -->
