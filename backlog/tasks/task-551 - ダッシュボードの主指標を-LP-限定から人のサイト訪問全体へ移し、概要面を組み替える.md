---
id: TASK-551
title: ダッシュボードの主指標を LP 限定から人のサイト訪問全体へ移し、概要面を組み替える
status: To Do
assignee: []
created_date: '2026-08-25 01:51'
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
- [ ] #3 概要面に残るダウンロード指標は合計のみで、内訳（自動更新・旧版・更新確認）は配信面または利用者面から読める
- [ ] #4 概要面から移動した指標の移動先が Implementation Notes に列挙されている（黙って消えたものが無い）
- [ ] #5 page 列の記録開始による母数の段差が画面上で説明されている
- [ ] #6 上の「着手前に決めること」4 点の結論が Implementation Notes に残っている
- [ ] #7 site の vitest が通り、主指標が page で絞られていないことと、query-count.test.ts の上限を超えないことをテストが固定している
<!-- AC:END -->
