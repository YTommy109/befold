---
id: TASK-135
title: 同名 CLIInstanceRouter.swift の解消と GUI 側境界アダプタを実態に合わせて改名する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:40'
updated_date: '2026-07-25 01:34'
labels:
  - refactor
  - structural
  - cli
dependencies: []
priority: high
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold/App/CLIInstanceRouter.swift は全 8 行で、中身は extension CLIOpenOptions の viewerSortOrder(CLIオプション→Viewer 層 SortOrder 変換)だけであり CLIInstanceRouter 型は存在しない。本物のルーターは BefoldCLI/CLIInstanceRouter.swift。同名 2 ファイルが grep/ナビゲーションを紛らわしくし、GUI 側ファイル名が内容(境界変換アダプタ)と一致していない。構造レビュー(2026-07-25)で検出。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GUI 側ファイルが内容に合う名前(例: CLIOpenOptions+ViewerSortOrder.swift)へ改名され、同名 2 ファイルが解消している
- [x] #2 project.yml / Package.swift のソース参照とビルドが更新後も通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. befold/App/CLIInstanceRouter.swift を CLIOpenOptions+ViewerSortOrder.swift へ git mv する。
2. 内容が境界アダプタであることが読んで分かるようドキュメントコメントを追加する。
3. project.yml / Package.swift のソース参照はディレクトリ指定のため変更不要であることを確認し、xcodegen generate と swift test で通ることを確かめる。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実態の確認: GUI 側 befold/App/CLIInstanceRouter.swift は全 8 行で、中身は extension CLIOpenOptions の viewerSortOrder のみ。CLIInstanceRouter 型は含まれておらず、本物のルーターは BefoldCLI/CLIInstanceRouter.swift にある(CLI バイナリ分離でルーター実装が移動した際にファイル名だけが残ったもの)。

対応:
- befold/App/CLIInstanceRouter.swift → befold/App/CLIOpenOptions+ViewerSortOrder.swift へ git mv。git ls-files で CLIInstanceRouter.swift の該当が 1 件(BefoldCLI 側のみ)になったことを確認した。
- ファイル名だけでなく中身も読んで分かるよう、境界アダプタであること(CLI 側は『指定なし』を表現できるが Viewer 側の SortOrder は常に具体値を持つ、その差を GUI の入口で都度書き分けずに済ませるための集約点)をドキュメントコメントに明記した。viewerSortOrder の呼び出し元は AppDelegate(2 箇所)と SessionRestorer(1 箇所)。

AC#2 の確認: project.yml(sources: - path: befold)も Package.swift もディレクトリ指定のため、ファイル名変更に伴う設定更新は不要だった。xcodegen generate が成功し、swift test が 615 tests / 86 suites pass、swiftformat --lint も 0/184。befold.xcodeproj は gitignore 対象のため差分は改名のみ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GUI 側 befold/App/CLIInstanceRouter.swift には CLIInstanceRouter 型が無く、中身は CLIOpenOptions → Viewer 層 SortOrder の変換だけだった。実態に合わせて CLIOpenOptions+ViewerSortOrder.swift へ改名し、同名 2 ファイルによる grep/ナビゲーションの紛らわしさを解消した。あわせて境界アダプタである旨をドキュメントコメントに残した。project.yml / Package.swift はどちらもディレクトリ指定のため設定更新は不要で、xcodegen generate・swift test(615 tests / 86 suites pass)・swiftformat --lint(0/184)で確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
