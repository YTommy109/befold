---
id: TASK-506
title: 配布サイトに旧バージョン（stable）のダウンロードページを用意する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-16 13:46'
updated_date: '2026-08-16 14:54'
labels: []
dependencies: []
ordinal: 737000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
最新版に不具合があったとき、利用者が一つ前の stable に戻せるようにする。現在 befold.degino.com は LP の /download が stable 最新の DMG を R2 から返すだけで、過去バージョンへ辿る導線が無い。

過去の stable リリース一覧（バージョン・公開日・リリースノートへのリンク・DMG のダウンロードリンク）を並べたページを追加する。dev（develop チャンネル）のリリースは対象外で、一覧にも出さない。

ダウンロード実績は既存の download イベントと同じ枠組みで記録し、どのバージョンが旧版として落とされたかがダッシュボードから分かる状態にする。一覧の取得元（R2 のポインタ/オブジェクト列挙か GitHub Releases か）と、LP からの導線の置き場所は着手時に決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold.degino.com に過去の stable バージョンを一覧するページがあり、各行からその版の DMG をダウンロードできる
- [x] #2 一覧に develop チャンネル（プレリリースタグ）のリリースが含まれない
- [x] #3 各行にバージョン・公開日・リリースノートへのリンクが表示される
- [x] #4 LP から旧バージョンページへ辿れる導線がある
- [x] #5 旧バージョンのダウンロードが download イベントとして版ごとに記録され、ダッシュボードで確認できる
- [x] #6 ページが LP と同じ意匠・多言語対応で表示される
- [x] #7 一覧の取得元が利用できない場合でもページがエラー表示にならず、状況が利用者に伝わる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 決定した前提（調査の裏付け付き）

- stable の判定: GitHub Releases API の prerelease=false かつタグが ^v\d+\.\d+\.\d+$（実測: 補助リリース 'appcast' が prerelease=false で混ざる。stable は 47 件、dev は -dev.N の prerelease）
- 一覧の取得元は GitHub Releases API（/repos/YTommy109/befold/releases?per_page=100）。R2 の releases/ 列挙は採らない: 公開日・リリースノート・アセット名の実体が無く、旧版のアセット名が mmdview-vX.Y.Z.dmg と現行規約（dmgFileName = befold-<tag>.dmg, site/src/lib/dist.ts:56-58）で導出できないため
- ダウンロード先は経路を分ける。既存 /dl/:tag/:file（site/src/routes/public.tsx:84-91）は source='sparkle' 固定で自動更新専用なので流用しない

## 実装手順

1. site/src/lib/github.ts に stableReleases(): Promise<ReleaseEntry[] | null> を追加。ReleaseEntry = { tag, publishedAt, notesUrl, dmgFile }。prerelease と非 semver タグと DMG 無しを除外し、cf: { cacheTtl, cacheEverything } でキャッシュ。**失敗は null を返し、空配列（= 一件も無い）と区別する**（縮退はデータの空きでなく事実で判定する）
2. site/src/schema.ts の downloadSourceSchema に 'archive' を追加（source は TEXT 列なので D1 マイグレーション不要）。pageSchema に '/releases' を追加
3. site/src/lib/pages.ts の SITE_PAGES に { '/releases', ja } と { '/en/releases', en } を追加（ルート登録・301・sitemap・hreflang が自動追従）
4. site/src/routes/public.tsx:40-46 の 2 ページ前提の三項分岐を Record<Page, FC> へ置き換える（3 ページ目で分岐を足すのではなく、ページを増やしたら型で漏れが出る形にする）
5. site/src/views/releases.tsx を新設。PageShell + 既存意匠で、バージョン・公開日・リリースノートリンク・ダウンロードリンクの表を出す。文言は Localized（ja/en）でコロケーション。取得失敗時（null）は表の代わりに「一覧を取得できませんでした」と GitHub リリース一覧へのリンクを出し、200 で返す（AC #7）
6. 配信ルート publicRoutes.get('/releases/:tag/:file') を追加し、serveDMG を共有して recordEvent({ kind:'download', version: tag, channel:'stable', source:'archive' }) を記録
7. site/src/analytics.ts: MetricKey に 'archive_download' を追加、METRIC_FILTERS に { kind:'download', source:'archive' }、KIND_LABELS にラベル。既存テストが全 MetricKey の被覆を検査するため漏れれば落ちる
8. site/src/views/shared.tsx の SiteFooter に旧バージョンページへのリンクを追加（全ページに出る導線、AC #4）
9. site/test/public.test.ts にページ本体・縮退・配信ルートの記録（source='archive'）のテスト、analytics 側にラベル被覆のテストを追加
10. npm run lint / format:check / test（site/）を通す

## /review-design の反映（実装前レビュー）

- 【修正1】アーカイブ配信は resolveDMGKey を使わない。tag は tagSchema、file は ^[A-Za-z0-9._-]+\.dmg$ で検証して R2 キーを組む。理由: resolveDMGKey は file を befold-<tag>.dmg に固定するが（dist.ts:47-53）、v1.3.3 以前の実アセット名は mmdview-vX.Y.Z.dmg（実測）。流用すると正常な配信が dmg-invalid として記録され、ADR 0007 / TASK-489 の判断材料（public.tsx:93-99）を汚す
- 【修正2】R2 欠落時の GitHub 302 は fallbackRouteSchema に 'archive-dmg' を足して記録を分ける（既存の 'dmg' は R2 の穴を表す指標であり、旧版は R2 に無いのが正常なため混ぜない）
- 【修正3】/releases/:tag/:file は isPrerelease(tag) が真なら 404。tagSchema は -dev.N を許す（dist.ts:18）ので、一覧側だけ絞ると URL 直打ちで dev が配れてしまう
- 【修正4】analytics.test.ts に「downloadSourceSchema の全値が METRIC_FILTERS のいずれかの source として現れる」テストを足す。MetricKey = EventKind | 'update_download'（analytics.ts:45）なので、source を足しても指標系列の足し忘れは型では捕まらない
- 【注記】per_page=100 を超えた古い版は表に出ない。GitHub のリリース一覧へのリンクを常設して逃がす（実測: 現在 stable 47 件）
- 【未確認】Worker の共有 IP から GitHub API 未認証（60 req/h/IP）を叩くため、エッジキャッシュが効かないと 403 が常態化しうる。cacheTtl を付けた上で、AC #7 の縮退表示を保険とする
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装したもの

- 一覧の取得元は GitHub Releases API。site/src/lib/github.ts に stableReleases() を追加し、prerelease・非 semver タグ（appcast）・DMG 無しを除外する。**取得失敗は null、0 件は空配列**で返し、ビューが別々の文面を出す
- ページは /releases・/en/releases。SITE_PAGES に足したのでルート登録・sitemap・hreflang・旧ホスト 301 は自動追従。public.tsx の 2 ページ前提の三項分岐は Record<Page, view> へ置き換えた（3 ページ目が Features として描かれる形を構造で塞ぐ）
- 配信は /releases/:tag/:file。stable タグのみ受け、ファイル名は ^[A-Za-z0-9._-]+\.dmg$ で検証。source='archive' で記録し、R2 に無ければ fallback='archive-dmg' を記録して GitHub へ 302
- LP のインストール手順の直後に「過去のバージョンを見る →」を追加
- ダッシュボード: MetricKey に archive_download を追加。あわせて**バージョン別内訳を単独クエリから指標別内訳の軸へ畳んだ**（METRIC_BREAKDOWN_AXES に 'version' を追加）。これで指標ごとのバージョン別表が出て、traffic 面のクエリは 8→7 本に減る（query-count.test.ts の上限に当たらずに AC #5 を満たせた）
- D1 マイグレーションは不要（source / fallback / page はいずれも TEXT で CHECK 制約が無い。migrate 済み D1 に対するテスト 360 件が通ることで実証）

## 検証

- npm test: 12 ファイル 360 件すべて成功
- npm run lint（--type-aware）/ format:check / typecheck: いずれもクリーン
- ローカル実測（wrangler dev + curl、GitHub API 実データ）: /releases が v1.13.2 以下の stable のみを表示し、dev.N と appcast タグは出ない。各行に公開日（2026-08-16）・リリースノート URL・/releases/<tag>/<実アセット名> のリンク。旧名 mmdview-v1.3.3.dmg も正しくリンクされる。/releases/v1.3.3/mmdview-v1.3.3.dmg は 302 で GitHub へ、/releases/v1.13.3-dev.1/... は 404。LP に href="/releases" の導線、/en/releases は英語表示
- テストが実際に働くことの確認: METRIC_FILTERS の archive_download の source を故意にずらすと、analytics の被覆テストと dashboard の版別テストが両方落ちることを実測

## 未確認

- 本番の Worker から GitHub API（未認証・60 req/h/IP）を叩いたときのレート制限。cf.cacheTtl=600 を付けているが、実効はデプロイ後にしか測れない。当たった場合は AC #7 の縮退表示に落ちる（行き止まりにはならない）
- 一覧は per_page=100 の 1 リクエストぶんのみ（現在 stable 47 件）。天井に当たったときのために GitHub のリリース一覧へのリンクを常設した
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
配布サイトに /releases（日英）を追加し、GitHub Releases API から stable だけを一覧して版ごとにダウンロードできるようにした。配信は専用ルートで source='archive' として記録し、ダッシュボードに「旧バージョンのダウンロード」系列と指標別のバージョン別内訳を追加した（バージョン別を指標別内訳の軸へ畳んだため traffic 面のクエリは 8→7 本）。取得失敗時は 200 のまま縮退表示に落とす。site の全 360 テスト・lint・型チェックが通り、wrangler dev + 実データで一覧・除外・配信・404 を実測した。
<!-- SECTION:FINAL_SUMMARY:END -->
