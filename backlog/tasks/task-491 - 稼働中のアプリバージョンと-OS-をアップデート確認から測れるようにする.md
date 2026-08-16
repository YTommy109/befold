---
id: TASK-491
title: 稼働中のアプリバージョンと OS をアップデート確認から測れるようにする
status: To Do
assignee: []
created_date: '2026-08-16 02:34'
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
- [ ] #1 稼働中のアプリバージョンの分布がダッシュボードで見られる
- [ ] #2 旧バージョンを使い続けている利用者の規模が読み取れる
- [ ] #3 採用した取得方式（UA 由来 / システムプロファイリング）と、プライバシー面で送信情報が増えるかどうかが記録されている
- [ ] #4 既存のバージョン別集計とダウンロード指標の意味と数値が変わらない
- [ ] #5 遡及分類できない既存行の扱いがダッシュボード上で注記されている
- [ ] #6 site の vitest と typecheck が通る
<!-- AC:END -->
