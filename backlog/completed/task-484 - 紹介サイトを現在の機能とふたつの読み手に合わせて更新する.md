---
id: TASK-484
title: 紹介サイトを現在の機能とふたつの読み手に合わせて更新する
status: Done
assignee: []
created_date: '2026-08-14 13:04'
updated_date: '2026-08-16 03:24'
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
- [x] #1 v1.13.0 で stable になった git 機能（サイドバーの変更ファイル識別、ソース表示の差分表示）がサイトで紹介されている
- [x] #2 Obsidian への言及がサイトのソースから無くなっている
- [x] #3 エンジニア向けの訴求と、Markdown を読む立場の人向けの訴求が同格に並んでいる
- [x] #4 未実装の機能（レンダリング差分・比較基準の切替）がサイトに書かれていない
- [x] #5 日本語と英語の両方が同じ内容で更新されている
- [x] #6 `site/` の既存テスト（vitest）と typecheck が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
サブタスク 5 件（484.1〜484.5）がすべて Done。親の AC を実測で確認した。

- #1: shared.tsx:96-112 に「Git 差分表示」「変更ファイルがわかるサイドバー」の 2 枚を FEATURES として追加済み（TASK-484.2）。スクリーンショット 2 枚もカルーセルに追加済み（TASK-484.5）
- #2: `grep -rni obsidian site/src site/public` が 0 件
- #3: landing.tsx:143-190 で同じ .philosophy を使う 2 セクションが「コードを書く人へ」「Markdown を読む人へ」のラベルだけで分かれて並ぶ（TASK-484.4）
- #4: `grep -rn '比較基準|merge-base|レンダリング表示の差分|base branch' site/src` が 0 件。差分の記述は「ソースの差分」に限定されている
- #5: 追加した文言はすべて ja/en の対で定義されている（shared.tsx の FEATURES / MORE_FEATURES、landing.tsx の philosophy セクション）
- #6: site で `npx tsc --noEmit` クリーン、`npm test` 181 件成功（2026-08-16 実行）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
配布サイトを v1.13.0 時点の実装とふたつの読み手に合わせて更新した。git 機能（サイドバーの変更ファイル識別・ソース表示の差分・最近使ったリポジトリ）を FEATURES / MORE_FEATURES へ追加し、スクリーンショット 2 枚をカルーセルへ足した。LP の訴求は「コードを書く人へ」「Markdown を読む人へ」の 2 セクションを同格に並べる構成へ書き直し、Obsidian への言及を削除した。ショートカット表は実装に追随させた。検証: grep で Obsidian 0 件・未実装機能への言及 0 件、site の tsc クリーン、vitest 181 件成功、カルーセルは LP のレンダリング結果に screenshot-1〜8 が出ることを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
