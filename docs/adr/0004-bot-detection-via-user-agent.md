# ADR 0004: 紹介サイトのボット判別は `cf.botManagement` ではなく User-Agent 判定で行う

- ステータス: Accepted（判定軸の追加を [ADR 0008](./0008-datacenter-traffic-via-as-org.md) が行った）
- 日付: 2026-08-09
- backlog decision: decision-4
- 関連タスク: TASK-386

<!-- constrained-by ../superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md -->

## Context

紹介サイトのアクセス解析は Cloudflare Worker がリクエストごとに D1 へ INSERT する
サーバ側方式である。JS ビーコンは使わない（`insertEvent`、`site/src/events.ts`）。このため
JavaScript を実行しないクローラの訪問も**既に記録されている**。`robots.txt` も
`Allow: /`（`site/src/routes/public.tsx` の `/robots.txt` ルート）なので、LP はクローラの巡回対象である。

しかし記録内容からはボットの**種類**が分からない。完全な User-Agent は保存していない。
`summarizeUA`（`site/src/lib/visitor.ts`）が Sparkle / 主要ブラウザ / curl 以外を
すべて `'other'` へ丸めるためである。`summarizeTraffic`（`site/src/analytics/summaries.ts`）の doc コメントは、
内訳を持つ目的を明記している。「`ua_summary` の内訳は AI クローラ（GPTBot / ClaudeBot 等）の到来量を実測するために持つ」。
意図はあるが実装が追いついていない。

ボットを判別する手段は 2 系統ある。

| 手段 | 確実性 | 前提 |
|---|---|---|
| `request.cf.botManagement.verifiedBot` 等 | 高い（Cloudflare が逆引き検証済み） | Bot Management の契約プランに依存 |
| User-Agent 文字列のトークン判定 | 詐称に弱い | 前提なし。UA は既に Worker が受け取っている |

現構成は `workers_dev = true`（`site/wrangler.toml`）の独自ドメイン無し運用である。
Cloudflare Access すら使えず、ダッシュボードは Worker 側 Basic 認証で保護している
（`site/src/routes/dashboard.tsx`）。この構成で `botManagement` フィールドが
取得できるかは**未実測**である。

## Decision

**まず User-Agent のトークン判定でボットを分類する。** `summarizeUA` に既知の
検索クローラ・AI クローラの分岐を追加する。判別できないボットも `'other'` に
埋もれさせず「ボットと分かる値」へ落とす。`cf.botManagement` は使わない。

理由は 3 点。

1. **前提を増やさない。** UA は既に Worker が受け取っている値であり、
   契約プランと独自ドメインのどちらにも依存しない。`botManagement` を前提に設計すると、取得できない
   場合は設計をやり直す必要が生じる。
2. **目的に対して精度が足りている。** この計測の目的は「AI クローラの到来量を実測して
   llms.txt の要否を判断する」ことである。この目的は `summarizeTraffic`
   （`site/src/analytics/summaries.ts`）が定め、TASK-360 で見送った判断の再検討材料でもある。
   詐称を排除した厳密なアクセス制御ではないため、
   UA を詐称してまで LP を巡回する主体は、この判断材料としては無視してよい。
3. **裏取り材料が既にある。** `as_org`（`request.cf.asOrganization`、`insertEvent`、`site/src/events.ts`）に
   接続元の組織名が入っている。このため UA と ASN の食い違いは事後に検算できる。

新しい列・テーブル・計測経路は追加しない。既存の `ua_summary` 列の値域を広げるだけで
足りる（既存の `GROUP BY ua_summary` がそのまま内訳表示になる）。

## Consequences

- 過去データは遡って分類できない。完全な UA を保存していないため、内訳が出るのは
  適用日以降のみで、この制約はダッシュボード側で読み取れるようにする。
- UA を詐称する巡回は人間の訪問として計上され続ける。`as_org` で事後に検算できるが、
  自動的には分離されない。
- 分類の網羅性は継続的なメンテナンスに依存する。新しい AI クローラが登場するたびに
  トークンの追加が必要で、追加するまでは「ボットと分かる値」（`BOT_OTHER` = `bot:other`）に
  集約される。ここが増え続けるなら分類漏れのシグナルとして読む。
- この決定を再検討するトリップワイヤ:
  1. 独自ドメインへ移行する、または Bot Management が使える構成になり、
     `cf.botManagement` が実際に取得できると実測できたとき
  2. `bot:other` の比率が高止まりし、UA トークンの追加では追いつかなくなったとき
  3. 計測結果を「llms.txt の要否判断」以外の用途（アクセス制御・課金・レート制限など、
     詐称耐性が要る用途）に使う要件が生まれたとき

  **1 と 3 は 2026-08-16 に検査済みで、結果は ADR 0008 にある。** 1 は「独自ドメインへの移行」を
  条件に含めていたのが誤りだった。実測の結果、`cf.botManagement` は Enterprise +
  Bot Management 契約でなければ取得できないと分かった。3 は発火し、UA 判定は維持した
  うえで接続元組織の軸を足す形で対処した。
