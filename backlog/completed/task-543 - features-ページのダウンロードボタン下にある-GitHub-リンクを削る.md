---
id: TASK-543
title: features ページのダウンロードボタン下にある GitHub リンクを削る
status: Done
assignee: []
created_date: '2026-08-23 07:57'
updated_date: '2026-08-23 12:42'
labels: []
milestone: m-1
dependencies: []
type: chore
ordinal: 792000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`site/src/views/features.tsx` の末尾「動作要件」セクションで、ダウンロードボタンの直下に GitHub リンクが 1 本置かれている。

```tsx
<a href={DOWNLOAD_PATH} class="btn-primary">Mac 版をダウンロード</a>
<p class="hero-note">
  <a href={REPO_URL}>GitHub</a>
</p>
```

同じ GitHub へのリンクが、すぐ下のフッター（`shared.tsx` の `SiteFooter`）と、全ページ共通の GitHub リボン（`SiteHeader`）にもある。同一画面内に 3 本あり冗長。

この `<p class="hero-note">` を削る。フッターとリボンは残す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 features ページのダウンロードボタン下の GitHub リンクが無くなっている（ja / en とも）
- [x] #2 フッターと GitHub リボンの GitHub リンクは残っている
- [x] #3 site のテスト・lint・整形チェックが通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
features.tsx の requirements セクションから <p class="hero-note"><a href={REPO_URL}>GitHub</a></p> を削除。未使用になった REPO_URL の import も外した。検証: 一時テストで /features・/en/features を worker.fetch でレンダリングし、requirements セクション内に github.com が無いこと、ページ全体には残ること（ribbon shared.tsx:211 / footer :244,:245 の計 3 箇所）を確認。site: vitest 394 passed / oxlint --type-aware 指摘なし / oxfmt --check 通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
features ページ動作要件セクションの重複した GitHub リンクを削除。ribbon と footer のリンクは維持。レンダリング HTML の実測と site のテスト・lint・整形チェックで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
