---
id: TASK-538.1
title: 紹介サイトに記事ページの器を用意する
status: To Do
assignee: []
created_date: '2026-08-22 13:05'
updated_date: '2026-08-22 13:19'
labels: []
milestone: m-10
dependencies: []
parent_task_id: TASK-538
priority: medium
ordinal: 783000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
site に記事（ユースケース・開発計画・リリース記事）を載せる置き場が無い。現状の公開ページは landing / features / releases の 3 つだけ（site/src/lib/pages.ts:37 の SITE_PAGES）。

## Zola を導入しない理由（2026-08-22 に検討・却下）

会社サイトは Zola を使っているが、befold のサイトには持ち込まない。

- site/src/routes/public.tsx:45-55 — 公開ページは SITE_PAGES を回して登録され、**全ページで recordEvent({kind:'visit'}) を打ち、Cache-Control: no-store を付けている**。同ファイルのコメントに『キャッシュに載った応答は Worker を通らず計上できない』と明記。Zola の静的出力を配信すると記事だけアクセス計測が落ちる
- SITE_PAGES が単一の情報源で、そこから sitemap.xml の hreflang 相互リンク（public.tsx:225）と旧ホストのリダイレクト対象（site/src/lib/hosts.ts:62）が導出されている。別系統を持つと二重管理になる
- 数件規模なら PAGE_VIEWS の表（public.tsx:65）に足す方が軽い。この表は『ページを足したら型が漏れを指す』形に意図して作られている

## 設計判断が要る点

記事が増えると Page 型の union が膨らむ。『記事を SITE_PAGES に直接並べる』か『記事レジストリを作って sitemap・計測・リダイレクト列挙へ差し込む』かを決める必要がある。多言語（entry.lang / variantsOf）をどう扱うかも同じ判断に含まれる（記事を日英両方作るのか、日本語のみとするのか）。

**実装着手前に /review-design を 1 回回すこと**（CLAUDE.md『実装着手前の設計レビュー』。新しい経路と値の持ち方を足す変更に当たる）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 記事ページが SITE_PAGES 由来の仕組み（visit 計測・no-store・sitemap の hreflang・旧ホストのリダイレクト列挙）にすべて乗る
- [ ] #2 記事を 1 本足す手順が、既存ページと同じ型の漏れ検知（Record<Page, ...> と同等）で守られる
- [ ] #3 多言語の扱いを決め、決めた内容が Notes に残る
- [ ] #4 着手前に /review-design を回し、結果を Implementation Plan に反映してある
- [ ] #5 befold analytics のダッシュボードで、ユースケース記事のアクセス数をページ別に確認できる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## analytics の AC を足した理由（2026-08-22）

記事ページを SITE_PAGES に載せれば visit イベント自体は記録されるが、**ダッシュボードの『ページアクセス』指標には出ない**。

- `site/src/analytics.ts:60` — `visit: { kind: 'visit', source: null, page: '/' }`。既定の visit 指標は LP（`/`）だけを数える。同 :59 のコメントに『意味と過去データの連続性を保つために page で絞る。ページ別の内訳は別系列』とある
- したがって記事のアクセス数は**ページ別の内訳系列**の側で見えるようにする必要がある。器を作る時点でここまで通すこと（記事を公開してから『数が見えない』と気づく形にしない）

この制約は Zola を却下した理由（静的配信だと Worker を通らず計上できない）と対になっている。計測に載せることが器の要件そのもの。
<!-- SECTION:NOTES:END -->
