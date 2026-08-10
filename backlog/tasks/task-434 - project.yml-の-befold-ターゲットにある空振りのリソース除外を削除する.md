---
id: TASK-434
title: project.yml の befold ターゲットにある空振りのリソース除外を削除する
status: To Do
assignee: []
created_date: '2026-08-10 12:59'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 118000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/project.yml:118-130` の `befold` アプリターゲットは `befold/Resources` に対して 10 個のファイルを `excludes` で列挙しているが、**そのいずれも該当ディレクトリに存在しない**。

`BefoldApp/befold/Resources/` の実際の中身は `AboutOGP.png` / `AppIcon.icns` / `Localizable.xcstrings` / `befold-review-skill.md` の 4 件のみで、viewer 系とベンダー JS/CSS は `BefoldApp/BefoldKit/Resources/` へ移設済み。リソース移設時の消し忘れ。

加えて、除外リストには `viewer-main.js` が**入っていない**（他 10 個は列挙されているのに漏れている）。仮にファイルが存在したままなら二重同梱していた形であり、リストが実態を追えていないことの傍証になる。

実害は現状ゼロだが、次にリソース構成を触る人が「この除外には意味がある」と誤読する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 project.yml の befold ターゲットから空振りの excludes が削除されている
- [ ] #2 xcodegen generate 後に xcodebuild build -scheme befold が通る
- [ ] #3 .app バンドルの中身が変更前と同じである（viewer 系リソースが befold ターゲット側へ二重に入っていない）
<!-- AC:END -->
