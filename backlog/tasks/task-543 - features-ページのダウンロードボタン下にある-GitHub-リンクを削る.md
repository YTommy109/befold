---
id: TASK-543
title: features ページのダウンロードボタン下にある GitHub リンクを削る
status: To Do
assignee: []
created_date: '2026-08-23 07:57'
updated_date: '2026-08-23 08:33'
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
- [ ] #1 features ページのダウンロードボタン下の GitHub リンクが無くなっている（ja / en とも）
- [ ] #2 フッターと GitHub リボンの GitHub リンクは残っている
- [ ] #3 site のテスト・lint・整形チェックが通る
<!-- AC:END -->
