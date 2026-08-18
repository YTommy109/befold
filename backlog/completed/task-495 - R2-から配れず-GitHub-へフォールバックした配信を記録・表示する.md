---
id: TASK-495
title: R2 から配れず GitHub へフォールバックした配信を記録・表示する
status: Done
assignee: []
created_date: '2026-08-16 02:40'
updated_date: '2026-08-17 14:52'
labels: []
milestone: m-8
dependencies: []
priority: medium
type: feature
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
- [x] #1 R2 から配れず GitHub へフォールバックした配信が、成功した配信と区別して記録される
- [x] #2 DMG 配信・latest ポインタ・appcast の 3 経路すべてのフォールバックが記録される
- [x] #3 検証で弾いた不正なタグ・ファイル名と、R2 の欠落が区別できる
- [x] #4 直近の期間でフォールバックが発生していないことがダッシュボードから確認できる
- [x] #5 既存のダウンロード指標の意味と数値が変わらない
- [x] #6 各フォールバック経路のユニットテストがある
- [x] #7 site の vitest と typecheck が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 現状（実測）

TASK-495 の大半は PR #534 / #537 で既に入っている（`git log -S github_fallback`）。

- `src/schema.ts:80` `fallbackRouteSchema = z.enum(['appcast', 'dmg', 'release-api'])` と
  `eventSchema` の refine（fallback は kind=github_fallback 専用）
- `schema/schema.sql:51-55` の `fallback` 列
- 記録は 3 経路すべてに入っている（`src/routes/public.tsx:63` release-api /
  `:99` dmg / `:223` appcast）
- 集計は `eventBreakdowns` の 1 クエリに相乗り（`src/analytics.ts:753` byFallback）、
  表示は配信面の「GitHub フォールバックの経路別」（`src/views/dashboard.tsx:785`）
- テストは `test/public.test.ts:1006-1059` に 3 経路ぶんある

→ AC #1 / #2 / #5 / #6 は充足済み。残りは #3 と #4。

## 残差分 1: 不正リクエストと R2 欠落を分ける（AC #3）

`serveDMG`（`src/routes/public.tsx:95-101`）は `resolveDMGKey` が null（タグ・
ファイル名が検証で弾かれた＝不正リクエスト）でも、R2 に無い（配布の穴）でも
同じ `fallback='dmg'` を記録している。原因も対処も違うので分ける。

- `fallbackRouteSchema` に `'dmg-invalid'` を足す
- `resolveDMGKey` が null のときだけ `'dmg-invalid'`、R2 ミスは従来どおり `'dmg'`
- 挙動（GitHub Releases へ 302）は変えない。スコープ外かつ AC にない
- `schema/schema.sql` の fallback 列コメントにも新値を書く

## 残差分 2: 直近で 0 件であることを読めるようにする（AC #4）

配信面のフォールバック表は**全期間の累計**なので、一度でも発生すると
「直近は 0 件」が永久に読めない。

- `eventBreakdowns` の既存 1 クエリの SELECT へ `MAX(timestamp)` を足し、
  経路ごとの**最終発生時刻（JST）**を列として出す。GROUP BY は変えないので
  行数もクエリ本数も増えない（`test/query-count.test.ts` の上限に触れない）
- 直近 N 日の件数を別に引く案は採らない。クエリが 1 本増える上に、
  「最後にいつ落ちたか」のほうが停止判断（TASK-489）に直接効く
- `byFallback` だけ `Split & { lastSeenAt: number | null }` にする。
  `Split` に optional を足すとホスト別の表と意味が混ざる

## 設計レビュー（/review-design、実装前に実施）

1. 判定の真実の源: 経路の区別を「R2 の応答が空か」ではなく
   「resolveDMGKey が null を返した」という**事実**で分ける。現状は同じ 302 という
   *形*で丸めていたのが問題だった
2. 既存の不変条件: refine（fallback ⇔ kind=github_fallback）は enum 値を増やしても不変。
   ただし新値の導入前に記録された `'dmg'` 行は「R2 欠落 + 不正リクエスト」の混合。
   遡って分離できないので schema.sql のコメントにその旨を残す
3. 消費経路の全列挙: fallback 値の消費側は (a) schema.sql のコメント、
   (b) 配信面の表（ラベルは enum 値をそのまま出しており対応表は無い）、
   (c) テスト の 3 箇所。日本語ラベルの対応表を新設しない（増やすと片方だけ直る）
4. 新しい状態の表示: 「一度も発生していない経路」は行として出ない。既存の
   `データなし` 表示がそのまま該当する。最終発生時刻が null になる行は生じない
   （byFallback は発生した行だけから作るため）
5. ライフサイクル・順序: 変化なし。SELECT へ集計列を足すだけで GROUP BY は不変
6. 高頻度経路のコスト: serveDMG に分岐 1 個。MAX(timestamp) は同じ全表スキャンに
   乗るだけで追加スキャンは無い
7. 測るものと守るもの: AC #4 の「直近 0 件」を最終発生時刻で担保する
8. 非同期の世代管理: 該当なし（SSR で、非同期に差し替わる表示状態が無い）
9. 決めたことを守らせるもの: 「不正リクエストを dmg として数えない」を破ると落ちる
   テストを置く（不正タグで `dmg-invalid` が記録され、かつ `dmg` が記録されないこと）
10. 型グループの行数: 該当なし（Swift ではない）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容

TASK-495 の記録・集計・表示の骨格は PR #534 / #537 で既に入っていた（`git log -S github_fallback -- site/` で確認）。本タスクで足したのは残っていた 2 点。

### 1. 不正リクエストと R2 欠落の分離（AC #3）

- `fallbackRouteSchema` に `'dmg-invalid'` を追加（`src/schema.ts:80`）
- `serveDMG` は `resolveDMGKey` が null のときだけ `'dmg-invalid'` を記録する
  （`src/routes/public.tsx`）。応答は従来どおり GitHub へ 302 で、挙動は変えていない
- `schema/schema.sql` の fallback 列コメントに新値と、**導入前の `'dmg'` 行は
  両者の混合で遡って分離できない**旨を記載

### 2. 「直近は落ちていない」を読めるようにする（AC #4）

- `eventBreakdowns` の既存 1 クエリの SELECT へ `MAX(timestamp)` を足し、
  `FallbackSplit = Split & { lastSeenAt: number }` として返す（`src/analytics.ts`）。
  GROUP BY は変えていないのでクエリ本数も行数も増えない
- 配信面に専用の `FallbackTable` を置き「最後に発生 (JST)」列を出す
  （`src/views/dashboard.tsx`）。`SplitTable` は列が違うので流用しない
- `Split` に optional を足さなかったのは、ホスト別の表が「0 件の既知ホストも行として
  残す」表で、最終発生時刻を持たない行が常に混ざるため

### 決めたことを守らせるもの（設計レビュー項目 9）

- `test/public.test.ts`「不正なタグ・ファイル名は dmg ではなく dmg-invalid として記録する」。
  **修正を戻して落ちることを確認済み**（`fallback = 'dmg' as const` に戻すとこの 1 件だけ失敗）
- `test/analytics.test.ts` に「経路ごとに最後に発生した時刻を返す」（古い行を後から
  入れて挿入順ではなく MAX で決まることを見る）と「不正なリクエストと R2 の欠落を
  別の経路として数える」
- `test/dashboard.test.ts` に「経路別に最後に発生した時刻を出す」

### 検証（実測）

- `npx vitest run`: 12 files / 347 tests 全 pass
- `npx tsc --noEmit`: エラーなし
- `npm run lint` / `npm run format:check`: 指摘なし
- `npm run migrate:diff`: `The migration directory is synced with the desired state`
  （schema.sql の変更はコメントのみでマイグレーション不要）
- `markdownlint-cli2`: 0 issues

### スコープ外にしたもの

- `/dl/:tag/:file` は不正なタグでも `kind='download'` を記録する（既存挙動）。
  AC #5「既存のダウンロード指標の意味と数値が変わらない」に反するため触っていない
- 不正リクエストを 302 ではなく 404 にする挙動変更。AC に無く、導線を途切れさせない
  既存方針とも別の判断になる
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
R2 から配れず GitHub へ落ちた配信のうち、検証で弾いた不正リクエスト（dmg-invalid）を R2 の欠落（dmg）から分離し、配信面のフォールバック表に経路ごとの最終発生時刻 (JST) を追加した。前者は serveDMG の resolveDMGKey が null かどうかという事実で分け、後者は既存の内訳クエリの SELECT に MAX(timestamp) を足しただけでクエリ本数を増やしていない。記録・集計・表示の骨格自体は PR #534 / #537 で既に入っていた。検証は vitest 347 件 pass・tsc/lint/format 指摘なし・migrate:diff で差分なし、加えて新規テストが修正を戻すと落ちることを実測した。
<!-- SECTION:FINAL_SUMMARY:END -->
