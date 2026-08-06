---
id: TASK-344
title: ブランチで新規追加したファイルにサイドバーで A ではなく M が出る問題を修正する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-06 07:52'
updated_date: '2026-08-06 08:17'
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
- [x] #1 現在のブランチで新規追加されコミット済みのファイルに、サイドバーで branchModified 色の 'A' が表示される
- [x] #2 削除（D）・改名（R）など A/M 以外の branch 変更種別も、対応する文字で表示される
- [x] #3 isBranchModified: Bool が廃止され、branch 側の変更種別が既存の GitFileStatus.Change で表現されている（新しい enum や Bool を増やさない）
- [x] #4 ブランチ新規追加ファイルが 'A' になることを検証するテストがあり、修正を戻すと落ちることを確認済み
- [x] #5 swiftlint の main 比ベースライン差分がゼロである
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitFileStatus.isBranchModified: Bool を branchChange: Change? へ置き換える（isClean も branchChange == nil で判定）。
2. GitStatusReader.parseNameStatus の戻り値を [(change: GitFileStatus.Change, path: String)] にする。状態フィールドの先頭 1 文字を Change(porcelainCode:) で解釈し、R/C は従来どおりパスを 2 つ読み進めて変更後のパスを採る。未知コード（git の 'X' 等）は porcelain 経路と同じく捨てる。
3. GitStatusReader.status:73-76 で statuses[key, default: GitFileStatus()].branchChange = change を設定する。
4. GitFolderStatus.merge の hasBranchModified を status.branchChange != nil で立てる（フォルダー集約は種別ではなく有無を持つ設計なので Bool のまま）。
5. GitStatusBadge.appearance:55-59 を branchChange.rawValue を出す形に変える（tint は .branchModified のまま）。
6. テスト更新: GitStatusReaderTests の parseNameStatus 期待値、GitStatusBadgeTests:52-63 / :73 の branchModified ケース、GitFolderStatusTests:64、GitStatusReaderIntegrationTests:164/183/204。
7. GitStatusReaderIntegrationTests にブランチで新規追加したファイルが branchChange == .added になるケースを追加し、修正を戻すと落ちることを確認する。

--- /review-design の結果（実装前）---
8. [項目1 判定の真実の源] parseNameStatus で GitFileStatus.Change に解釈できないコード（git の 'X'=unknown、'B'=pairing broken）に当たったとき、エントリごと捨ててはならない。捨てるとバッジが消え、「変更あり」が「変更なし」と同じ表示に縮退する。**種別だけを諦めて .modified を入れる**（変更があった事実は確かなため）。これは GitStatusReader.swift:70-72 が branch diff 全体に対して既に採っている「この機能だけを諦める」方針と同じ。doc コメントにフォールバックである旨を書く。
9. [項目4 表示] l10n の追加は不要。'sidebar.gitStatus.branchModified' は英 'Changed in this branch' / 日「このブランチでの変更」で種別に中立なため、A/D/R でもそのまま正しい（Resources/Localizable.xcstrings:2383-2397 で確認）。
10. [項目9 担保] Bool を廃止して Change? にすること自体が担保になる（'M' を暗黙に意味する表現が型から消えるため、同じ退化を再度書けない）。追加の仕組みは不要。
11. [項目3 兄弟箇所] 変更種別の文字を出す箇所は GitStatusBadge.appearance(for:) の 1 箇所のみ（rg で確認）。フォルダー行は '•' 固定で種別を出さないため GitFolderStatus は Bool 集約のままでよい。FolderListingView はバッジを描かない（FileListEntryRow を gitStatus 無しで使う）ので消費経路はサイドバーだけ。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-06 実装完了。

変更点:
- GitFileStatus.isBranchModified: Bool を branchChange: Change? へ置換（GitFileStatus.swift:32-38）
- parseNameStatus の戻り値を [String: GitFileStatus.Change] にし、状態文字を拾い直す（GitStatusReader.swift:142-163）。branchModifiedPaths は branchChanges へ改名
- 解釈できないコードは設計レビューの結論どおり .modified へフォールバックし、エントリを捨てない
- GitStatusBadge.appearance が branchChange.rawValue をそのまま出す（GitStatusBadge.swift:55-59）
- GitFolderStatus は種別ではなく有無の集約なので Bool のまま（merge を branchChange != nil に変更）

検証（実測）:
- swift test: 1173 tests / 174 suites すべて成功
- 修正を戻す確認: parseNameStatus のフォールバックを常時 .modified に差し替えて実行し、'name-status: 変更後のパスを変更種別つきで返す' と 'ブランチで新規追加したコミット済みファイルは added になる' の 2 件が失敗することを確認（changed=.modified/added=.modified になり A が出ない）。確認後に戻した
- swiftlint: 変更した 8 ファイルについて origin/main を git archive で展開した木と比較し差分ゼロ（両者とも警告 0 件）
- swiftformat: 0/166 files formatted（整形の必要なし）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
git diff --name-status の状態文字を捨てていたため、ブランチで新規追加したファイルがサイドバーで A ではなく M として表示されていた問題を修正した。GitFileStatus の isBranchModified: Bool を既存の Change enum を使う branchChange: Change? へ置き換え、parseNameStatus がパスと一緒に種別を返すようにして、表示側が文字を決め打ちできない構造にした。A だけでなく D/R/C/T も正しい文字で出る。swift test 1173 件成功、修正を戻すと新規テスト 2 件が落ちることを実測で確認、swiftlint は main 比で差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
