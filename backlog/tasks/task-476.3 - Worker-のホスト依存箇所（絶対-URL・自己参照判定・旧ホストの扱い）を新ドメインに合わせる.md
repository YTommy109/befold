---
id: TASK-476.3
title: Worker のホスト依存箇所（絶対 URL・自己参照判定・旧ホストの扱い）を新ドメインに合わせる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-13 14:21'
updated_date: '2026-08-14 06:54'
labels:
  - site
dependencies:
  - TASK-476.1
parent_task_id: TASK-476
priority: high
type: chore
ordinal: 101300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Worker のコードには、単一ホスト前提の箇所と旧ホストをハードコードした箇所が残っている。ADR 0007 の決定 2 / 決定 6 の実装。

<!-- constrained-by ../../docs/adr/0007-distribution-site-custom-domain.md -->

対象（実測）:
- `site/src/views/shared.tsx:13` `DOWNLOAD_URL = https://befold.tommy109.workers.dev/download` — site 側で唯一のハードコード絶対 URL。**正規オリジンの定数から組む形へ変える**（ADR 0007 の決定 6。ホスト名リテラルをコード中に散らさない）。
- `site/src/lib/referrer.ts:44` `if (host === selfHost)` — 自己ホストが 1 つ前提。呼び出し元（`site/src/events.ts:46-50`）はリクエストホストを渡している。**引数型を自己ホスト集合へ変え、単一文字列を渡せない形にする**。集合には本番・staging の新旧 4 ホストを入れる。集合と正規オリジンは `site/src/lib` の同じ定数から引く。
- 旧ホストのリダイレクトは **LP（`/`）と `/features` のみを対象とする肯定列挙**で実装する（ADR 0007 の決定 2）。「appcast と /dl/ を除く」という否定列挙は取らない — 新しい機械向けパスを足したときに黙って壊れる。
- `/download` はリダイレクトしない。LP 由来のダウンロード計測（`source:"lp"`、`site/src/routes/public.tsx:42-55`）が 301 を挟んで別ホストへ散るのを避ける。
- canonical / og:url / JSON-LD / robots / sitemap（`site/src/views/landing.tsx`, `features.tsx`, `src/routes/public.tsx:106-128`）はリクエスト origin 由来。旧ホストの HTML ルートを 301 で送ることで重複コンテンツを解消するため、origin 由来のままでよい（staging で正しく動く性質を壊さない）。

注意:
- 決定 6 は移行と同じデプロイに入れる。後回しにすると、その間の新旧ホスト間の遷移が外部参照元として D1 に記録され、参照元の集計（`site/src/analytics.ts:424`）に断層が残る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ダウンロードリンクが配信ホストに依存せず、新旧どちらのホストで開いても同一ホスト内の /download を指す
- [x] #2 resolveReferrer の引数が自己ホスト集合になっており、単一ホスト文字列を渡す旧実装へ戻せない形になっている
- [x] #3 新旧ホスト間の遷移が参照元として記録されない（本番・staging の新旧 4 ホストをユニットテストで検証）
- [x] #4 旧ホストで /appcast.xml・/appcast-develop.xml・/dl/... が 301 ではなく 200 を返すことをテストで担保している
- [x] #5 旧ホストのリダイレクトが対象パスの肯定列挙で実装されており、列挙外のパスはリダイレクトされない
- [x] #6 旧ホストの /download がリダイレクトされず、source:"lp" の計測が従来どおり記録される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. site/src/lib/hosts.ts を新設し、本番・staging の新旧 4 ホストと、旧ホスト→新ホストの対応、301 対象パスの肯定列挙をここ 1 箇所に置く
2. resolveReferrer の第 3 引数を ReadonlySet<string> にする（単一文字列は型エラーになり、旧実装へ戻せない）。events.ts は SELF_HOSTS に「いま来ているリクエストホスト」を足した集合を渡す（localhost / preview URL での自己遷移除外を壊さないため）
3. DOWNLOAD_URL を相対パス /download にする。JSON-LD の downloadUrl だけは絶対 URL が要るので、structuredData が既に受け取っている origin から組む（ADR 決定 6 は訂正済み）
4. 旧ホストからの 301 を index.ts のミドルウェアとして置く。対象は / と /features の肯定列挙のみ。列挙外は素通しで、appcast・/dl/・/download・/healthz は 200 のまま
5. テスト: (a) 新旧 4 ホスト間の遷移が resolveReferrer で null、(b) 単一文字列を渡せない型であること、(c) 旧ホストの /appcast.xml・/appcast-develop.xml・/dl/... が 301 ではなく 200、(d) 旧ホストの /download がリダイレクトされず source:'lp' が記録される、(e) 列挙外パスがリダイレクトされない、(f) ダウンロードリンクが新旧どちらのホストでも同一ホスト内を指す
6. 既存テストのホスト固定値（test/referrer.test.ts:4、test/public.test.ts:85,458）を更新する

## 設計レビュー（/review-design）の結果

- 項目 3（消費経路と兄弟判断の全列挙）: 自己ホスト判定をしている箇所は resolveReferrer だけで兄弟なし（実測 grep）。site/src 内のホスト名リテラルは shared.tsx:13 の 1 箇所だけ（実測）
- 項目 1（判定の真実の源）: 301 判定はリクエストの host と pathname という事実で行う。肯定列挙なので /features/ のような末尾スラッシュ違いは素通し（安全側に倒れる）
- 項目 5（順序）: 旧ホストの / が 301 になるため visit はリダイレクト後の新ドメインで 1 回だけ記録される。二重計上はしない。**未確認**: 301 の際にブラウザが元の外部サイトの Referer を引き継ぐ前提に乗っている（ブラウザ差がありうる）
- 項目 7（測るものと守るもの）: resolveReferrer 単体テストだけだと events.ts の結線漏れを検知できないため、Referer を旧ホストにして / を叩き D1 の referrer が null になる結合テストも置く
- 項目 9（決めた粒度を守らせるもの）: SELF_HOSTS に 4 ホストが入っていることと、列挙外パスがリダイレクトされないことをテストで固定する
- 項目 2/4/6/8/10 は非該当: 既存の不変条件を迂回しない / 新しいユーザー向け状態を作らない（301 は機械向け）/ ミドルウェアは Set.has 2 回で高頻度経路のコストにならない / 非同期で置き換わる表示状態を足さない / Swift ではないため型グループ行数の規定の対象外
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 変更したもの

- `site/src/lib/hosts.ts`（新規）: 本番・staging の新旧 4 ホスト、旧→新の対応表、301 対象パスの肯定列挙、`selfHostsFor` を 1 箇所に置いた
- `site/src/lib/referrer.ts`: 第 3 引数を `selfHost: string` → `selfHosts: ReadonlySet<string>` に変更
- `site/src/events.ts`: `selfHostsFor(new URL(c.req.url).host)` を渡す（既知 4 ホスト + リクエストホスト）
- `site/src/views/shared.tsx`: `DOWNLOAD_URL`（絶対 URL）→ `DOWNLOAD_PATH = '/download'`。`landing.tsx` / `features.tsx` の 4 箇所の `<a href>` が相対に、JSON-LD の `downloadUrl` は `${origin}${DOWNLOAD_PATH}` になった
- `site/src/index.ts`: 旧ホストの `/` と `/features` だけを新ドメインへ 301 するミドルウェアをルート登録より前に追加
- `docs/adr/0007-distribution-site-custom-domain.md`: 決定 6 の `DOWNLOAD_URL` の記述を訂正

## ADR 決定 6 の訂正について

決定 6 は「`DOWNLOAD_URL` が使う正規オリジンも同じ定数から組む」と書いていたが、これは誤りだったのでユーザー確認のうえ訂正した。

理由: 使用箇所 5 つのうち 4 つは `<a href>` で、ブラウザが表示中の文書のオリジンに対して解決するため相対パスで足りる。正規オリジンを固定すると staging の LP のダウンロードボタンが本番を指し、staging で download 経路と `source:'lp'` の計測を確かめられなくなる（`site/wrangler.toml:35-48` が書いている staging の存在意義と衝突する）。決定 6 の理由は「ホスト名リテラルを散らさない」ことで、相対パスはリテラルを 1 つも残さないのでその理由をより強く満たす。ホスト判定の分岐を新設する案は、述語を増やさずに同じ結果が得られるため採らなかった。

## 設計レビュー（/review-design）で拾えたもの

- 項目 3: 自己ホスト判定の兄弟箇所は無い（`resolveReferrer` のみ）、`site/src` 内のホスト名リテラルは `shared.tsx:13` のみ ← 実測 grep
- 項目 7: `resolveReferrer` の単体テストだけでは `events.ts` の結線漏れを検知できないため、実リクエスト経由の結合テストを足した。実際、`events.ts` をリクエストホストのみに戻すとこのテストだけが落ちることを確認した
- 項目 9: 肯定列挙が否定列挙へ退化したときに落ちるテストを置いた。否定列挙版に書き換えると「列挙外のパスはリダイレクトしない」が落ちることを確認した

## 実測

- `npm run typecheck` 通過、`npm test` 10 ファイル 174 件パス（変更前は 145 件）
- AC #2 の担保は型で効いている: 既存テストが単一文字列を渡したまま `tsc` を通すと `TS2345: Argument of type 'string' is not assignable to parameter of type 'ReadonlySet<string>'` が 10 箇所出た
- 担保が空振りしていないことの確認（修正を戻して落ちるか）:
  - `events.ts` を `new Set([リクエストホスト])` に戻す → 「旧ホストからの遷移は参照元として記録しない」が落ちる
  - 301 判定を否定列挙に書き換える → 「列挙外のパスはリダイレクトしない（肯定列挙であることの担保）」が落ちる
- staging へデプロイして実機確認（`npx wrangler deploy --env staging`、version `ef3594c7`）:

| URL | 結果 |
|---|---|
| `befold-staging.tommy109.workers.dev/` | 301 → `https://staging.befold.degino.com/` |
| `befold-staging.tommy109.workers.dev/features` | 301 → `https://staging.befold.degino.com/features` |
| 同 `/appcast.xml` `/download` `/healthz` `/robots.txt` | いずれも 200（301 されない） |
| `staging.befold.degino.com/` の LP | `href="/download"`（絶対 URL は現れない） |
| 同 JSON-LD | `"downloadUrl":"https://staging.befold.degino.com/download"` |
| 同 canonical | `https://staging.befold.degino.com/` |

staging の旧ホストが本番ではなく staging の新ドメインへ送られている（対応表が効いている）。

## 未確認 / 申し送り

- **301 のとき、ブラウザが元の外部サイトの `Referer` を引き継ぐ**という前提に乗っている。引き継がれない実装があると、旧ホスト経由の流入の参照元が失われる（`?ref=` は 301 先へ引き継ぐようにしたので、そちらは影響しない）。実測していない。
- **本番へは未デプロイ。** ADR 決定 6 は「移行と同じデプロイで入れて断層を作らない」としているが、TASK-476.2 のデプロイが先行したため、本番では現在このデプロイまでの間だけ旧ホスト → 新ドメインの遷移が外部参照元として記録されうる。本番デプロイの実施タイミングはユーザー判断待ち。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ホスト名の定義を site/src/lib/hosts.ts に集約し、Worker の単一ホスト前提を解いた。resolveReferrer の第 3 引数を ReadonlySet<string> にして単一ホスト文字列を渡せない形にし（既存テストが tsc で 10 箇所の TS2345 になったことで確認）、新旧 4 ホストの全組み合わせと events.ts 経由の結合テストで遷移が参照元として記録されないことを担保した。DOWNLOAD_URL は相対パスにして配信ホストに依存しない形にし、絶対 URL が要る JSON-LD だけリクエスト origin から組む。旧ホストの 301 は / と /features の肯定列挙で実装し、appcast・/dl/・/download・列挙外パスが 301 されないことをテストで固定した。担保が空振りしていないことは、events.ts をリクエストホストのみに戻すと結合テストが落ち、301 判定を否定列挙に書き換えると列挙テストが落ちることで確認した。typecheck 通過、テスト 174 件パス。staging へデプロイして旧ホストの 301・新ドメインの相対リンク・JSON-LD の origin 由来を実機で確認した。ADR 決定 6 の DOWNLOAD_URL に関する記述は誤りだったのでユーザー確認のうえ訂正した。
<!-- SECTION:FINAL_SUMMARY:END -->
