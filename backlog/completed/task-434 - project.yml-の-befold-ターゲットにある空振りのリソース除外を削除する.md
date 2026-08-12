---
id: TASK-434
title: project.yml の befold ターゲットにある空振りのリソース除外を削除する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 12:59'
updated_date: '2026-08-11 23:00'
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
- [x] #1 project.yml の befold ターゲットから空振りの excludes が削除されている
- [x] #2 xcodegen generate 後に xcodebuild build -scheme befold が通る
- [x] #3 .app バンドルの中身が変更前と同じである（viewer 系リソースが befold ターゲット側へ二重に入っていない）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. befold/Resources の excludes 7 件が実在しないことを確認（済）
2. 変更前に xcodebuild build -scheme befold を実行し、.app の Contents/Resources 一覧をベースラインとして取得
3. project.yml から空振りの excludes ブロックを削除
4. xcodegen generate → 再ビルド、Resources 一覧を diff してゼロ差分を確認
5. コミット
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
project.yml の befold ターゲット `befold/Resources`（buildPhase: resources）にあった excludes 7 件（viewer.html / viewer-bundle.js / style.css / mermaid.min.js / github.css / github-dark.css / github-markdown.css）を削除。実測でいずれも BefoldApp/befold/Resources/ に存在しないことを確認済み（実在は AboutOGP.png / AppIcon.icns / Localizable.xcstrings / befold-review-skill.md の 4 件のみ）。
検証: 変更前後で xcodebuild build -scheme befold が BUILD SUCCEEDED。生成された befold.app 内の全ファイル一覧（107 件）を find で取得して diff → 差分ゼロ。xcodegen generate 後も .xcodeproj/project.pbxproj に差分は出なかった（除外対象が元から存在せず、pbxproj へ影響していなかったことの裏付け）。
Description が「10 個」としていた点は実際には 7 個で、viewer-main.js が漏れているという指摘も現行リストの 7 件基準では同様に成立する（本文の趣旨は変わらないため実装は同じ）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
befold ターゲットのリソース除外リストから、実在しないファイル 7 件の excludes を削除した。viewer 系リソースは BefoldKit/Resources へ移設済みで除外は空振りしていた。変更前後の xcodebuild ビルド成功と .app バンドル内ファイル一覧の完全一致（107 件、diff 差分ゼロ）で無影響を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
