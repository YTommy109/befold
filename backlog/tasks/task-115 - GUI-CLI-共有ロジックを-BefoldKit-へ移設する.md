---
id: TASK-115
title: GUI/CLI 共有ロジックを BefoldKit へ移設する
status: To Do
assignee: []
created_date: '2026-07-23 12:31'
updated_date: '2026-07-23 12:31'
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
- [ ] #1 サポート形式優先でファイルを解決するロジックが BefoldKit に一本化され、DirectoryLister と CLICheckCommand の双方がそこへ委譲している
- [ ] #2 パス正規化(symlink解決)ロジックが BefoldKit に一本化され、BookmarkStore と CLIBookmarkDefaults の双方がそこへ委譲している
- [ ] #3 UserDefaults のブックマークキー名が共有定数として一箇所で定義されている
- [ ] #4 サポート形式・非サポート形式混在ディレクトリでの --check テストが存在する
- [ ] #5 シンボリックリンク経由のブックマーク登録・参照が CLI/GUI 間で一致することを検証するテストが存在する
<!-- AC:END -->
