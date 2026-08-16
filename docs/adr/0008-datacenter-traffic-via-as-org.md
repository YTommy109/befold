# ADR 0008: データセンター由来の自動アクセスを接続元組織（as_org）で人間の訪問から分離する

- ステータス: Accepted
- 日付: 2026-08-16
- backlog decision: decision-8
- 関連タスク: TASK-490

<!-- derived-from ./0004-bot-detection-via-user-agent.md -->
<!-- constrained-by ./0007-distribution-site-custom-domain.md -->

## Context

配布サイトの計測は User-Agent のトークンでボットを分類している（ADR 0004）。
判定は `summarizeUA`（`site/src/lib/visitor.ts`）が記録時に行い、集計側は
`ua_summary` の `bot:` 接頭辞だけを見る（`site/src/analytics.ts` の `BOT_MATCH`）。

この方式では捕まらない自動アクセスが、実データで無視できない量に達している。
2026-08-16 時点の本番 D1 で、visit として記録された 372 件を接続元組織
（`as_org` = `request.cf.asOrganization`）別に見た結果:

| 接続元組織 | ua_summary | 件数 |
| --- | --- | --- |
| Meta Platforms Ireland Limited | other / Chrome / Safari | 57 |
| Amazon Data Services Northern Virginia | other / Chrome | 35 |
| Amazon Technologies Inc. | Chrome / other | 27 |
| Google LLC | other / Chrome | 17 |
| SAKURA Internet Inc. | other | 12 |
| Amazon.com, Inc. | other / Chrome | 9 |
| Twitter Inc. | other | 8 |
| Driftnet Ltd | other | 8 |
| DigitalOcean, LLC | Chrome / Firefox | 8 |

いずれも UA がボットを名乗らないため `bot:` が付かず、**人間の訪問として
計上されていた**。きっかけは TASK-489.3 で見つけた 4 件で、`befold.degino.com:2052`
のような Cloudflare の HTTP 代替ポートを参照元に持ち、接続元はインターネット全域
スキャン業者の Driftnet Ltd だった。

この数字の使いみちが変わっていることが問題を大きくしている。ADR 0007 は旧ホストと
GitHub 配布経路を止めてよいかを人間の訪問数で判断すると決めた（TASK-489）。
**停止は取り返しがつかない**ので、人間の数が実態より膨らんだままでは判断できない。
これは ADR 0004 が挙げた再検討トリップワイヤ 3（「計測結果を llms.txt の要否判断
以外の、詐称耐性が要る用途に使う要件が生まれたとき」、同 :107-110）そのものである。

### `cf.botManagement` は使えない（実測）

ADR 0004 のトリップワイヤ 1 は「独自ドメインへ移行する、または Bot Management が
使える構成になり、`cf.botManagement` が実際に取得できると実測できたとき」だった。
独自ドメインへの移行は TASK-476 / ADR 0007 で完了しているので、**当時「未実測」
だった点を実測した**（2026-08-16）。

1. **エッジ実行**: `request.cf` を JSON で返すだけの使い捨て Worker を
   `wrangler dev --remote` で Cloudflare のエッジ上に置いて叩いた。返った
   `Object.keys(request.cf)` は 30 個で、**`botManagement` は含まれない**
   （`asOrganization` / `asn` / `colo` / `verifiedBotCategory` などのみ）。
2. **契約プラン**: Cloudflare API の `GET /zones` で `degino.com` の plan は
   `Free Website`。
3. **ドキュメント**: Bot Management のフィールドは
   「Requires a Cloudflare Enterprise plan with Bot Management enabled」
   （developers.cloudflare.com/bots/reference/bot-management-variables/）。

つまり必要なのは独自ドメインではなく Enterprise + Bot Management 契約であり、
**トリップワイヤ 1 は発火していない**（条件の書き方のほうが誤っていた）。
`cf.verifiedBotCategory` は Free でもキーとして存在するが、値が入るのは Cloudflare が
逆引き検証済みの good bot だけで、EC2 や Driftnet からのスキャンは対象外。単体では
この問題を解けない。

## Decision

**`as_org` による「データセンター由来」の判定を、UA 判定とは別の軸として足す。**
判定は記録時ではなく**集計時**に行う。ADR 0004 の UA 判定は維持する（supersede
しない）。

### 1. 集計時に判定する

`as_org` は 2026-07-30 の列追加以降すべての行に記録されている。集計時に判定すれば
**過去データにも遡って効く**。UA 分類が遡れなかった（完全な UA を保存していない）
のと非対称で、これがこの軸を選んだ決め手。列の追加もマイグレーションも計測経路の
変更も要らない。

`cf.asn` を新しい列に足して ASN のデータセットで判定する案は採らない。遡及が効かず、
外部データセットの同梱と更新が要る。

### 2. 判定は 1 箇所に集約する

パターンの列挙と SQL 断片の生成は `site/src/lib/network.ts` だけに置く
（`DATACENTER_ORG_PATTERNS` と `datacenterOrgMatch`）。`analytics.ts` は
`BOT_MATCH`（UA 軸）と `DATACENTER_MATCH`（接続元軸）を `NON_HUMAN_MATCH` へ束ね、
`HUMAN_ONLY = NOT NON_HUMAN_MATCH` とする。集計クエリはこれまでどおり
`HUMAN_ONLY` だけを見る。

2 軸を OR で束ねる形を他所に書かない。片方だけを見る箇所ができると、
「人間側から引かれたのに自動アクセス側にも出ない」という**総和の合わない表示**に
なる（`trafficSplit` / `eventBreakdowns` がまさにその位置にある）。

### 3. 迷ったら人間側に残す

誤って人間を落とす向きの間違いのほうが高くつく。この数字は ADR 0007 の停止判断に
使うので、人間を少なく見積もると**まだ使われている配布経路を止めてしまう**。
次のものはデータセンターに含めない。

- **プライバシー中継の出口**（Cloudflare / Akamai / Fastly）。iCloud Private Relay と
  WARP はこれらの組織名で出る（実測: 本番に `Cloudflare London, LLC` + Chrome +
  macOS + JP が 1 件）。
- **VPN・Tor の出口**（`TOR EXIT AND MORE`、`UAB code200` 等）。自動アクセスとは
  限らない。
- **消費者向け ISP**。日本の ARTERIA / KDDI / So-net / IIJ / BIGLOBE / NTT 系などは
  法人向けホスティングも兼ねるが、人間の訪問が主。
- **`as_org` が NULL の行**。NULL は「データセンターでない」ではなく「不明」。

`COALESCE(as_org, '')` を外さないこと。`NULL LIKE ...` は NULL を返すため、素の LIKE を
WHERE に置くと NULL の行が人間でもデータセンターでもなく黙って全集計から消える
（`BOT_MATCH` が同じ理由で COALESCE を持っている）。

### 4. UA でボットと分かるものが優先

データセンターから来る Googlebot は「ロボット」に数える。「データセンター」へ
寄せると、ADR 0004 が測りたかった「AI クローラの到来量」がクローラ名の内訳から
消えるため。

### 5. 除外した量を画面から消さない

人間側の「接続元組織別」テーブル（`metricBreakdown('as_org')`）は `HUMAN_ONLY` 付き
なので、この変更でデータセンターの組織名がそこから消える。**今回の問題を発見した
のがまさにその表**なので、データセンター区分専用の内訳表（接続元組織別）を
ダッシュボードに用意する。区分は「人間 / ロボット / データセンター」の 3 つとして
数え、カードにも 3 つ並べる。

## Consequences

- **人間の訪問数が大きく下がる。** 2026-08-16 時点の本番 visit 372 件は、この判定で
  human 151（ユニーク 87）/ datacenter 207（190）/ bot 14（14）になる。過去の日別
  推移も遡って下がるため、**同じ日の数字が前に見たときと違う**。この非対称
  （UA 分類は適用日以降のみ、接続元判定は全期間）はダッシュボードの注記で示す。
- **as_org 列を足す前（2026-07-30 より前）の行は判定材料が無く、人間側に残る。**
  UA 分類の 2026-08-09 と合わせて、境界が 2 つある。
- **パターンの列挙は継続的なメンテナンスに依存する。** ADR 0004 の UA トークンと
  同じ性質で、新しいホスティング事業者が現れるたびに追加が要る。人間側の
  「接続元組織別」テーブルに見慣れない事業者名が並び始めたら追加のシグナルとして
  読む（この表を人間側に残しているのはそのため）。
- **VPN やプライバシー中継の背後から来る自動アクセスは人間として残る。** 上の
  「迷ったら人間側」の裏返しで、意図した取りこぼし。
- **`curl` は依然として人間として数える。** 判定軸が UA 側であり、作者自身の疎通
  確認である可能性が高いことも含めて別途判断する（TASK-490 の Notes に記録）。
- **ADR 0004 は維持する。** UA 判定は残り、`bot:` 接頭辞の意味も変わらない。
  変わるのは「集計から外れるもの」がボットだけではなくなった点で、ADR 0004 の
  トリップワイヤ 1 の書き方（独自ドメインへの移行を条件に含めていた）は誤りだった
  ことがこの ADR で分かる。
- この決定を再検討するトリップワイヤ:
  1. Enterprise + Bot Management が使える構成になり、`cf.botManagement` が実際に
     取得できると実測できたとき（ドメイン構成では変わらないことが分かったので、
     条件を契約プランで書き直した）
  2. 人間側の「接続元組織別」に未知のホスティング事業者が並び、パターンの追加では
     追いつかなくなったとき（ASN ベースの判定へ切り替える）
  3. プライバシー中継・VPN の背後からの自動アクセスが無視できない量になったとき
