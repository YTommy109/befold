---
id: TASK-344
title: ブランチで新規追加したファイルにサイドバーで A ではなく M が出る問題を修正する
status: To Do
assignee: []
created_date: '2026-08-06 07:52'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 610000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーのファイル一覧の git ステータスバッジで、現在のブランチが base ブランチから新規追加したコミット済みファイルに 'A' ではなく青い 'M' が出る。

原因（実測・コード参照）:
- GitStatusReader.parseNameStatus（BefoldApp/befold/App/GitStatusReader.swift:139-158）が `git diff --name-status -z` の状態文字を R/C 判定にしか使わず破棄し、パスだけを返している。
- 受け側 GitStatusReader.swift:73-76 はそれを isBranchModified: Bool（App/GitFileStatus.swift:33）という 1 ビットに落とす。
- そのため GitStatusBadge.appearance（Viewer/GitStatusBadge.swift:55-59）が branchModified を常に GitFileStatus.Change.modified（'M'）として描画する。ブランチ追加ファイルは構造上 'A' になれない。
- git 側は正しく 'A' を返すことを一時リポジトリで実測済み（merge-base main..HEAD の diff --name-status が 'A new.md' / 'M old.md'）。

単純化の検討結果: 新しい状態を足すのではなく、既存の GitFileStatus.Change（A/M/D/R/C/T/U を表現できる）をそのまま使い、isBranchModified: Bool を branchChange: GitFileStatus.Change? へ置き換えるのが最小。parseNameStatus の戻り値を (状態, パス) の組にすれば、捨てている情報を拾い直すだけで済み、分岐も状態も増えない。

既存テスト GitStatusReaderTests.swift:80-82 と GitStatusBadgeTests.swift:52-63 が現在の挙動（パスのみ返す / branchModified 単独は 'M'）を仕様として固定しているため、あわせて更新が必要。

FeatureGate.isSidebarGitStatusEnabled 配下のため、コミットには (gate) スコープを付けること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 現在のブランチで新規追加されコミット済みのファイルに、サイドバーで branchModified 色の 'A' が表示される
- [ ] #2 削除（D）・改名（R）など A/M 以外の branch 変更種別も、対応する文字で表示される
- [ ] #3 isBranchModified: Bool が廃止され、branch 側の変更種別が既存の GitFileStatus.Change で表現されている（新しい enum や Bool を増やさない）
- [ ] #4 ブランチ新規追加ファイルが 'A' になることを検証するテストがあり、修正を戻すと落ちることを確認済み
- [ ] #5 swiftlint の main 比ベースライン差分がゼロである
<!-- AC:END -->
