---
id: TASK-395
title: 本番 D1 への解析クエリを読み取り専用に制限する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-09 13:33'
updated_date: '2026-08-10 01:19'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 649000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
解析データを実データで確認する経路として wrangler の d1 execute --remote が使える（2026-08-09 に実行して確認済み）。ただし現在の wrangler トークンは d1 (write) 権限を持っており、同じ経路で本番 events テーブルへの UPDATE / DELETE / DROP も通る。読み取りしか行わないのは運用者側の自制であって、仕組みによる担保がない。

エージェント（Claude）に解析データを見せながら戦略を検討する運用を続けるなら、書き込みを構造的に不可能にしておく。破壊操作の可能性を残したまま自動化を増やすと、events は追記のみで復元手段がないため（バックアップ運用は現在なし）、一度の事故で計測データを全損する。

前提と裏付け:
- 実測: npx wrangler whoami の Token Permissions に 'd1 (write)' が含まれる。アカウントは Tokutomi@degino.com's Account（96b3602a71be49f99732550f9f3dedad）1 つ。
- 実測: (cd site && npx wrangler d1 execute befold-analytics --remote --command 'SELECT ...') が本番 D1 に対して成功する。
- コード参照: 対象 DB は site/wrangler.toml の d1_databases（本番 befold-analytics / staging befold-analytics-staging）。
- 未確認: Cloudflare の API トークンで D1 に読み取り専用スコープを付けられるかは実測していない（D1 の権限が Read / Edit の粒度で分かれているかを Cloudflare ダッシュボードの API Tokens 画面で確認する）。分けられない場合は .claude/settings.json の permissions 側で担保する。
- 選択肢: (a) 読み取り専用 API トークンを発行し、解析用途はそれを使う、(b) .claude/settings.json の permissions で wrangler d1 execute を確認付き（または SELECT で始まるコマンドのみ許可）にする、(c) 両方。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 本番 D1 に対する解析用途のクエリ経路が、書き込み（UPDATE / DELETE / DROP / INSERT）を実行できない形になっている
- [x] #2 その制限が仕組みで担保されている（運用上の約束や文書だけではない）
- [x] #3 採用した方式と、検討して採らなかった方式の理由が Implementation Notes に記録されている
- [x] #4 解析クエリを実行する手順（どのトークン・どのコマンドを使うか）が README または docs に記載され、次回のセッションが手順を再発見しなくてよい
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 前提確認: Cloudflare の API トークン権限に Account / D1 / Read が存在することを docs で確認済み（fundamentals/api/reference/permissions）。現在の wrangler 認証は OAuth（d1 write 込み）で、デプロイに write が要るため単一認証の降格はできない。読み取り用は別トークンに分ける。
2. 単純化検討: 経路を増やさず「本番 D1 を読む経路を 1 本の入口へ畳む」形にする。専用ラッパ scripts/analytics-query.sh を唯一の入口とし、(a) 読み取り専用トークン必須、(b) SQL を読み取り形にのみ限定、の 2 段で担保する。
3. scripts/analytics-query.sh を追加する。CLOUDFLARE_D1_READONLY_TOKEN 未設定なら実行を拒否（任意ではなく必須にして「破れない構造」にする）。SQL は SELECT/WITH 始まり・複文なし・PRAGMA/ATTACH 等の除外で検査。--self-test を用意する。
4. .claude/settings.json に PreToolUse(Bash) フックを追加し、ラッパ以外の 'd1 execute' を含むコマンドを exit 2 で落とす。permissions allow に scripts/analytics-query.sh を追加する。
5. site/README.md に「本番の解析データを読む」節を追加。読み取り専用トークンの作成手順（Account / D1 / Read のみ）、env の渡し方、実行コマンドを記載する。
6. 実測で検証: --self-test、フックが破壊コマンドを落とすこと、ラッパ経由の SELECT が本番で通ること（トークン作成後）。トークン発行はダッシュボード操作のためユーザーに依頼し、実測結果を Notes に記録する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
採用: 読み取り専用 API トークン（Account / D1 / Read）を必須にした専用ラッパ scripts/analytics-query.sh を唯一の入口にし、迂回は .claude/settings.json の PreToolUse フックで落とす（選択肢 (c) 両方に相当）。

3 段の担保:
1. 認証 — CLOUDFLARE_D1_READONLY_TOKEN 未設定なら実行を拒否する。手元の wrangler OAuth（d1 write 込み）は流用しない。Cloudflare 側で書き込みが弾かれる唯一の段。
2. 文面 — 単一の SELECT / WITH 文だけを許可し、複文・PRAGMA / ATTACH・書き込みを伴う CTE を弾く。--self-test で判定自体を検査（許可 3 件・拒否 8 件）。
3. 経路 — PreToolUse(Bash) フックが 'd1 execute' を含むコマンドを、ラッパ経由でない限り exit 2 で落とす。d1 migrations apply / npm run migrate:remote は対象外（適用は別経路）。

採らなかった案と理由:
- トークンだけ（選択肢 a）— 発行後も直接 wrangler を叩く癖が残り、write を持つ OAuth 認証が同じ端末にある以上、経路が 2 本のままになる。
- permissions の allow/deny だけ（選択肢 b）— deny はコマンド前置き一致のため 'cd site && npx wrangler ...' の複合コマンドで容易に外れる。実測でもフックなら複合形を落とせることを確認したので、フック側に寄せた。
- SELECT のみ許可する permissions 表現 — SQL は引数の中の文字列であり、permissions のパターンでは中身を検査できない。

実測（このセッション）:
- scripts/analytics-query.sh --self-test → OK（許可 3 / 拒否 8）
- フックへ 5 パターンを流して判定を確認: 直接の DELETE / 直接の SELECT は BLOCK、ラッパ経由・npm run migrate:remote・d1 migrations apply は allow
- トークン未設定時に、ネットワークへ出る前に拒否されることを確認
- Cloudflare docs で Account / D1 / Read 権限の存在を確認（fundamentals/api/reference/permissions）

未確認: D1 Read だけのトークンで wrangler d1 execute --remote の SELECT が通るか（同 API は POST /query を使うため、Read で許可されるかを実測していない）。トークン発行はダッシュボード操作のためユーザー依頼待ち。通らない場合は経路を D1 REST の read 系エンドポイントまたは Worker 側の read-only API へ切り替える。

追加の実測（トークン待ちの間に確認できた分）:
- 不正なトークンを渡して経路を実測。POST /accounts/96b3602a.../d1/database/5b7d03ff.../query に到達し 'Authentication error [code: 10000]' で失敗した。すなわち (a) アカウント ID とデータベース ID の解決は正しい、(b) 渡したトークンが実際の認証に使われ、OAuth へフォールバックしない——手元の write 権限が暗黙に流用される経路が無いことが確認できた。
- 残る未確認は 1 点のみ: Account / D1 / Read だけのトークンがこの /query エンドポイント（POST）で許可されるか。Cloudflare docs は D1 Read / D1 Edit の存在は明記するが、/query がどちらに属するかは記載していない。実トークンでの 1 回の SELECT でしか判定できない。
- トークン受け渡しは Keychain（security add-generic-password -s befold-d1-readonly）を第一手段にした。会話ログ・シェル履歴にトークン文字列を残さずに済む。環境変数 CLOUDFLARE_D1_READONLY_TOKEN も引き続き使える。

検証（AC #1 / #2 の根拠、実測）:
- ラッパ経由の書き込み 4 種（UPDATE / DELETE / DROP / INSERT）はいずれも rc=1 でネットワークへ出る前に拒否される。
- PreToolUse フックは --command 形・--file 形・複合コマンド（cd site && ...）いずれも BLOCK する。
- scripts/check-analytics-query-guard.sh が pre-commit に入っており、判定を緩めるとコミットが落ちる。
- 不正トークンでの実測により、ラッパは渡されたトークンのみを認証に使い OAuth へフォールバックしないことを確認済み（Authentication error [code: 10000]）。

残る弱点（意図的に残した範囲）:
読み取り専用トークンをまだ発行していないため、「Cloudflare 側で write が 403 になる」段だけが未導入。エージェント経路（Bash ツール）はフックで塞がっているが、人間がターミナルで直接 wrangler を叩く経路は依然 OAuth の d1 (write) を使える。この段の導入と、D1 Read だけで POST /query が通るかの実測は TASK-402 へ送った。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
本番／staging の解析 D1 を読む経路を scripts/analytics-query.sh の 1 本へ畳み、書き込みを 3 段で塞いだ。(1) 認証: 読み取り専用トークンを必須にし、手元の OAuth（d1 write 込み）を流用しない。(2) 文面: 単一の SELECT / WITH 文だけを許可し、複文・PRAGMA / ATTACH・書き込みを伴う CTE を弾く。(3) 経路: PreToolUse フックがラッパを経由しない d1 execute を落とす。ガードが緩められたら pre-commit の check-analytics-query-guard.sh が落ちる。

実測: ラッパ経由の UPDATE / DELETE / DROP / INSERT は 4 件ともネットワーク到達前に rc=1 で拒否。フックは --command 形・--file 形・複合コマンドを BLOCK し、d1 migrations apply / npm run migrate:remote は通す。self-test は許可 3 件・拒否 8 件で期待どおり。不正トークンでの実測により、ラッパが渡されたトークンのみを認証に使い OAuth へフォールバックしないことを確認（Authentication error [code: 10000]）。手順は site/README.md「本番の解析データを読む」に記載。

残: 読み取り専用トークンの発行（ダッシュボード操作）と、D1 Read だけで POST /query が通るかの実測は TASK-402 へ分離した。人間がターミナルで直接 wrangler を叩く経路は、それが入るまで write 認証を使える。
<!-- SECTION:FINAL_SUMMARY:END -->
