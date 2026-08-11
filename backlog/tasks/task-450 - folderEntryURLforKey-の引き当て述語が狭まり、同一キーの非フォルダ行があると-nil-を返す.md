---
id: TASK-450
title: 'folderEntryURL(forKey:) の引き当て述語が狭まり、同一キーの非フォルダ行があると nil を返す'
status: Done
assignee:
  - '@claude'
created_date: '2026-08-11 13:38'
updated_date: '2026-08-11 21:44'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 100620
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #483（TASK-442.2 で引き当て述語を FileListModel へ移した変更）で、述語の意味が変わっている。

- 移動前（SidebarNavigator.folderEntryURL）: `entries.first { $0.kind == .folder && $0.pathKey == key }?.url` — 非フォルダ行は読み飛ばして走査を続ける
- 移動後（BefoldApp/befold/Viewer/FileListModel+Lookup.swift:12-15）: `guard let entry = entry(forPathKey: key), entry.kind == .folder else { return nil }` — FileListEntryIndex.byPathKey は kind を問わず「最初の 1 行が勝つ」ため、先に非フォルダ行が居るとその行で確定してから kind で弾かれる

同じ normalizedPathKey を持つ非フォルダ行が本来のフォルダ行より前に並ぶ一覧（シンボリックリンク行が後続の子と同じディレクトリを指す、リンク経由で同じディレクトリが子としても辿れるときの .parentNavigation 行など）で、以前は返っていたフォルダ URL が nil になる。

影響は 2 箇所の呼び出し元で「選択なし」になる形で出る。
- SidebarNavigator+FolderNavigation.swift:37 — 上の階層へ移動したとき、戻り元フォルダが選択強調されない
- SidebarHistoryController.swift:84 — 履歴の戻る/進むで「上へ移動した」エントリの親フォルダ選択が復元されない

/code-review high の verifier は PLAUSIBLE（述語の変化はコード参照で確定。実際に同一キーの重複行が発生する一覧の再現条件は未実測）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 まず「同一 normalizedPathKey の行が重複しうるのか」を実測で確定させ、結果を Implementation Notes に記録する（重複しないなら述語を戻さず、その根拠を doc コメントに残す）
- [x] #2 重複しうる場合、フォルダ行を取り違えず引き当てられる（移動前と同じ意味の）実装になっている
- [x] #3 同一キーの非フォルダ行が先行する一覧でフォルダ URL が引けることをユニットテストで担保している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. AC#1: 重複は起きうると確定（コード参照で裏付け済み。Notes へ記録）
2. folderEntryURL(forKey:) を索引経由から entries の線形走査へ戻す（kind == .folder かつ pathKey 一致の最初の行）。索引 byPathKey は先勝ちで kind を見ないため、この述語は索引では表現できない
3. FileListModel の型グループは 484 行でベースライン掲載のため増加ゼロに収める（guard 2 行を 1 行の式へ畳んだぶんで doc 追記を吸収する）
4. FileListEntryIndex の doc に「索引は kind を見ない」を明記して同型の再発を防ぐ
5. 同キーの非フォルダ行が先行する entries でフォルダ URL が引けるテストを追加（索引経由へ戻すと落ちる形）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#1 の結論: **重複しうる**。防いでいるコードは存在しない（コード参照で裏付け）。
- pathKey は resolvingSymlinksInPath() で解決した実体パス（BefoldKit/URL+NormalizedPathKey.swift:7-9）。実体と並ぶシンボリックリンク行、祖先を指すリンクがあるときの .parentNavigation 行が同一キーになる
- 行の組み立て SidebarRowBuilder.Flattening.append（SidebarRowBuilder.swift:106-113）は rows.append に重複チェックを持たず、visited は再帰の停止だけを担う
- FileListEntryIndex.init（FileListEntryIndex.swift:18-27）は重複を先勝ちで黙って飲み込む。doc:10-13 が「同じ実体を指す行が複数あるとき」を明示的に想定
- SidebarRowBuilderTests.swift:134 が [dirA, dirB, dirA] を期待値として重複行をテストで固定している
未確認: .parentNavigation と子行のキー衝突が利用者環境で現実に起きる頻度（コードが弾かないことは断定できるが頻度は不明）。

実装: folderEntryURL(forKey:) を索引経由から entries の線形走査（kind == .folder かつ pathKey 一致の最初の行）へ戻し、分割前と同じ意味にした。索引を使えない理由を doc に明記し、FileListEntryIndex 側の doc にも「先勝ちは kind を見ない／その形の述語は線形走査で書く」を追記して同型の再発を防ぐ。

述語の棚卸し（AC#3 の周辺確認）: pathKey で行を引く箇所は 3 通りで、意図が異なるため統合しない。folderEntryURL（本件）／matchingEntryURL（kind 不問なので先勝ちのままでよい）／SidebarNavigator.rememberedSelectionURL（visibleEntries の線形走査・.parentNavigation 除外）。

検証: swift test 全件 1428 tests / 211 suites 通過。新規テスト findsFolderBehindSameKeyNonFolderRow は索引経由へ戻すと落ちることを実測で確認（Expectation failed: nil == .../sub）。swiftlint は main と完全一致、型グループ行数は FileListModel 484 行のまま（増加ゼロ）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
folderEntryURL(forKey:) を索引経由（先勝ち・kind を見ない）から entries の線形走査へ戻し、同一キーの非フォルダー行が先行してもフォルダー行を引き当てるようにした。AC#1 の「重複しうるか」はコード参照で確定（重複を防ぐコードは存在せず、既存テストが重複行を期待値として固定している）。索引では表せない述語であることを両側の doc に明記。索引経由へ戻すと落ちるテストで担保。swift test 1428 件通過、swiftlint は main と完全一致。
<!-- SECTION:FINAL_SUMMARY:END -->
