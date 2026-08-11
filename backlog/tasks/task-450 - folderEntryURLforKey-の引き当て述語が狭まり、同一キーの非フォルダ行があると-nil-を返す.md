---
id: TASK-450
title: 'folderEntryURL(forKey:) の引き当て述語が狭まり、同一キーの非フォルダ行があると nil を返す'
status: To Do
assignee: []
created_date: '2026-08-11 13:38'
updated_date: '2026-08-11 13:39'
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
- [ ] #1 まず「同一 normalizedPathKey の行が重複しうるのか」を実測で確定させ、結果を Implementation Notes に記録する（重複しないなら述語を戻さず、その根拠を doc コメントに残す）
- [ ] #2 重複しうる場合、フォルダ行を取り違えず引き当てられる（移動前と同じ意味の）実装になっている
- [ ] #3 同一キーの非フォルダ行が先行する一覧でフォルダ URL が引けることをユニットテストで担保している
<!-- AC:END -->
