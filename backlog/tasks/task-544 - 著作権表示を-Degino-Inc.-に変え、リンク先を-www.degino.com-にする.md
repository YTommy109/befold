---
id: TASK-544
title: 著作権表示を Degino Inc. に変え、リンク先を www.degino.com にする
status: To Do
assignee: []
created_date: '2026-08-23 07:57'
updated_date: '2026-08-23 08:33'
labels: []
dependencies: []
type: chore
ordinal: 793000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
著作権表示が個人名（Tommy109）と GitHub プロフィールへのリンクになっている。法人名 Degino Inc. と `https://www.degino.com` に変える。

## 対象（実測、2026-08-23）

| 場所 | 現在 |
|---|---|
| `site/src/views/shared.tsx:244-245` | `MIT License · © 2026 <a href="https://github.com/YTommy109">Tommy109</a>` |
| `site/src/views/landing.tsx:107` | JSON-LD の `author: { '@type': 'Person', name: 'Tommy109', url: 'https://github.com/YTommy109' }` |
| `BefoldApp/befold/App/AboutView.swift:43-44` | `Text("Copyright © 2026")` + `Link("Tommy109", destination: AppLinks.author)` |
| `BefoldApp/BefoldKit/AppLinks.swift:41` | `AppLinks.author = https://github.com/YTommy109` |

## 決めること

- JSON-LD の `author` を `'@type': 'Organization'` に変えるか（`Person` のままで名前だけ変えると型と実体がずれる）
- `AppLinks.author` を改名するか（`author` は人を指す名前。会社を指すなら `AppLinks.company` 等）。リポジトリ URL（`REPO_URL` / `github.com/YTommy109/befold`）は別物なので変えない
- ライセンス表記（MIT License）の扱い。LICENSE ファイル内の著作権者も合わせるか

## 注意

`AppLinks.siteOrigin` のコメントにあるとおり、アプリ側のホスト名リテラルは `AppLinks` に集約する規約。`www.degino.com` を AboutView に直書きしない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 紹介サイトのフッターの著作権表示が Degino Inc. で、リンク先が https://www.degino.com になっている
- [ ] #2 トップページの JSON-LD の author が Degino Inc. を指している
- [ ] #3 アプリの About パネルの著作権表示が Degino Inc. で、リンク先が https://www.degino.com になっている
- [ ] #4 www.degino.com の URL リテラルが AppLinks に集約されており、AboutView に直書きされていない
- [ ] #5 site のテストと BefoldApp の swift test が通り、swiftlint が main とのベースライン差分ゼロ
<!-- AC:END -->
