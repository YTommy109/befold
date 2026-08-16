---
id: TASK-495
title: R2 から配れず GitHub へフォールバックした配信を記録・表示する
status: To Do
assignee: []
created_date: '2026-08-16 02:40'
labels: []
milestone: m-8
dependencies: []
priority: medium
ordinal: 724500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
R2 を正とする配布が実際に効いているかを測れるようにする。TASK-489（配布 URL の一本化）で GitHub バイナリ配布を止める判断をする際、「もう GitHub に落ちていない」ことを実測で示す材料になる。

## 現状（実測）

フォールバック経路は 3 つあり、**いずれも記録されていない**。成功も失敗も同じ 1 行として `download` / `update_check` に計上されるだけで、区別が付かない。

1. `site/src/routes/public.tsx:73-92` `serveDMG()` — `resolveDMGKey` が null、または R2 に該当オブジェクトが無いとき、GitHub Releases の同名アセットへ 302 する。`/download`（LP）と `/dl/:tag/:file`（Sparkle の enclosure）の両方がここを通る。
2. `site/src/routes/public.tsx:42-51` `/download` — R2 の `latest.json` ポインタが読めない（移行前・put 失敗・stable 未リリース・JSON 破損）とき、GitHub 側の解決へ落とす。コメントに「導線は途切れさせず、従来どおり GitHub 側の解決へ落とす」とある。
3. `site/src/routes/public.tsx:159-189` `loadAppcast()` — R2 に appcast が無いとき、GitHub の appcast をプロキシする。コメントに「フォールバックは移行期の経路であって恒常的な二重の真実ではない」と明記されている。

`resolveDMGKey` が null を返すケース（想定外のタグ・ファイル名）は不正リクエストであり、R2 の欠落とは意味が違う。同じ 302 でも分けて数える必要がある。

## 決めること

- **どう持つか。** イベント種別を増やすか、既存行に「R2 から配れたか」を表す列を足すか。ダウンロード数の既存指標（`site/src/analytics.ts:44-49` の `download` / `update_download`）の意味と数値を変えないこと。
- **不正リクエストと R2 欠落を分けるか。** `resolveDMGKey` が null（検証で弾いた）と、R2 に無い（配布の穴）は原因も対処も違う。
- **どこまで表示するか。** TASK-489 の停止判断に使う指標なので、「直近 N 日でフォールバックが 0 件」が読めれば足りる。恒常的なグラフが要るかは判断する。

## 注意

- 記録のために配信を遅らせない。計測は best-effort で `ctx.waitUntil` に逃がす既存の方針を守る（`site/src/events.ts:22-30`）。
- スキーマを変えるなら Atlas 運用に従う（`site/schema/schema.sql` → `npm run migrate:diff` → `migrate:lint` → local → remote。`site/README.md:59-73`）。追加は `ADD COLUMN`（`scripts/check-destructive-migrations.sh`）。
- `summarize()` の発行クエリ数上限テストに注意（`site/test/query-count.test.ts:35` の `MAX_QUERIES = 13`）。
- 記録経路を増やす変更のため、実装着手前に `/review-design` を 1 回回す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 R2 から配れず GitHub へフォールバックした配信が、成功した配信と区別して記録される
- [ ] #2 DMG 配信・latest ポインタ・appcast の 3 経路すべてのフォールバックが記録される
- [ ] #3 検証で弾いた不正なタグ・ファイル名と、R2 の欠落が区別できる
- [ ] #4 直近の期間でフォールバックが発生していないことがダッシュボードから確認できる
- [ ] #5 既存のダウンロード指標の意味と数値が変わらない
- [ ] #6 各フォールバック経路のユニットテストがある
- [ ] #7 site の vitest と typecheck が通る
<!-- AC:END -->
