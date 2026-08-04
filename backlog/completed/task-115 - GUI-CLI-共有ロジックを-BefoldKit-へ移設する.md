---
id: TASK-115
title: GUI/CLI 共有ロジックを BefoldKit へ移設する
status: Done
assignee: []
created_date: '2026-07-23 12:31'
updated_date: '2026-07-23 13:03'
labels:
  - refactor
  - cli
dependencies:
  - TASK-112
priority: high
ordinal: 103000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLICheckCommand.defaultResolveFileToOpen と DirectoryLister.resolveFileToOpen(TASK-110)、CLIBookmarkDefaults と BookmarkStore/normalizedPathKey(TASK-111)がそれぞれ独立実装になっている。原因は共有ロジックが befold(GUIアプリ)ターゲット配下にあり、BefoldCLI ライブラリから参照できないこと。BefoldKit は befold・BefoldCLI 双方から参照可能な既存の共有ライブラリであり、新規依存を増やさずにここへ移設できる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サポート形式優先でファイルを解決するロジックが BefoldKit に一本化され、DirectoryLister と CLICheckCommand の双方がそこへ委譲している
- [x] #2 パス正規化(symlink解決)ロジックが BefoldKit に一本化され、BookmarkStore と CLIBookmarkDefaults の双方がそこへ委譲している
- [x] #3 UserDefaults のブックマークキー名が共有定数として一箇所で定義されている
- [x] #4 サポート形式・非サポート形式混在ディレクトリでの --check テストが存在する
- [x] #5 シンボリックリンク経由のブックマーク登録・参照が CLI/GUI 間で一致することを検証するテストが存在する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldKit に共有ロジックを追加する:
   - URL+NormalizedPathKey.swift: befold/App/URL+PathKey.swift の normalizedPathKey を移設
   - SupportedFileResolver.swift: resolveFileToOpen のサポート形式優先ロジックを新設(FileReading+FileType流用)
   - BookmarkStore.swift: befold/App/BookmarkStore.swift をそのまま移設・public化
2. befold 側: URL+PathKey.swift・BookmarkStore.swift を削除し、normalizedPathKey/BookmarkStore を使う各ファイルに import BefoldKit を追加(未importの箇所のみ)。DirectoryLister.resolveFileToOpen は SupportedFileResolver へ委譲。
3. CLICheckCommand.defaultResolveFileToOpen は SupportedFileResolver へ委譲する実装に置き換える。
4. befold-cli 側: CLIBookmarkDefaults enum を削除し、addBookmark ワイヤリングを BookmarkStore(defaults: UserDefaults(suiteName: "com.degino.befold") ?? .standard).add($0) に置き換える。befold-cli の Package.swift/project.yml 依存に BefoldKit を追加。
5. テスト:
   - befoldTests/BookmarkStoreTests.swift にシンボリックリンク正規化のテストを追加(AC#5の片側)
   - befoldCLITests に --bookmark のシンボリックリンク経由テスト(実際の BefoldCLICommand.run 経由、AC#5のCLI側)と、--check の混在ディレクトリでの既定解決テスト(AC#4)を追加
6. 各ターゲットの既存テスト(BookmarkStoreTests, CLIBookmarkCommandTests, ViewerWindowControllerTests 等)の import 更新、swift build && swift test で確認、xcodegen generate && xcodebuild build -scheme befold/-scheme befold-cli で確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装は当初計画からさらに単純化した: CLIBookmarkDefaults(befold-cli 独自実装)を削除し、BookmarkStore 自体を BefoldKit に移設して GUI/CLI が同一クラスを共有する形にした(ユーザー承認済み)。UserDefaults キー名の共有(AC#3)は単一クラス化により自動的に満たされる(重複する定数が存在しない)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BefoldKit に SupportedFileResolver(サポート形式優先のファイル解決)・URL.normalizedPathKey(symlink 解決)・BookmarkStore(ブックマーク永続化)を追加し、GUI(befold: DirectoryLister/各種ストア)と CLI(BefoldCLI: CLICheckCommand、befold-cli: BefoldCLICommand)の双方をそこへ委譲させた。CLIBookmarkDefaults(befold-cli 独自の重複実装)は削除し、GUI と全く同じ BookmarkStore クラスを UserDefaults(suiteName: "com.degino.befold") で使うことで、キー名の重複自体を排除した。検証: swift build / swift test(601 tests, 76 suites, all green)、xcodegen generate && xcodebuild build -scheme befold / -scheme befold-cli(いずれも BUILD SUCCEEDED)、SwiftLint/SwiftFormat 実行済み(新規違反なし)。TASK-110・TASK-111 はこの一本化によって解消される。
<!-- SECTION:FINAL_SUMMARY:END -->
