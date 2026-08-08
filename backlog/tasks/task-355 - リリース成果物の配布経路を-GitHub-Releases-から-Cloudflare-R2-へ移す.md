---
id: TASK-355
title: リリース成果物の配布経路を GitHub Releases から Cloudflare R2 へ移す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 01:21'
updated_date: '2026-08-08 09:43'
labels: []
dependencies: []
priority: medium
ordinal: 614000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
直販（Mac App Store を使わない配布）を前提に、リリース成果物と Sparkle の appcast.xml の配信先を GitHub Releases から Cloudflare R2 + Workers へ移す。

背景・狙い:
- 現状の最大のボトルネックは認知とダウンロード数であり、まず「ダウンロード数を正確に測れる」状態にしたい。GitHub Releases では取得できる情報が限られる。
- 将来的にライセンスキー配布や有料版の配信制御を Workers + D1/KV で行う余地を残す。本タスクでは課金・ライセンス層は扱わない（配信経路の移設のみ）。
- Mac App Store は App Sandbox 必須・Sparkle 不可・CLI 配布不可のため採用しない方針。直販なら Sparkle と befold-cli をそのまま維持できる。

前提（未検証。着手時に確認すること）:
- ビルド・署名・公証は macOS が必須のため CI は GitHub Actions の macos runner のままとする。Cloudflare Workers Builds は Worker 用の CI であり xcodebuild は動かない。
- 変更範囲はリリースワークフローの「アップロード先」であり、ビルド・署名・公証の手順自体は変えない想定。
- Sparkle は appcast.xml を HTTPS で取得し EdDSA 署名を検証してから成果物を取得するため、配信元が R2 でも動作するはず。

制約:
- 署名鍵（Sparkle の EdDSA 秘密鍵、Developer ID 証明書）は Cloudflare 側に置かない。署名は GitHub Actions 上で行い、R2 には署名済み成果物のみを配置する。
- 移行期間中は既存ユーザの自動アップデートを壊さないこと（既存の appcast URL からの導線を維持する）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 リリースワークフローが署名・公証済みの DMG と appcast.xml を Cloudflare R2 へアップロードする（R2 への put 失敗はジョブ失敗として扱う）
- [x] #2 appcast の enclosure が Worker 経由の R2 配信 URL になった状態で、dev ビルドの旧バージョンから新バージョンへの Sparkle 自動アップデートが EdDSA 検証を通って実機で成功する
- [x] #3 v1.10.0 以前の配布済みバージョンが参照する GitHub 直の appcast URL が更新され続け、自動アップデートが壊れない
- [x] #4 ダウンロード数を確認できる手段が用意されている
- [x] #5 LP 経由のダウンロードと Sparkle の自動更新ダウンロードがダッシュボードで区別して集計される
- [x] #6 Sparkle の EdDSA 秘密鍵と Developer ID 証明書が Cloudflare 側に配置されていない（CI の Cloudflare トークンは R2 書き込みのみのスコープ）
- [x] #7 /dl のパス検証により、R2 バケット内の DMG 以外のオブジェクトが読み出せないことをテストで担保する
- [x] #8 配布手順の変更が docs 配下のリリース手順と配布設計書に反映されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. R2 バケット befold-dist / befold-dist-staging を作成し、site/wrangler.toml に r2_buckets バインディング DIST を本番・staging 双方へ追加する（非継承キーのため env.staging にも再指定）。
2. release.yml に R2 アップロード手順を追加する。GitHub Releases への添付（softprops/action-gh-release, gh release upload appcast）は残したまま併存させる。
   - DMG: R2 キー releases/<tag>/befold-<tag>.dmg
   - appcast: R2 キー appcast.xml / appcast-develop.xml
   - stable リリース時のみ releases/latest.json を更新（{version, file}）。prerelease では更新しない（GitHub の releases/latest と同じ意味論を保つ）
   - 認証は GitHub Secrets の CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID（R2 の書き込み権限のみ）。Sparkle EdDSA 鍵と Developer ID 証明書は従来どおり Actions 内に閉じ、Cloudflare 側へは置かない。
3. appcast の enclosure URL prefix を Worker 配下へ変更する（download_url_prefix を https://befold.tommy109.workers.dev/dl/<tag>/ に）。既存 appcast に含まれる過去エントリの URL は generate_appcast が保持するため GitHub 直リンクのまま残り、既存配布バージョンの自動更新は壊れない。
4. Worker 側ルートを追加・変更する（site/src/routes/public.tsx）。
   - 新設 GET /dl/:tag/:file — R2 の releases/<tag>/<file> をストリーム返却し、kind='download' を version=tag 付きで D1 に記録する。存在しなければ GitHub Releases へ 302 フォールバック。
   - GET /download — releases/latest.json を読んで /dl/... へ 302。R2 に無ければ従来どおり GitHub API 経由へフォールバック。
   - GET /appcast.xml, /appcast-develop.xml — R2 を優先して返し、無ければ現行の GitHub プロキシへフォールバック。update_check の記録は現状どおり維持する。
5. site/test に Vitest を追加する（R2 ヒット / ミス時フォールバック / download イベント記録 / latest.json 解決）。
6. docs/dev/development.md のリリース手順と docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md（対象外としていた R2 移行の記述）を更新する。
7. staging Worker で疎通確認し、dev ビルドで旧→新の Sparkle 自動アップデートを実機検証する（AC#2）。

前提（着手時に確認する）:
- 未確認: generate_appcast が既存 appcast のエントリ URL を書き換えないこと。CI 実行前に手元で旧 appcast + 新 DMG を与えて出力を diff して確認する。
- 未確認: CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID は未設定。ユーザによる GitHub Secrets 登録が必要（ハンドオフ事項）。
- AC#4（ダウンロード数の確認手段）は TASK-182 の D1 + ダッシュボードで既に充足済み。本タスクでは /dl 経由の実ダウンロードも数えられるようになり精度が上がる。
- AC#5 は現状で充足済み（鍵は GitHub Secrets のみ）。R2 用トークンを追加しても Cloudflare 側に署名鍵は置かない。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## /review-design の結果（実装前）

計画へ反映した指摘 7 件。ユーザ判断: (1) 計測の区別は本タスク内で source 列を追加、(2) staging は本番バケットを読み取り専用でバインド。

1. **計測の意味が変わる（項目2・7）**: enclosure を Worker 配下にすると Sparkle の自動更新 DL が kind='download' に混ざる。analytics.ts:83 は kind だけで集計しているため、AC#4 で達成済みの指標が壊れる。→ events に source 列（lp / sparkle）を追加し集計を分離する。UA 判定はしない。
2. **/dl のキー空間（項目1）**: tag/file をそのまま R2 キーへ連結すると releases/latest.json 等が読める。tag は ^v[0-9]+\.[0-9]+\.[0-9]+(-dev\.[0-9]+)?$、file は ^befold-<tag>\.dmg$ で検証し、検証済みの値からのみキーを組み立てる。テストで担保。
3. **CI の順序制約が新設（項目5）**: 「appcast が指す DMG は appcast 公開時点で R2 に存在する」。順序を DMG put → appcast 生成 → appcast put に固定する。
4. **R2 と GitHub の乖離（項目1）**: 「R2 にあれば R2、無ければ GitHub」は中身の有無での判定。appcast の put だけ失敗すると古い appcast を返し続ける。→ R2 put 失敗は CI ジョブ失敗にする（破れない構造）。フォールバックは移行期の一時経路と位置づける。
5. **ミス時は 404 でなく 302（項目4）**: Sparkle は 404 で更新失敗を出す。R2 に無ければ GitHub Releases の同名アセットへ 302。
6. **AC#2 の文言が実態と不一致（項目7）**: フィード URL は TASK-182.4 で既に Worker。R2 化で URL は変わらない。AC を「enclosure が Worker 経由 URL の appcast で EdDSA 検証を通って更新成功」に書き換え済み。
7. **staging（項目9）**: CI は本番バケットのみ put するため staging が空になりフォールバックしか通らない。→ staging の R2 バインディングを本番バケットへ向ける（Worker は読み取りのみ）。

別タスクへ切り出す候補:
- appcast の byte 一致検証手順（TASK-182 Notes の GitHub 直との sha256 比較）を「R2 オブジェクトと Worker 応答の一致」へ差し替える
- appcast 応答への caches.default 導入（現在 GitHub 側の cacheTtl:300 に依存しており、R2 直読みでキャッシュが外れる）

該当しなかった項目:
- 項目3: appcast URL の保持箇所は UpdateChannel.swift / UpdateChannelTests.swift / github.ts / release.yml:204 / docs で列挙済み。latestDMG() の消費側は /download のみ（rg latestDMG で確認）
- 項目6: /dl は DMG をストリームするが R2 egress は無料、D1 INSERT は DL ごと1回で低頻度
- 項目8: Worker はステートレスで非同期に差し替わる表示状態を持たない

実測: git tag --contains b6e2ba3 → フィード URL の Worker 切替は v1.10.1 以降。v1.10.0 以前は GitHub 直の appcast を見ており、AC#3 の根拠。
未確認: generate_appcast が既存 appcast の過去エントリの enclosure URL を書き換えないこと。CI 前に手元で旧 appcast + 新 DMG を与えて diff する。

## 実装（コード側は完了、インフラ設定が未了）

実装済み:
- site/src/lib/dist.ts 新設。R2 キーの解決とタグ/ファイル名の検証（resolveDMGKey）。
- site/src/routes/public.tsx: GET /dl/:tag/:file を新設（R2 から DMG を返す。無ければ GitHub Releases へ 302）。GET /download は R2 の releases/latest.json を読んで DMG を返し、解決できなければ従来の GitHub 解決へフォールバック。appcast は R2 優先・GitHub フォールバック。
- 経路ごとに 1 回だけ記録する形にして二重計上を防いだ（/download は source='lp'、/dl は source='sparkle'）。UA 判定はしていない。
- D1: source 列を追加（migrations/20260808084432_add_download_source.sql）。analytics.ts は MetricKey を導入し download（LP 経由）と update_download（Sparkle 経由）を分離。COALESCE(source,'lp') により source 列導入前の行は LP 経由として数え、過去の DL 数の系列を不連続にしない。
- wrangler.toml: r2_buckets バインディング DIST（本番・staging とも bucket_name=befold-dist）。
- release.yml: DMG を R2 へ put → appcast 生成 → appcast を R2 へ put → stable のみ releases/latest.json を put。いずれも set -euo pipefail で失敗をジョブ失敗にする。enclosure の download_url_prefix を https://befold.tommy109.workers.dev/dl/<tag>/ に変更。GitHub Releases への添付は従来どおり継続。
- docs/dev/development.md に「配布経路」節を追加。site/README.md にルート表・R2 バケット作成手順・必要なトークン権限を追記。設計書の「対象外: DMG 実体の R2 移行」を移行済みに更新。

実測:
- site: npm run typecheck 通過、npm test 86 passed（変更前 74 passed から +12）。
- markdownlint-cli2: 0 issues。
- atlas migrate lint: no diagnostics（ALTER TABLE ADD COLUMN のみで破壊的変更なし）。

## ブロッカー（ユーザ対応が必要）

**Cloudflare アカウントで R2 が有効化されていない。** r2_buckets_list が
403 code 10042 'Please enable R2 through the Cloudflare Dashboard.' を返す。
このため befold-dist バケットを作成できず、AC#1・#2 を実測で確認できない。

さらに、**このブランチを main へマージすると site.yml の deploy ジョブが失敗する**。
wrangler deploy は存在しない R2 バケットへのバインディングを解決できないため。
バケット作成前にマージしないこと。

解消に必要な作業（ユーザ）:
1. Cloudflare ダッシュボードで R2 を有効化する（従量課金の登録が必要）
2. npx wrangler r2 bucket create befold-dist
3. GitHub Secrets の CLOUDFLARE_API_TOKEN に Account / Workers R2 Storage / Edit 権限を追加する
4. GitHub Secrets に CLOUDFLARE_ACCOUNT_ID を登録する

## 残る未確認

- generate_appcast が既存 appcast の過去エントリの enclosure URL を書き換えるかどうかは未確認（ローカルに sparkle 未インストール、which generate_appcast が not found）。ただし設計上ブロッカーにはならない: 全 URL が /dl/<tag>/ へ書き換わっても、R2 に無いタグは GitHub Releases の同名アセットへ 302 されるため更新経路は切れない（test/public.test.ts の 'R2 に無ければ 404 ではなく GitHub Releases へ 302 する' で担保）。
- AC#2（実機の Sparkle 自動アップデート）はバケット作成後の dev リリースで検証する。

レビューで切り出しと決めた 2 件を起票: TASK-365（appcast の配信一致検証を R2 基準へ）、TASK-366（appcast 応答の Worker 側キャッシュ）。

## ブロッカーの切り分け（実測）

2 系統の認証で同じ結果を確認した。トークンのスコープ不足ではなく、アカウントで R2 自体が未有効化。

- MCP（cloudflare-bindings）: r2_buckets_list → 403 code 10042 'Please enable R2 through the Cloudflare Dashboard.'
- ローカル OAuth トークン（tokutomi@degino.com / account 96b3602a71be49f99732550f9f3dedad）: npx wrangler r2 bucket list → 同じ code 10042
- 参考: 同トークンの権限一覧（wrangler whoami）に r2 スコープが無い。ただし権限不足なら code 7403 が返るため、10042 は未有効化を指す

R2 の有効化は従量課金への同意を伴うダッシュボード操作であり、アカウント所有者にしか実施できない。AC#1・#2 はここが解消するまで実測できない。

訂正: 「main へマージすると site.yml の deploy が失敗する」は推論であって実測していない（R2 未有効化のため wrangler deploy を試せない）。バケット作成後に確認すること。

## generate_appcast の前提検証（実測できず）

brew install --cask sparkle を実行して generate_appcast の挙動（既存 appcast の過去エントリの enclosure URL を書き換えるか）を確かめようとしたが、**カスクに generate_appcast が含まれていなかった**ため実測できなかった。この前提は未確認のまま残る。

ただし設計上ブロッカーにはならない。全エントリの URL が /dl/<tag>/ へ書き換わったとしても、R2 に無いタグは GitHub Releases の同名アセットへ 302 されるため更新経路は切れない（test/public.test.ts の 'R2 に無ければ 404 ではなく GitHub Releases へ 302 する' で担保済み）。

この調査の副産物として、より差し迫った問題を発見し TASK-367 として起票した:
Homebrew の sparkle カスクが Gatekeeper 検証を理由に deprecated となり 2026-09-01 に disable される。加えて現時点で既に generate_appcast がカスクから削除されており、release.yml:215-219 の appcast 生成が次のリリースで失敗する可能性がある。TASK-355 の検証（AC#2 の dev リリース）にも影響するため、先に TASK-367 を片付ける必要がある。

検証に使った sparkle カスクはアンインストール済み（環境を元に戻した）。

generate_appcast の前提を実測で確定した（TASK-367 で入手した公式 tarball の generate_appcast 2.9.4 を使用）。

再現手順: 過去エントリの enclosure が GitHub 直リンクの appcast.xml と、新バージョンの DMG（.app 同梱）を同じディレクトリに置き、--download-url-prefix に Worker の URL を与えて generate_appcast を実行。

結果: 'Wrote 1 new update, updated 0 existing updates, and removed 0 old updates in appcast.xml'
- 新エントリ: url="https://befold.tommy109.workers.dev/dl/v1.12.0/befold-v1.12.0.dmg"
- 過去エントリ: url="https://github.com/YTommy109/befold/releases/download/v1.11.0/befold-v1.11.0.dmg"（維持）

**既存エントリの enclosure URL は書き換えられない。** よって v1.10.0 以前の配布済みバージョンの更新経路は無傷で、AC#3 は R2 移行後も成立する。/dl の GitHub フォールバックは過去エントリのためには不要（保険として残す）。この前提は未確認リストから外す。

## R2 有効化後の実測（2026-08-08）

ユーザが R2 を有効化。以下を実施・確認した。

- npx wrangler r2 bucket create befold-dist → 'Created bucket befold-dist with default storage class of Standard'
- npx wrangler deploy --dry-run → バインディングが解決することを確認
  env.DB (befold-analytics) D1 / env.DIST (befold-dist) R2 Bucket / env.ASSETS Assets
- R2 の put / get / delete を実測（リリースワークフローと同じ wrangler r2 object put --remote の形）。テスト用オブジェクト _smoke/latest.json は削除済み
- GitHub Secrets に CLOUDFLARE_ACCOUNT_ID を登録（値はアカウント ID で機密ではない）

訂正の決着: 「バケット不在なら wrangler deploy が落ちる」は結局実測できていない（バケットを作成した後に確認したため）。Cloudflare のドキュメントにも明記が無い。この推論は未確認のまま残るが、バケットが存在する現状では影響しない。

## 残作業

- **CLOUDFLARE_API_TOKEN に R2 の書き込み権限があるか未確認**。トークンのスコープは API から読めないため、リリースワークフローの R2 put ステップが 403 で落ちるまで判別できない。Cloudflare ダッシュボードで Account / Workers R2 Storage / Edit が付いているか確認が必要（ユーザ作業）。
- AC#1・#2 は dev リリースを 1 回打つことで実測する。release.yml はタグが指すコミットの内容で実行されるため、このブランチを main へマージしてからタグを打つ必要がある。TASK-367 の AC#3 も同じ dev リリースで兼ねられる。

## R2 権限の preflight を追加

CLOUDFLARE_API_TOKEN のスコープは API から読めないため、リリース実行前に権限不足を検出する手段が無かった。release.yml のジョブ冒頭（checkout 直後、Xcode セットアップより前）に put → delete の preflight ステップを入れた。

これが無いと、権限不足は「DMG を GitHub Release へ公開した後」の R2 put で初めて露見する。その時点で失敗すると、成果物だけが公開され appcast は更新されず R2 は空、という中途半端な状態が残る。署名・公証に 20 分以上かけた後に落ちるのも避けたい。

実測: 同じコマンド列（wrangler@4 r2 object put --remote → delete --remote）を手元で実行し、put/delete とも成功することを確認。実行後に wrangler r2 bucket info で object_count: 0 を確認し、バケットに残骸が無いことも確かめた。

なお、この preflight はローカルの OAuth トークンで検証したものであり、**CI が使う CLOUDFLARE_API_TOKEN で通るかは未確認**。権限が足りなければリリース時にこのステップが落ちる（ただしビルド前なので実害は最小）。

TASK-367 を PR #443 として分離・提出した。R2 とは独立してマージできる。TASK-355 側（feat/route_deploy）は未 push。

## マージと本番デプロイ（2026-08-08）

- PR #443（TASK-367 / Sparkle ツール）をマージ。verify pass
- PR #444（本タスク / R2 移行）を作成。test pass・verify pass を確認してマージ
- main へのマージで site.yml の deploy が起動。**D1 マイグレーション適用は成功**、Worker デプロイで失敗

### 失敗の原因（実測で確定）

CLOUDFLARE_API_TOKEN に R2 の権限が無い。

  A request to the Cloudflare API (/accounts/96b3602a71be49f99732550f9f3dedad/r2/buckets/befold-dist) failed.
  Authentication error [code: 10000]

これまで「未確認」としてきたトークン権限の件が、ここで確定した。

### 副次的に解決した未確認事項

「バインディング先のバケットが存在しないと wrangler deploy が落ちる」は推論のままだったが、**wrangler deploy が実際に /r2/buckets/<name> を叩いてバインディングを検証している**ことがこのログで判明した。バケット不在でも同じ経路で失敗する。推論の機序は正しかった。

### 本番への影響: なし

デプロイが失敗したため旧バージョンの Worker が稼働継続している。実測:
- GET / → 200
- GET /appcast.xml → 200
- GET /download → 302
- GET /healthz → 200

旧コードは source 列を使わないため、先に適用された D1 マイグレーション（ADD COLUMN）とも矛盾しない。

### 解消に必要な作業（ユーザ）

Cloudflare ダッシュボード（https://dash.cloudflare.com/profile/api-tokens）で CLOUDFLARE_API_TOKEN に **Account / Workers R2 Storage / Edit** を追加する。追加後、site.yml の deploy を再実行すれば通る（gh run rerun）。

これが済むまで dev リリースは打たない。打っても preflight ステップが同じ理由でビルド前に落ちる（そう設計した）。

## dev リリース v1.12.3-dev.2 による実測（2026-08-08）

ユーザが CLOUDFLARE_API_TOKEN に R2 権限を追加。site.yml の deploy 再実行が success となり、Worker が R2 バインディング付きで本番反映された。その後 v1.12.3-dev.2 タグを打ってリリースワークフローを実行した。

### リリースワークフロー: 全ステップ success（run 31250794505）

- R2 へ書き込めることを確認する → success（preflight。トークン権限の確定）
- DMG を R2 へアップロードする → success
- appcast を生成する → success
- appcast を固定リリースにアップロードする → success（GitHub 側の後方互換も維持）
- appcast を R2 へアップロードする → success
- stable の最新ポインタを R2 へ配置する → skipped（prerelease のため。意図どおり）

### AC#1 の実測

R2 に署名・公証済みの DMG と appcast が配置された。Worker が返す appcast-develop.xml の enclosure:

- 新エントリ: https://befold.tommy109.workers.dev/dl/v1.12.3-dev.2/befold-v1.12.3-dev.2.dmg
- v1.12.3-dev.1 / v1.12.2 の過去エントリ: GitHub 直リンクのまま（事前実験どおり書き換わらない）

### AC#2 の実測（GUI 操作を除く全経路）

- GET /dl/v1.12.3-dev.2/befold-v1.12.3-dev.2.dmg → 200、7,113,222 バイト、Content-Type application/x-apple-diskimage。appcast の length と完全一致
- sha256 が GitHub Release の同名アセットと完全一致: bdc1ab308c24dc62cb9415eb1bb6c34640104a32fba61c58e21d5061a720942e
- DMG をマウントして codesign --verify --deep --strict 通過、spctl -a --type execute → accepted / source=Notarized Developer ID / origin=Developer ID Application: Yuichi Tokutomi (X3587J4U72)
- CFBundleShortVersionString = 1.12.3-dev.2
- **EdDSA 署名検証**: appcast の sparkle:edSignature（64 バイト）を、アプリ内蔵の SUPublicEDKey（ktKZ4ysV5yIdgGkTTkpD4aSs/soC1qksE4vvQ7S9Z78=）で openssl pkeyutl -verify（Ed25519 raw）した結果 'Signature Verified Successfully'。Sparkle がインストール前に行う検証と同じもの

### AC#5 の実測（本番）

- GET /download → source='lp'、GET /dl/... → source='sparkle' として D1 に記録されることを本番で確認
- ダッシュボードは「ダウンロード」と「自動アップデート適用」を別指標として集計する

### 検証で生じたデータの後始末

- R2 のスモークテスト用オブジェクト（releases/v0.0.1-dev.1/... と releases/latest.json）を削除
- curl による計測イベント計 13 件を D1 から削除

### 残るもの

AC#2 の文言のうち「実機で成功する」の GUI 操作部分（旧 dev ビルドを起動し Sparkle にアップデートさせる）のみ未実施。CLAUDE.md のテスト規約で GUI 層は自動テスト対象外・リリース前手動チェックと定めているため、ユーザによる dogfood で確認する。配信・署名・検証の経路はすべて上記で実測済み。

## AC#2 の実機検証（2026-08-08 18:41 JST）

この Mac に v1.12.3-dev.1 が develop チャンネルで稼働していたため、そのまま実機の dogfood として検証した。

1. アプリメニューの 'Check for Updates…' を実行
2. Sparkle が 'Software Update' ウィンドウを表示: 'befold 1.12.3-dev.2 is now available—you have 1.12.3-dev.1.'
   → Worker/R2 経由の appcast-develop.xml から新バージョンを検知できている
3. 'Install Update' をクリック → 'Updating befold' でダウンロード・検証・インストールが進行
4. アプリが自動再起動（PID 16562 → 59645）
5. /Applications/befold.app の CFBundleShortVersionString = **1.12.3-dev.2**

EdDSA 検証は Sparkle がインストール前に必ず行うもので、署名が不正なら手順 3 で失敗する。完了して再起動しているため検証を通過している（事前に openssl で同じ署名を Ed25519 検証済み）。

計測にも実データとして記録された:
- update_check / channel=develop / ua_summary=Sparkle（18:41:19）
- download / version=v1.12.3-dev.2 / channel=develop / **source=sparkle** / ua_summary=Sparkle（18:41:39）

これは Sparkle の実ダウンロードが /dl 経由で計測されることの実証でもあり、本タスクで新設した source 列の分離（AC#5）が実運用データで機能していることを示す。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
リリース成果物（DMG）と Sparkle の appcast の配信元を GitHub Releases から Cloudflare R2 へ移し、配布サイト Worker から配信するようにした。署名・公証は従来どおり GitHub Actions 上で行い、署名済みの成果物だけを R2 へ配置する（Cloudflare 側に鍵は置かない）。

主な設計判断: (1) appcast の enclosure を Worker 配下の /dl/<tag>/<file> に向け、Sparkle の実ダウンロードも計測できるようにした。(2) それに伴い LP 経由の新規獲得と自動更新が同じ kind='download' に混ざるため events に source 列を追加し、COALESCE(source,'lp') で過去データの系列を保ったまま分離した。(3) /dl はタグとファイル名を検証してから R2 キーを組み立てる（バケット内の配信対象外オブジェクトを読み出せないようにする）。(4) R2 に無いオブジェクトは 404 ではなく GitHub Releases へ 302 する（Sparkle は enclosure の 404 を更新失敗として扱うため）。(5) R2 への put 失敗はジョブ失敗とし、ジョブ冒頭に権限の preflight を置いた（put は GitHub Release 公開より後に来るため、権限不足だと中途半端な公開状態で失敗する）。

検証: site のテスト 86 passed（74 から +12）、typecheck・markdownlint・atlas migrate lint いずれも通過。dev リリース v1.12.3-dev.2 でリリースワークフローを実行し全ステップ success。配信された DMG は GitHub Release の成果物と sha256 完全一致、codesign / spctl（Notarized Developer ID）通過、appcast の EdDSA 署名をアプリ内蔵の SUPublicEDKey で Ed25519 検証して成功。実機の v1.12.3-dev.1 から Sparkle の自動アップデートを実行し 1.12.3-dev.2 への更新が成功、その実ダウンロードが source=sparkle として D1 に記録されることも確認した。

未実測として残るもの: 「バインディング先の R2 バケットが存在しないと wrangler deploy が落ちる」は推論だったが、権限不足時のデプロイ失敗ログで wrangler が /r2/buckets/<name> を検証していることが判明し機序は裏付けられた。後続として TASK-365（appcast の配信一致検証を R2 基準へ）と TASK-366（appcast 応答の Worker 側キャッシュ）を起票済み。
<!-- SECTION:FINAL_SUMMARY:END -->
