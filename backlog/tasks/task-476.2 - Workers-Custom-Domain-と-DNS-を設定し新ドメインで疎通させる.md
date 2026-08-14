---
id: TASK-476.2
title: Workers Custom Domain と DNS を設定し新ドメインで疎通させる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-13 14:20'
updated_date: '2026-08-14 06:32'
labels:
  - site
dependencies:
  - TASK-476.1
parent_task_id: TASK-476
priority: high
type: chore
ordinal: 101200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cloudflare の degino.com ゾーンに `befold.degino.com` と `staging.befold.degino.com` の Workers Custom Domain を設定し、`site/wrangler.toml` に routes を記述する。ホスト名は ADR 0007 の決定 4 で確定済み。

<!-- constrained-by ../../docs/adr/0007-distribution-site-custom-domain.md -->

注意点:
- Custom Domain 設定時に DNS レコードは Cloudflare 側が自動作成する。既存の degino.com の他レコードを壊さないこと。
- **`workers_dev = true` を本番・staging とも明示的に残す。** routes を書くと `workers_dev` は次回デプロイで `false` と推論される仕様があるため（Cloudflare「workers.dev」ドキュメント）、明示指定しないと旧ホストが落ちる。旧ホストが落ちると出荷済みアプリの更新チェックが止まる（ADR 0007 の決定 1）。
- assets / d1_databases / observability は環境非継承キー。staging 側に routes を足すときも既存の再指定を崩さない。
- `site/wrangler.toml:6-8` と `site/src/routes/dashboard.tsx:16` のコメントは「workers.dev には Access を設定できない」と書いているが、これは現在の Cloudflare ドキュメントに照らして誤り。書き換える際に事実を訂正すること（保護面を 1 つに畳む判断そのものは ADR 0007 の決定 5 のとおり変えない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 https://befold.degino.com/ で LP が表示され、/appcast.xml と /download が本番と同じ内容を返す
- [x] #2 旧 https://befold.tommy109.workers.dev/appcast.xml が引き続き 200 を返す
- [x] #3 staging が https://staging.befold.degino.com で公開され、site-staging ワークフローの出力 URL が実際の公開先と一致している
- [x] #4 routes 追加後のデプロイでも本番・staging の workers.dev ホストが生きていることを実測で確認している
- [x] #5 site/wrangler.toml のコメントが現状に合わせて書き換えられ、workers.dev に Access を張れないという誤った記述が残っていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. degino.com ゾーンの既存 DNS レコードを実測し、befold 系が未使用であることを確認する
2. site/wrangler.toml に本番 [[routes]]（befold.degino.com / custom_domain）と staging [[env.staging.routes]]（staging.befold.degino.com）を追加し、workers_dev = true を両方に明示のまま残す
3. workers.dev に Access を張れないという誤ったコメントを wrangler.toml と src/routes/dashboard.tsx から取り除き、ADR 0007 の決定 5 に合わせて書き直す
4. ADR 0007 の決定 1 の担保として、wrangler.toml 本文をバインディング経由でテストへ渡し、workers_dev と routes の記述を固定するテストを追加する（消したら落ちることを実測で確認）
5. 本番・staging をデプロイして Custom Domain を作成し、新旧 4 ホストの疎通を curl で実測する
6. site-staging.yml の出力 URL を実際の公開先に合わせる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 変更したもの

- `site/wrangler.toml`: 本番 `[[routes]] pattern = "befold.degino.com" / custom_domain = true`、staging `[[env.staging.routes]] pattern = "staging.befold.degino.com"` を追加。`workers_dev = true` は両方に明示のまま残した
- `site/src/routes/dashboard.tsx`: 「workers.dev には Access を設定できない」という誤ったコメントを訂正（旧ホストで Access を張らないのは保護面を 1 つに畳む判断であって技術的制約ではない、と書き直した）
- `site/test/wrangler-config.test.ts`（新規）+ `vitest.config.ts` / `test/env.d.ts`: wrangler.toml 本文をバインディングで渡し、workers_dev と routes の記述を固定するテストを追加
- `.github/workflows/site-staging.yml`: 出力 URL に staging.befold.degino.com を追加

## 実測

デプロイ: `npx wrangler deploy` / `npx wrangler deploy --env staging`。どちらも出力に workers.dev と custom domain の両方が並んだ。

HTTP ステータス（curl）:

| URL | 結果 |
|---|---|
| https://befold.degino.com/ | 200 |
| https://befold.degino.com/appcast.xml | 200（旧ホストと `diff` で内容一致） |
| https://befold.degino.com/download | 200 |
| https://befold.degino.com/appcast-develop.xml | 200 |
| https://befold.tommy109.workers.dev/ | 200 |
| https://befold.tommy109.workers.dev/appcast.xml | 200 |
| https://befold.tommy109.workers.dev/appcast-develop.xml | 200 |
| https://befold.tommy109.workers.dev/dl/v1.12.3/befold-v1.12.3.dmg | 200 |
| https://staging.befold.degino.com/ , /appcast.xml , /download | 200 |
| https://staging.befold.degino.com/dashboard | 401（Basic 認証。移行前の想定どおり） |
| https://befold-staging.tommy109.workers.dev/ | 200 |

workers.dev が生きていることは HTTP に加え API でも確認した。`GET /accounts/{id}/workers/scripts/{befold,befold-staging}/subdomain` がどちらも `enabled: true`。

DNS: degino.com ゾーン（`27bb9209...`）に `befold.degino.com` と `staging.befold.degino.com` の AAAA（proxied）が Cloudflare によって自動作成された。デプロイ前に既存レコードを一覧して befold 系が未使用であることを確認しており、既存の CNAME（GitLab Pages）・MX・SPF/DKIM/DMARC・www は変更していない。

テスト: `npm run typecheck` 通過、`npm test` で 10 ファイル 145 件パス。追加したテストは、`workers_dev = true` を外すと落ちることを実測で確認済み（担保が空振りしていないことの確認）。

## 詰まった点

`staging.befold.degino.com` は 2 階層下のサブドメインで Universal SSL（`*.degino.com`）の対象外のため、Custom Domain 作成時に advanced 証明書パックが自動発行される。発行完了までの数分間は TLS ハンドシェイクが失敗する（`befold.degino.com` は Universal SSL に含まれるので即座に 200 だった）。証明書が active になった後は上表のとおり。

なお作業マシンの mDNSResponder に `staging.befold.degino.com` の NXDOMAIN が残り、`host`/`dig` は解決するのに `curl`（getaddrinfo）だけが解決できない状態が続いた。ネガティブキャッシュの期限切れ待ちで、サーバ側の問題ではない。上表の staging の測定は `curl --resolve` で行った。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
site/wrangler.toml に本番 befold.degino.com と staging staging.befold.degino.com の Workers Custom Domain を追加し、両環境をデプロイして Cloudflare 側に DNS レコードと証明書を作成した。workers_dev = true は routes 追加後も両環境で明示のまま残し、旧ホストの / ・/appcast.xml ・/appcast-develop.xml ・/dl/<tag>/<file> が 200 を返すことと、workers subdomain API が enabled: true を返すことを実測で確認した。新旧の appcast は diff で内容一致。ADR 0007 の決定 1 が次のデプロイで黙って破れないよう、wrangler.toml の記述を固定するテストを追加し、workers_dev を外すと落ちることも実測した。あわせて「workers.dev には Access を設定できない」という誤ったコメントを wrangler.toml と dashboard.tsx から取り除き、site-staging.yml の出力 URL を実際の公開先に合わせた。
<!-- SECTION:FINAL_SUMMARY:END -->
