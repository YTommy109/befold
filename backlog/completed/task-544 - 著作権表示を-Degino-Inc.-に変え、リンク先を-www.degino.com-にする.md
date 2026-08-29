---
id: TASK-544
title: 著作権表示を Degino Inc. に変え、リンク先を www.degino.com にする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-23 07:57'
updated_date: '2026-08-23 13:10'
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
- [x] #1 紹介サイトのフッターの著作権表示が Degino Inc. で、リンク先が https://www.degino.com になっている
- [x] #2 トップページの JSON-LD の author が Degino Inc. を指している
- [x] #3 アプリの About パネルの著作権表示が Degino Inc. で、リンク先が https://www.degino.com になっている
- [x] #4 www.degino.com の URL リテラルが AppLinks に集約されており、AboutView に直書きされていない
- [x] #5 site のテストと BefoldApp の swift test が通り、swiftlint が main とのベースライン差分ゼロ
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. site/src/views/shared.tsx: フッターを 'MIT License · © 2026 <a href=https://www.degino.com>Degino Inc.</a>' に変更
2. site/src/views/landing.tsx: JSON-LD の author を { '@type': 'Organization', name: 'Degino Inc.', url: 'https://www.degino.com' } に変更（Person のままだと型と実体がずれるため）
3. BefoldKit/AppLinks.swift: author を company へ改名し、値を https://www.degino.com にする。ホスト名リテラルは AppLinks に集約する規約に従う
4. befold/App/AboutView.swift: Link("Tommy109", destination: AppLinks.author) を Link("Degino Inc.", destination: AppLinks.company) に変更
5. befoldTests/AppLinksTests.swift: company の host を検証するテストを追加
6. LICENSE: 著作権者を Degino Inc. に変更（ユーザー承認済み。起票時は「決めること」だった）
7. 検証: site の test/lint/format、BefoldApp の swift test、swiftlint ベースライン差分ゼロ
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決めたこと（起票時の「決めること」への回答）

- JSON-LD の author は `'@type': 'Organization'` へ変更（Person のまま名前だけ法人にすると型と実体がずれるため）
- `AppLinks.author` → `AppLinks.company` へ改名（author は人を指す名前で、指し先が法人サイトになると意味がずれる）。参照は AboutView.swift の 1 箇所のみで影響は局所
- LICENSE の著作権者も `Copyright (c) 2026 Degino Inc.` へ変更（ユーザー承認済み。起票時は AC 外だったのでスコープ追加として確認した）
- REPO_URL / github.com/YTommy109/befold はリポジトリを指すもので別物なので変えていない

## 変更

- site/src/views/shared.tsx:245 フッターのクレジットを Degino Inc. / https://www.degino.com へ
- site/src/views/landing.tsx:107 JSON-LD の author を Organization へ
- BefoldKit/AppLinks.swift author → company、値を https://www.degino.com に。siteOrigin（befold.degino.com）とは別ホストなので組み合わせず独立した定数にした旨を doc コメントに明記
- befold/App/AboutView.swift:44 Link("Degino Inc.", destination: AppLinks.company)
- befoldTests/AppLinksTests.swift company の host を検証するテストを追加
- LICENSE 著作権者

## 検証（実測）

- AC#1/#2: 一時テストで /・/en・/features・/en/features・/releases・/usecases を worker.fetch でレンダリングし、実 HTML を確認（確認後にテスト削除）。フッターは全 6 経路で `<a href="https://www.degino.com">Degino Inc.</a>`、JSON-LD の author は / と /en で `{"@type":"Organization","name":"Degino Inc.","url":"https://www.degino.com"}`
- AC#3: xcodebuild で .app をビルドして起動し、About パネルを実機で目視確認 → `Copyright © 2026 Degino Inc.`。osascript による自動ダンプは assistive access が無く不可だったため手動確認
- AC#4: `git grep 'degino.com' -- '*.swift'` でプロダクトコードのリテラルは AppLinks.swift のみ（siteOrigin と company）。AboutView に直書きなし
- AC#5: site は vitest 394 passed / oxlint --type-aware 指摘なし / oxfmt --check 通過。BefoldApp は swift test 1701 tests in 270 suites passed（新規テスト含む）。swiftlint はルール×ファイルの正規化比較で main 42 / HEAD 42、真の新規ゼロ・解消ゼロ。swiftformat fix は 0 files formatted
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
著作権表示を個人名 Tommy109 から法人 Degino Inc. へ、リンク先を https://www.degino.com へ変更。対象は紹介サイトのフッター、トップページの JSON-LD（author を Person → Organization）、アプリの About パネル、LICENSE の 4 箇所。ホスト名リテラルは AppLinks に集約する規約に従い AppLinks.author を company へ改名して値を移した。レンダリング HTML の実測（6 経路）、About パネルの実機目視、site のテスト/lint/整形、swift test 1701 passed、swiftlint ベースライン差分ゼロで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
