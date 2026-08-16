---
id: TASK-491
title: 稼働中のアプリバージョンと OS をアップデート確認から測れるようにする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-16 02:34'
updated_date: '2026-08-16 07:08'
labels: []
milestone: m-7
dependencies: []
priority: medium
ordinal: 727000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
古いバージョンを使い続けている利用者がどれだけいるかを把握できるようにする。

## 現状（実測）

**`update_check` は「何件来たか」しか記録していない。** appcast ハンドラは `recordEvent(c, { kind: 'update_check', channel })` を呼ぶだけで、`version` を渡していない（`site/src/routes/public.tsx:146`）。リクエストから取るのは UA・IP・CF ヘッダのみで、クエリパラメータは一切読んでいない（`site/src/events.ts:33-56`）。

本番 D1（`befold-analytics`、2026-08-16 時点、全 538 行）を実測した結果:

- `update_check` は 132 件。**全件が `version` NULL / `os` NULL**。内訳は `ua_summary='Sparkle'` が 101 件（develop 81 / stable 20）、`curl' が 31 件。
- `summarizeUA` は Sparkle の UA を `'Sparkle'` の 1 語に丸めてバージョンを捨てる（`site/src/lib/visitor.ts:137`）。`summarizeOS`（同 `:35-42`）は `Mac OS X` / `Macintosh` / `Darwin` を探すが Sparkle の既定 UA（`befold/1.12.3 Sparkle/2.x` 形式）はどれも含まないため NULL になる。

**自動アップデート自体は既に記録されている（未記録という前提は誤り）。** `kind='download'` かつ `source='sparkle'` の行が実測で 16 件あり、`version` も入っている（`v1.12.3`, `v1.12.4-dev.5` など）。enclosure が Worker の `/dl/:tag/:file` を通るため計上される（`site/src/routes/public.tsx:64-71`、`.github/workflows/release.yml` の `download_url_prefix`）。ダッシュボードにも `update_download` 指標として既に出ている（`site/src/analytics.ts:44-49,118-124`）。

ただしこの `version` は**更新先**のタグであって**更新元**ではない。「今どのバージョンが動いているか」は依然として測れていない。

**システムプロファイリングは無効。** `SUEnableSystemProfiling` はリポジトリ内に記述が無く（`BefoldApp/befold/Info.plist` は `SUPublicEDKey` のみ）、Sparkle 既定の無効。有効にすると appcast URL に `appVersion` / `osVersion` / `model` / `ncpu` / `ramMB` / `lang` 等がクエリで付く。

## 決めるべきこと

- **UA から取るか、システムプロファイリングを有効にするか。** UA からアプリバージョンを取る方式はアプリ側の変更も追加送信も要らず、プライバシーへの影響が最小。一方 OS バージョン（macOS 14 / 15 / 26 の別）は UA に載らないため、取るならプロファイリング有効化が必要で、送信する端末情報が増える。まず生 UA を実測して何が取れるかを確定させ、OS バージョンを諦めるか別途 ADR を立てるかを決める。
- **`version` 列に入れてよいか。** 現状 `version` は `download` では「ダウンロード対象のタグ」の意味。`update_check` に「稼働中バージョン」を入れると同じ列に 2 つの意味が同居する。列を分けるか、意味を明文化して同居させるかを確定させ、既存の「バージョン別」集計（`site/src/analytics.ts` の `byVersion`）の意味が変わらないことを確かめる。

## 注意

- 既存 132 件の `update_check` は遡及分類できない。ダッシュボードには既に同種の注記があるので同じ形で示す（`site/src/views/dashboard.tsx`）。
- スキーマ変更は Atlas 運用に従う（`site/schema/schema.sql` を更新 → `npm run migrate:diff` → `migrate:lint` → local → remote。`site/README.md:59-73`）。追加は `ADD COLUMN` で行う（`scripts/check-destructive-migrations.sh`）。
- `summarize()` の発行クエリ数上限テストがある（`site/test/query-count.test.ts:35` の `MAX_QUERIES = 13`）。
- 状態と列を新設する変更のため、各サブタスクで実装着手前に `/review-design` を 1 回回す（`.claude/CLAUDE.md`「実装着手前の設計レビュー」）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 稼働中のアプリバージョンの分布がダッシュボードで見られる
- [x] #2 旧バージョンを使い続けている利用者の規模が読み取れる
- [x] #3 採用した取得方式（UA 由来 / システムプロファイリング）と、プライバシー面で送信情報が増えるかどうかが記録されている
- [x] #4 既存のバージョン別集計とダウンロード指標の意味と数値が変わらない
- [x] #5 遡及分類できない既存行の扱いがダッシュボード上で注記されている
- [x] #6 site の vitest と typecheck が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
両サブタスクを完了した。

- **TASK-491.1（記録）**: Sparkle の生 UA を実測（`befold/1.13.2-dev.4 Sparkle/2.9.4`）し、events に `app_version` 列を新設して稼働バージョンを記録するようにした。`version`（download の対象タグ）とは列を分けたので既存の `byVersion` 集計は不変。
- **TASK-491.2（表示）**: ダッシュボードに「稼働中のアプリバージョン（直近 14 日）」をチャネル別に表示。数えるのはアクセス元の異なり数で、延べ確認回数ではない。

## 親タスクの「決めるべきこと」への回答

**UA から取る方式を採った。** OS バージョンは見送り。`SUEnableSystemProfiling` を有効にすると `appVersion` / `osVersion` / `model` / `ncpu` / `ramMB` / `lang` が appcast URL に付き、送信する端末情報が増える。UA 方式はアプリ側の変更も追加送信も不要で、プライバシーへの影響が最小。OS バージョンが必要と判断した時点で ADR を起こして別タスクにする。

**`version` 列は流用せず `app_version` を新設した。** 1 列に 2 つの意味（更新先のタグ / 更新元の稼働版）が同居するのを避けた。`byVersion`（`kind='download' AND COALESCE(source,'lp')='lp'`）は SQL も値も変えていない。

## 残る制約（想定どおり）

既存 132 件の `update_check` は遡及分類できない。ダッシュボードの注記で「稼働バージョンの記録は 2026-08-16 に始めたもので、それより前のアップデート確認はどのバージョンから来たかを遡って分類できない」と明示している。本番 D1 への反映は `npm run migrate:remote`（または Site Migrate ワークフロー）が必要で、それまで本番の分布は空になる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
update_check から「今どのバージョンが動いているか」を測れるようにした。記録側（TASK-491.1）は Sparkle の生 UA を実測した上で稼働バージョンだけを抽出し、events の新設列 app_version に入れる。表示側（TASK-491.2）はダッシュボードにチャネル別の分布を出し、数える単位（アクセス元の異なり数）・期間（直近 14 日）・ダウンロード対象タグ別集計との違い・遡及分類できない既存行を画面上で説明する。取得方式は UA 由来を採用し、送信情報が増えるシステムプロファイリングは見送った。既存の byVersion 集計とダウンロード指標は SQL も値も変えていない。検証は site の vitest 277 件通過・typecheck・クエリ本数 13 本の上限テスト。
<!-- SECTION:FINAL_SUMMARY:END -->
