---
id: TASK-542
title: 紹介サイトに全ページ共通のナビゲーションバーを置く
status: To Do
assignee: []
created_date: '2026-08-23 07:56'
labels: []
dependencies: []
ordinal: 791000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在、ヘッダー（`site/src/views/shared.tsx` の `SiteHeader`）はタイトルと言語切替だけで、ページ間の動線を持っていない。ページ間リンクは各ページの本文末尾に散らばっている。

実測（2026-08-23、`grep -n "pathFor('/" site/src/views/*.tsx`）:

- `/usecases`（記事一覧）へのリンクは、記事ページのパンくず（`article.tsx:66`）以外どこにも無い。**トップページから記事一覧へ到達できない**
- `/features` と `/releases` へのリンクはトップページの下部にしかない（`landing.tsx:287` / `landing.tsx:331`）
- `/features`・`/releases`・`/usecases` の各ページからはトップへ戻るリンクのみ

`SITE_PAGES` に載る論理ページは `/`・`/features`・`/releases`・`/usecases` と記事。ヘッダーに共通のナビゲーションバーを置き、本文末尾に散らばった動線をそちらへ集約する。

## 決めること

- ナビに出す項目（記事は一覧へ 1 本にするか、記事ページも出すか）
- 現在地の示し方（言語切替と同じく `aria-current="page"` で揃えるか）
- 本文末尾の既存リンクを消すか残すか（消すならトップの導線設計を見直す必要がある）
- 項目の列挙をどこに置くか。`SITE_PAGES` から導出できるが、ナビに出したくないページ（記事個別・`/download`）があるため、そのまま使うと出しすぎる

## 制約

- 全ページが ja / en の 2 バリアントを持つ不変条件があるので、リンクは `pathFor(page, lang)` で組む（ハードコードしない）
- 記事一覧・記事のパスは `lib/articles.ts` が唯一の情報源。ナビ側にパスを書き写さない
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 トップページのヘッダーから記事一覧（/usecases）へ 1 クリックで到達できる
- [ ] #2 全ページ・両言語で同じナビゲーションが出る
- [ ] #3 ナビの各リンクが現在の言語のパスを指す（en では /en 配下）
- [ ] #4 現在地がナビ上で分かる
- [ ] #5 ナビの項目にパスをハードコードしていない（pathFor と articles.ts から組む）
<!-- AC:END -->
