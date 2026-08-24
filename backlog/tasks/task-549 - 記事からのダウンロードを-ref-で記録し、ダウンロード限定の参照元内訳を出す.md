---
id: TASK-549
title: 記事からのダウンロードを ?ref= で記録し、ダウンロード限定の参照元内訳を出す
status: To Do
assignee: []
created_date: '2026-08-24 14:39'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 797000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布サイトのアナリティクスで「どの記事がダウンロードに繋がったか」が測れない。事例記事の末尾にはダウンロード導線（`{{cta}}`）が置いてあるが、記録の上では LP のボタンと区別が付かない。

## 現状（2026-08-24 に実測・コード確認）

3 つが独立に効いていて、どれか 1 つを直しても測れない。

| 何が | どうなっている | 場所 |
| --- | --- | --- |
| `source` | `'lp' \| 'sparkle' \| 'archive'` の 3 値のみ。`/download` は**どこから押されても `'lp'` 固定** | `site/src/schema.ts:39` / `site/src/routes/public.tsx:156` |
| `page` | download イベントには載らない。`page` を持つのは visit だけで、`byPage` は `kind === 'visit'` に絞ってから畳む | `site/src/analytics.ts:771` |
| `referrer` | 自サイト内の遷移は `null`。外部でも `origin` だけでパスは保存しない | `site/src/lib/referrer.ts:47`, `:49` |

visitor 単位でイベントを突き合わせる集計は `updateConversion`（`site/src/analytics.ts:1145-1190`）の 1 つだけで、対象は `update_check → update_download` のみ。軸は `day` と `channel` で、`page` は SELECT にも GROUP BY にも無い。ダッシュボードにファネル表示も無い。

## やること

読む側は既に実装済みで、`/download?ref=xxx` を踏めば `xxx` がそのまま referrer 列に入る（`site/src/events.ts:103` → `site/src/lib/referrer.ts:31-34`、64 文字で切り詰め）。`/download` 固有の除外も無い。**にもかかわらず `?ref=` を付けているリンクが 1 つも無い**のが現状。

1. **記事の CTA に `?ref=` を付ける。** 記事からのダウンロードリンクは `site/src/views/article-bodies.ts` の `{{cta}}` 展開 1 箇所に集約されているので、そこで記事 slug を載せる。スキーマ変更も移行も不要。
2. **ダウンロード限定の参照元内訳を足す。** いまの「参照元別」は `breakdown(db, 'referrer')` を**指標フィルタ無し**で呼んでいる（`site/src/analytics.ts:1334`）ため、記事 slug が Google などの外部流入元と同じ表に混ざる。`breakdown()` は `metric` 引数を既に持つ（`site/src/analytics.ts:619-637`）ので、`breakdown(db, 'referrer', 'download')` を別カードとして出す。

## 着手前に決めること

- **LP / features のボタンにも `?ref=` を付けるか。** 付けないと、それらのダウンロードは referrer が `NULL` になり、`breakdown()` の `WHERE ${column} IS NOT NULL` で新カードから丸ごと落ちる。結果「記事からのダウンロードしか出ない表」になり、記事の寄与が全体の何割かを読めない。付けるなら `lp` / `features` のような値を決めること。
- **`ref` の値の付け方。** 記事は `Article['page']`（`/usecases/medical-expenses`）から導けるが、64 文字の切り詰めがあるので slug だけにするか、接頭辞を付けるか（`usecase-medical-expenses` 等）を決める。値をリテラルで散らかさず、`lib/pages.ts` の `pathFor` と同じく 1 箇所から導く形にすること。
- **`?ref=` は外部参照元を上書きする**（`resolveReferrer` の最優先分岐）。download イベントの referrer は内部遷移で元々 `null` なので失うものは無いが、この性質は把握した上で入れること。

## 背景

TASK-548 の作業中に「事例記事では宣伝を前に出したくないので CTA を外したい」という話が出て、一度外す変更を入れた。その後「記事がダウンロードに結びついたか計測できるなら残す」という判断で戻したが、調べた結果**その計測は成立していなかった**。CTA を残すか外すかの判断を、実際に測れる状態にしてからやり直せるようにするのがこのタスクの狙い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 記事の CTA からのダウンロードが、LP / features からのダウンロードと区別して数えられる
- [ ] #2 ダッシュボードにダウンロード限定の参照元内訳が出る（既存の全 kind 混在の「参照元別」とは別のカード）
- [ ] #3 ref の値がリテラルの散らかしではなく 1 箇所から導かれている（記事を足したときに付け忘れが起きない形）
- [ ] #4 上の「着手前に決めること」3 点の結論が Implementation Notes に残っている
- [ ] #5 site の vitest が通り、?ref= 付きのリンクが出ることと、参照元内訳が download に絞られていることをテストが固定している
<!-- AC:END -->
