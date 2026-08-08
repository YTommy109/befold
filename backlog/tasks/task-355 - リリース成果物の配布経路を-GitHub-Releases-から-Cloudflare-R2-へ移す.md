---
id: TASK-355
title: リリース成果物の配布経路を GitHub Releases から Cloudflare R2 へ移す
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-08 01:21'
updated_date: '2026-08-08 08:59'
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
- [ ] #1 リリースワークフローが署名・公証済みの DMG と appcast.xml を Cloudflare R2 へアップロードする（R2 への put 失敗はジョブ失敗として扱う）
- [ ] #2 appcast の enclosure が Worker 経由の R2 配信 URL になった状態で、dev ビルドの旧バージョンから新バージョンへの Sparkle 自動アップデートが EdDSA 検証を通って実機で成功する
- [ ] #3 v1.10.0 以前の配布済みバージョンが参照する GitHub 直の appcast URL が更新され続け、自動アップデートが壊れない
- [ ] #4 ダウンロード数を確認できる手段が用意されている
- [ ] #5 LP 経由のダウンロードと Sparkle の自動更新ダウンロードがダッシュボードで区別して集計される
- [ ] #6 Sparkle の EdDSA 秘密鍵と Developer ID 証明書が Cloudflare 側に配置されていない（CI の Cloudflare トークンは R2 書き込みのみのスコープ）
- [ ] #7 /dl のパス検証により、R2 バケット内の DMG 以外のオブジェクトが読み出せないことをテストで担保する
- [ ] #8 配布手順の変更が docs 配下のリリース手順と配布設計書に反映されている
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
<!-- SECTION:NOTES:END -->
