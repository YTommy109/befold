# ADR 0007: 配布サイトを独自ドメイン befold.degino.com へ移し、workers.dev は恒久的に併存させる

- ステータス: Accepted
- 日付: 2026-08-14
- backlog decision: decision-7
- 関連タスク: TASK-476（サブタスク 476.1〜476.6）
- 更新: [ADR 0011](./0011-legacy-distribution-shutdown-conditions.md) が決定 1 の
  「停止時期は定めない」を停止条件で置き換えた（supersede ではない。他の決定は有効）

<!-- constrained-by ../superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md -->

## Context

### 現状（実測 / 2026-08-14 時点）

以下の Context は決定を下した時点の調査結果であり、決定の実装（TASK-476）で
変わった箇所がある。現在の実装は下の Decision と `site/src/lib/hosts.ts` を見ること。

配布サイトは Cloudflare Worker 1 本で、本番 `befold` と staging `befold-staging` の
どちらも `workers_dev = true` のみで公開している（`site/wrangler.toml:9,51`）。
`routes` / `route` / `custom_domain` の記述は同ファイルに 1 件も無い。

独自ドメインを使わない理由は設定ファイル自身に書かれている（`site/wrangler.toml:6-8`）。

```text
# 独自ドメインは使わず、Cloudflare が用意する *.workers.dev で公開する。
# workers.dev には Cloudflare Access を設定できないため、ダッシュボードは
# Worker 側の Basic 認証（シークレット DASHBOARD_PASSWORD）で保護する。
```

DNS 管理を Cloudflare へ集約したため、この前提を見直せる状態になった。

### 移行を難しくしている制約

**出荷済みアプリの更新経路は後から変更できない。** Sparkle のフィード URL は
アプリバイナリに焼き込まれている（`BefoldApp/befold/Updates/UpdateChannel.swift`）。

| チャンネル | フィード URL |
|---|---|
| stable | `https://befold.tommy109.workers.dev/appcast.xml` |
| develop | `https://befold.tommy109.workers.dev/appcast-develop.xml` |

さらに、**過去に配信済みの appcast に埋まっている enclosure URL も変更できない**。
リリースワークフローが `https://befold.tommy109.workers.dev/dl/<tag>/` を prefix として
appcast を生成しているため（`.github/workflows/release.yml`）、既に配布された
appcast.xml の各エントリは旧ホストの `/dl/` を指している。

したがって `/appcast.xml`・`/appcast-develop.xml`・`/dl/*` の 3 経路は、
**旧ホストで無期限に同じ内容を返し続けなければならない**。

### 移行の難しさを下げている事実

- `/dl/` と `/appcast*.xml` は R2 を正として読み、無ければ GitHub Releases へ落ちる
  （`site/src/routes/public.tsx`、`site/src/lib/dist.ts`、
  `site/src/lib/github.ts`）。**どちらの経路もホスト名に依存しない**ため、
  同一 Worker が応答する限り旧ホストでも新ドメインでも同じ内容を返せる。
- サイト側の絶対 URL は原則リクエスト origin 由来で、ホスト名のハードコードは
  **ダウンロード先の定数 1 箇所だけ**（`site/src/views/shared.tsx`。当時の名前は
  `DOWNLOAD_URL`。決定 6 のとおり相対パス化して現在は `DOWNLOAD_PATH`）。canonical・og:url・
  og:image・JSON-LD・sitemap・robots.txt はすべて `new URL(c.req.url).origin` から組む
  （`site/src/routes/public.tsx`、`site/src/views/landing.tsx`、
  `site/src/views/features.tsx`）。
- Cookie・CORS・CSP にホスト名は現れない。クライアント状態は `localStorage` のみ
  （`site/src/views/shared.tsx` の `CLEANUP_SCRIPT`）。ホスト追加でセッションが壊れる箇所は無い。

### 移行で壊れる箇所

- **自己参照の除外が単一ホスト前提。** `resolveReferrer` は
  `if (host === selfHost) return null` の完全一致 1 行で判定し
  （`site/src/lib/referrer.ts`）、`selfHost` には呼び出し元がリクエストホストを
  そのまま渡す（`site/src/events.ts`）。このままホストが 2 つになると、
  旧ホスト → 新ドメインの遷移が「外部参照元」として D1 に記録される。
- **appcast のキャッシュキーがリクエスト URL 全体。** `site/src/routes/public.tsx` は
  `new URL(c.req.url).toString()` をキーにするため、ホストごとに独立したキャッシュになる。
  内容は同一なので不整合は起きないが、キャッシュ効率は 2 分割される。
- **ダッシュボード保護の前提コメントが古い。** `site/src/routes/dashboard.tsx` と
  `site/wrangler.toml:7` は「workers.dev には Access を設定できない」と書いているが、
  現在の Cloudflare ドキュメント（Workers の workers.dev ページ「Manage access to
  `workers.dev`」節）は workers.dev URL へ Access を有効化する手順を明記している。
  **この前提は現時点で誤り**である。

### 前提の裏付け

| 前提 | 裏付け |
|---|---|
| `/dl/`・appcast がホスト非依存 | コード参照（上記 file:line） |
| 絶対 URL のハードコードは 1 箇所 | 実測（`rg -n 'workers\.dev\|tommy109'` の全ヒットを用途別に分類） |
| Custom Domain と workers.dev は併存できる | ドキュメント参照（Cloudflare「workers.dev」: `routes` を書くと `workers_dev` は次回デプロイで `false` と推論される。明示指定で回避する） |
| Access はパス単位で保護できる | ドキュメント参照（Cloudflare「Access application paths」。ワイルドカードは親パスを含まない） |
| workers.dev にも Access をかけられる | ドキュメント参照（同「Manage access to `workers.dev`」） |
| 移行後の実際の DNS 疎通・Access 動作 | **未確認**。TASK-476.2 / 476.6 で実測する |

## Decision

最優先の制約は **既存ユーザーの更新経路を壊さないこと**。以下はすべてこの制約から導いた。

### 1. workers.dev ホストは恒久的に維持する（パスの選別はしない）

`workers_dev = true` を本番・staging とも明示的に書き続け、
Custom Domain を追加した後も削除しない。`routes` を書いた時点で `workers_dev` が
`false` と推論される仕様があるため、**明示指定は必須**である。

維持するのは**全パス**とし、「appcast と `/dl/` だけ維持する」形は取らない。
同一 Worker が両ホストに応答するので、パスを選別しないほうが分岐がゼロで済む。
選別は「維持すべきパスの列挙」を保守し続ける義務を生み、列挙漏れの形で破れる。

停止時期は定めない。停止できる条件は「旧ホストの appcast を叩くクライアントが
ゼロになったこと」だが、これは観測できてもゼロを保証できない。

**この段落は [ADR 0011](./0011-legacy-distribution-shutdown-conditions.md) が
更新した。** 停止条件は同 ADR の決定 4 にある。`/appcast*.xml` と `/dl/*` は
そこで別々の条件に分けられている（現行 appcast の enclosure が新ドメインだけを
指すようになり、両者が連動しなくなったため）。「ゼロを保証できない」という
上の指摘は解消されておらず、切り捨てるバージョン範囲を明示したうえで判断として
引き受ける形になっている。

観測手段は TASK-488.3 で用意した。`events.host` に応答したホストを記録し、
ダッシュボードの「配布ホストと旧経路」でホスト別の件数を人間とロボットに分けて出す
（0 件のホストも行として残すので、「まだ 0」と「計測していない」を取り違えない）。
旧ホストの HTML ページは決定 2 の 301 で送り出すため `visit` にならず、
`legacy_redirect` として別に数える。詳細は `site/README.md`。

### 2. 旧ホストからのリダイレクトは HTML ページのみ、肯定列挙で行う

旧ホストの LP（`/`）と `/features` のみ、新ドメインの同一パスへ 301 で送る。
それ以外のパスは**リダイレクトしない**。

除外条件を「appcast と `/dl/` を除く」という否定列挙では書かない。否定列挙は
新しい機械向けパスを足したときに黙って壊れる。**リダイレクトする側を列挙する**
（allow-list）ことで、列挙漏れは「リダイレクトされない」= 安全側に倒れる。

`/download` はリダイレクトしない。LP 由来のダウンロード計測（`source:'lp'`、
`site/src/routes/public.tsx`）が 301 を挟むことで別ホストの計測へ散るのを避ける。

**この列挙は TASK-496 以降、`site/src/lib/pages.ts` の `SITE_PAGES` から導出する。**
LP を言語ごとの URL（`/en`・`/en/features`）に分けたことで同じ列挙を必要とする
場所が 5 つ（ルート登録・この 301・sitemap・hreflang・`og:locale`）になり、
書き写す形では決定 2 が要求する「列挙漏れが安全側に倒れる」性質より先に、
列挙そのものが割れるため。`SITE_PAGES` に機械向けの経路（appcast・`/dl/`・
`/download`）を載せないことが、この導出が決定 2 を守り続ける条件になる。

### 3. アプリ側の appcast URL とリリースの enclosure prefix は新ドメインへ切り替える

`UpdateChannel.feedURLString` と `.github/workflows/release.yml` の
`download_url_prefix` を `https://befold.degino.com/` 基準へ変更する。

切り替えの効果は**切り替え後のバージョンを入れたユーザーにのみ**及ぶ。既存ユーザーの
アクセスは旧ホストへ永続的に残る。それでも切り替える理由は可搬性である。独自ドメインは
DNS で向き先を差し替えられるが、`*.workers.dev` は Cloudflare アカウントに固定された
ホスト名で、将来 Cloudflare 以外へ移す選択肢を塞ぐ。新規に配る分から順に依存を
移しておく。

### 4. staging も独自ドメイン配下に置く

`staging.befold.degino.com` を staging Worker の Custom Domain とする
（workers.dev も 1 と同じ理由で残す）。

staging の存在意義は「本番にしか存在しない条件を本番の前に踏むこと」であり、
その理由は設定ファイルに明記されている（`site/wrangler.toml:35-48`）。Custom Domain と
Access という**本番でだけ効く経路**を staging が持たないと、その意義が本番移行の
当日だけ空白になる。

### 5. ダッシュボードは Cloudflare Access へ移し、旧ホストでは 404 にする

- 新ドメインの `/dashboard` と `/dashboard/*` を Access の self-hosted アプリケーションで
  保護する。ワイルドカードは親パスを含まないため、**2 本の指定が必要**。
- Worker 側は Access の JWT（`Cf-Access-Jwt-Assertion`）を検証する。Access を張っても
  Worker が素通しでは、経路を迂回された場合に無防備になる。
- **旧ホストの `/dashboard` は 404 を返す。** workers.dev にも Access はかけられるが、
  保護面を 2 つ持つと片方だけ設定が抜ける形で破れる。ダッシュボードは新ドメイン専用とし、
  保護面を 1 つに畳む。
- Basic 認証（`site/src/routes/dashboard.tsx`）は Access の動作を実測で確認するまで
  残し、確認後に削除する。`DASHBOARD_PASSWORD` シークレットも同時に削除する。

### 6. 自己参照の除外を「単一ホスト」から「自己ホスト集合」へ変える

`resolveReferrer` の第 3 引数を単一の `selfHost` 文字列から**自己ホストの集合**へ変える。
集合には本番の新旧 2 ホストと staging の新旧 2 ホストを入れる。

リクエストホストを渡す現在の形（`site/src/events.ts`）だけでは残さない。残すと
「いま来ているホスト以外の自ホスト」を除外できず、新旧ホスト間の遷移が
外部参照元として記録される。集合は `site/src/lib` の定数として 1 箇所に置く。
ホスト名リテラルがコード中に散ると、次にホストが増えたときに片側だけ直る。

**ダウンロード先の定数（`site/src/views/shared.tsx`）は相対パス `/download` にする。**
（実装では `DOWNLOAD_URL` を `DOWNLOAD_PATH` に改名した。）
当初この節は「正規オリジンの定数から組む」と書いていたが、これは誤りだったので
訂正する。使用箇所は 5 つで、4 つは `<a href>`（`site/src/views/landing.tsx`、
`site/src/views/features.tsx`）、1 つは JSON-LD の `downloadUrl`
（`site/src/views/landing.tsx`）。`<a href="/download">` はブラウザが表示中の文書の
オリジンに対して解決するため、相対パスにするだけで「開いたホストの `/download`」に
なる。正規オリジンの定数から組むと、staging の LP のダウンロードボタンが本番を指し、
staging で download 経路と `source:'lp'` の計測を確かめられなくなる。これは
staging の存在意義（`site/wrangler.toml:35-48`）と衝突する。

この節の理由は「ホスト名リテラルを散らさない」ことであり、相対パスはリテラルを
1 つも残さないのでその理由をより強く満たす。ホスト判定の分岐を新設する案は
採らない（述語を増やさずに同じ結果が得られる）。絶対 URL が要る JSON-LD だけは、
canonical・og:url・sitemap と同じくリクエスト origin から組む。

## Consequences

### 得るもの

- 配布 URL がアカウント名を含まない形（`befold.degino.com`）になり、将来の移設で
  DNS の向き先変更だけで済む。
- ダッシュボードが Access の認証（SSO・多要素・デバイス条件）で保護され、
  共有パスワードの管理が不要になる。
- staging が本番と同じ経路構成になり、Custom Domain / Access 固有の問題を
  本番より前に踏める。

### 受け入れるコスト

- **旧ホストは無期限に生き続ける。** Worker のルーティングは常に 2 ホストを想定した
  ものになり、テストもホスト非依存であることを前提に書く必要がある。
- appcast のキャッシュがホストごとに分かれる（`site/src/routes/public.tsx`）。
  内容は同一なのでユーザーへの影響は無いが、オリジンへの到達回数は増える。
- 計測データに移行前後の断層が残る。参照元の集計（`site/src/analytics.ts` の
  `breakdown(db,'referrer')`）は、自己ホスト集合を入れる前に記録された旧ホスト →
  新ドメインの遷移を外部参照元として含みうる。移行と同じデプロイで 6 を入れ、
  断層が生じない順序にする。
- 301 を追わないクライアントが旧ホストの LP を見た場合、ダウンロードボタンは
  旧ホストの `/download` に留まる（相対パスのため）。これは決定 2 で
  `/download` をリダイレクト対象から外した意図と同じ向きで、`source:'lp'` の
  計測は従来どおり記録される。
- ホスト名を固定値で期待しているテストの更新が必要になる
  （`site/test/public.test.ts`、`site/test/referrer.test.ts`、
  `BefoldApp/befoldTests/AppLinksTests.swift`、
  `BefoldApp/befoldTests/UpdateChannelTests.swift`）。

### 破れたら落ちるもの

決定は文章だけでは守られないため、次を実装側に用意する。

| 決定 | 担保 |
|---|---|
| 1（旧ホスト維持） | `site/wrangler.toml` に `workers_dev = true` が残ることを検査する。`routes` を足したデプロイで消えるのが既定挙動のため、設定の存在をテストで固定する |
| 2（肯定列挙のリダイレクト） | 旧ホストの `/appcast.xml`・`/appcast-develop.xml`・`/dl/<tag>/<file>` が 200 を返す（301 ではない）ことのテスト |
| 5（保護面は 1 つ） | 旧ホストの `/dashboard` が 404 を返すテスト。Access JWT 未提示で新ドメインの `/dashboard` が通らないことの実測 |
| 6（自己ホスト集合） | `resolveReferrer` の引数型を集合にする（単一文字列を渡せない形にし、呼び出し側がリクエストホストを渡す旧実装へ戻れないようにする）。新旧ホスト間の遷移が `null` になるテスト |

## 未確定事項

この ADR で決めていないこと。後続タスクで決める。

- 旧ホストの LP を 301 にした場合の検索インデックスの移行速度。実測してから
  canonical の扱いを再検討する余地がある（TASK-476.3）。
- Access のポリシー内容（許可する識別子・セッション長）。TASK-476.6 で決める。
- `docs/index.html` の GitHub Pages リダイレクト shim を新ドメインへ向け直すか、
  この機会に撤去するか（TASK-476.5）。
