---
id: TASK-542
title: 紹介サイトに全ページ共通のナビゲーションバーを置く
status: Done
assignee: []
created_date: '2026-08-23 07:56'
updated_date: '2026-08-23 13:26'
labels: []
milestone: m-10
dependencies: []
type: feature
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
- [x] #1 トップページのヘッダーから記事一覧（/usecases）へ 1 クリックで到達できる
- [x] #2 全ページ・両言語で同じナビゲーションが出る
- [x] #3 ナビの各リンクが現在の言語のパスを指す（en では /en 配下）
- [x] #4 現在地がナビ上で分かる
- [x] #5 ナビの項目にパスをハードコードしていない（pathFor と articles.ts から組む）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. pages.ts に navPagesFor(lang) を足し、FIXED_PAGES から現在言語のナビ項目を導出する
2. shared.tsx に SiteNav を足し、SiteHeader のタイトルと言語切替の間に置く。ラベルは Record<FixedPage, Localized> で付け忘れを型で落とす
3. 現在地は言語切替と同じく aria-current="page"。記事ページはナビ項目を持たないのでどれも current にしない（一覧へはパンくずが担当）
4. features/releases/usecases のパンくず「← トップページへ戻る」はナビと重複するので撤去。landing の section-more は文脈付き CTA なので残す
5. style.css に .site-nav / .site-nav-link と 600px 以下の調整を足す
6. public.test.ts に全ページ×両言語のナビ出現・aria-current・en の /en 配下を実 HTML で検証するテストを足す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
決めたこと（タスクの「決めること」への回答）:

- **ナビ項目**: FIXED_PAGES の 4 論理ページ（/ ・/features ・/releases ・/usecases）。記事個別ページは SITE_PAGES 側にしか無いので構造的に外れ、/download はそもそも pages.ts に載せてはならないものなので、ナビ用の除外リストを持たなくてよい（navPagesFor は FIXED_PAGES を lang で絞るだけ）。固定ページを足すと自動でナビに出る形なので、その doc コメントに「出したくないページができたら除外条件ではなく FIXED_PAGES 側へ印を足す」と明記した。
- **現在地**: 言語切替と同じく aria-current="page"。記事ページはナビ項目を持たないためどれも current にならない（一覧へ戻る動線は article.tsx のパンくずが持つ）。
- **本文の既存リンク**: features/releases/usecases の先頭パンくず「← トップページへ戻る」はナビと完全に重複するので撤去。landing.tsx の section-more（全機能一覧へ / 過去バージョンへ）は文脈付き CTA なので残した。article.tsx のパンくずも階層表現として残した。
- **ラベルの置き場**: shared.tsx の Record<FixedPage, Localized>。固定ページを足したときのラベル付け忘れが型で落ちる。

実測: npx tsc --noEmit（エラー 0）/ npm run lint（oxlint --type-aware、指摘 0）/ npx vitest run（13 files 407 tests passed。TASK-542 で 13 件追加）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
全ページ共通のヘッダーナビを追加した。項目は pages.ts の navPagesFor(lang) が FIXED_PAGES から導出し、リンク先は SITE_PAGES のパスをそのまま使う（ハードコードなし）。現在地は aria-current="page"。重複した features/releases/usecases のトップ戻りパンくずを撤去。public.test.ts に全ページ×両言語の実 HTML 検証を 13 件追加し、vitest 407 件・tsc・oxlint がすべて通ることを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
