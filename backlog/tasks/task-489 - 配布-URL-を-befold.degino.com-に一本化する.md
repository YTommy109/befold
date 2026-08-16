---
id: TASK-489
title: 配布 URL を befold.degino.com に一本化する
status: To Do
assignee: []
created_date: '2026-08-16 01:59'
updated_date: '2026-08-16 02:08'
labels: []
milestone: m-8
dependencies: []
priority: medium
ordinal: 720000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布・更新に使う URL を befold.degino.com だけに畳む。

## 現状（2026-08-16 実測）

**3 世代すべてが現役で稼働している。**

| 世代 | URL | 実測 |
| --- | --- | --- |
| (a) GitHub Pages | `https://ytommy109.github.io/befold/` | **有効・稼働中**。`gh api repos/YTommy109/befold/pages` が `status: built` / `source: main /docs` を返す。HTTP 200。配信物は `docs/index.html` で、meta refresh と `location.replace` で `https://befold.degino.com/?ref=gh-pages` へ飛ばすだけの shim |
| (b) Cloudflare 既定 | `https://befold.tommy109.workers.dev/` | **生存**。`/` は 301 で degino へ、`/appcast.xml` は 200（リダイレクトしない） |
| (c) 独自ドメイン | `https://befold.degino.com/` | 正規。`/appcast.xml` 200 |

**旧世代が残っているのは設計判断による。** ADR 0007（`docs/adr/0007-distribution-site-custom-domain.md`）が workers.dev の恒久併存を決めており、理由は「出荷済みアプリの Sparkle フィード URL はバイナリに焼き込まれていて後から変更できない」「配信済み appcast の enclosure URL も変更できない」ため、`/appcast.xml`・`/appcast-develop.xml`・`/dl/*` の 3 経路は旧ホストで無期限に同じ内容を返し続けなければならない、というもの（同 :29-44）。

停止条件についても同 ADR が既に書いている（:117-118）。

> 停止時期は定めない。停止できる条件は「旧ホストの appcast を叩くクライアントがゼロになったこと」だが、これは観測できてもゼロを保証できない。

**つまり現状は「消せない」のではなく「消せる条件を観測できていない」。** アクセス統計の `events` テーブルにはホストもパスも列が無く（`site/schema/schema.sql:5-26`）、旧ホストの `update_check` が今どれだけ来ているかを数える手段が無い。まずここを埋める。

## GitHub 側への依存（バイナリ配布を止める前に解く必要があるもの）

- `.github/workflows/release.yml:212-216` GitHub Release を作成し DMG を添付（コメント :208-213 に「移行期の後方互換とロールバックのために残す」）
- `.github/workflows/release.yml:308-316` 固定リリース `appcast` へ appcast をアップロード。かつ同ワークフローは `gh release download appcast` を**入力としても**使う（:289,300 付近）ため、GitHub を止めるには入力を R2 へ移す先行作業が要る
- `site/src/lib/github.ts:10-12` `APPCAST_UPSTREAM` — R2 に無いとき GitHub の appcast をプロキシするフォールバック
- `site/src/routes/public.tsx:73-76` `/dl/:tag/:file` は R2 に無いとき GitHub Releases のアセットへ 302
- `site/src/routes/public.tsx:37-55` `/download` は `releases/latest.json` が無いとき GitHub API へフォールバック
- `docs/dev/development.md:113-119` 「v1.10.0 以前の配布済みバージョンは GitHub 直の appcast URL を見ており（フィード URL の Worker 切替は v1.10.1 以降）、そこからたどれる成果物が必要」
- 過去に配信済みの appcast に埋まっている enclosure URL は書き換えられない（TASK-355 の Notes に実測記録）。GitHub の該当リリースアセットを消すと、その版からの更新ダウンロードが 404 になる

## 残すもの

ソースリポジトリとしての `github.com/YTommy109/befold` へのリンクは残す（`site/src/views/shared.tsx:10` の `REPO_URL`、`BefoldApp/BefoldKit/AppLinks.swift:38,41` の Issues・作者プロフィール）。止めるのは**バイナリと appcast の配布経路**であって、開発リポジトリではない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 旧世代 URL（GitHub Pages / workers.dev / GitHub Releases 経由の配布）を停止できる条件が、観測可能な指標として文書化されている
- [ ] #2 旧ホストと GitHub 直経路へのアクセス数がダッシュボードで確認できる
- [ ] #3 停止条件に関係なく削除できる残骸が削除されている
- [ ] #4 条件を満たさないまま停止しないことが、テストまたは文書上の担保で守られている
- [ ] #5 ソースリポジトリとしての GitHub へのリンクは残っている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
計測に関するサブタスク（旧 TASK-489.2）は TASK-488.3 へ移し、TASK-489.2 はアーカイブした。m-8 の作業は「条件を決める（489.1）」「消せる残骸を消す（489.3）」「条件充足後に止める（489.4）」の 3 本で、観測は m-7 / TASK-488.3 に依存する。
<!-- SECTION:NOTES:END -->
