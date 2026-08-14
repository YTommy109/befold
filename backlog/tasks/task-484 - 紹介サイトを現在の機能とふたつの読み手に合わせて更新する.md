---
id: TASK-484
title: 紹介サイトを現在の機能とふたつの読み手に合わせて更新する
status: To Do
assignee: []
created_date: '2026-08-14 13:04'
updated_date: '2026-08-14 13:22'
labels: []
milestone: m-1
dependencies: []
documentation:
  - site/README.md
priority: high
type: feature
ordinal: 705000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold.degino.com（`site/` の Cloudflare Worker、Hono + hono/jsx の SSR）の内容が実装から遅れている。紹介文の実質的な最終更新は 2026-08-09 の `ce37df6d`（/features ページ新設）で、中核コピーは 2026-07-30 の `78cf320d` 由来。以後の `9a1ef1fc`（2026-08-14, #518）は URL とドメインの移行だけで文言に触れていない。

その間に v1.13.0 で **サイドバーの git ステータス表示・ソース表示での git 差分表示・サイドバーのツリー展開** が開発ビルド限定から stable へ到達したが、サイトにはこれらの記載が一切無い。現在サイトにある git 関連の言及は「git を知っているリンク解決」1 件だけで、これは Markdown 内リンクの解決に git 追跡ファイルを使う話であり差分表示ではない。

あわせて次の 2 点を扱う。

- **Obsidian への言及を削除する。** LP の 3 番目の philosophy セクション（`site/src/views/landing.tsx:155` 日本語 / `:166` 英語）にある 2 箇所が全て。
- **読み手をふたつ同格に併記する。** befold は設計レビュー・コードレビューの多いエンジニア向けに開発しているが、エンジニアでなくても Markdown を読む立場の人（ライター・企画・レビュアーなど）にとっての利点がある。この 2 つの入口を同じ重みで並べる構成にする。

**未実装の機能をサイトに書かないこと。** レンダリング表示のままの差分表示（TASK-483）と、比較基準の切り替え UI（TASK-353）はいずれも未実装。現在の差分はソース表示のみで、比較基準はデフォルトブランチとの merge-base に固定されている。

文言の単一情報源は `site/src/views/shared.tsx` の `FEATURES` / `MORE_FEATURES` で、LP と /features の両方がこれを参照する。日英は 1 つの HTML に両方を埋め込み `lang` 属性と `hidden` で出し分ける構造のため、**追加・変更は必ず日英の両方に入れる**。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 v1.13.0 で stable になった git 機能（サイドバーの変更ファイル識別、ソース表示の差分表示）がサイトで紹介されている
- [ ] #2 Obsidian への言及がサイトのソースから無くなっている
- [ ] #3 エンジニア向けの訴求と、Markdown を読む立場の人向けの訴求が同格に並んでいる
- [ ] #4 未実装の機能（レンダリング差分・比較基準の切替）がサイトに書かれていない
- [ ] #5 日本語と英語の両方が同じ内容で更新されている
- [ ] #6 `site/` の既存テスト（vitest）と typecheck が通る
<!-- AC:END -->
