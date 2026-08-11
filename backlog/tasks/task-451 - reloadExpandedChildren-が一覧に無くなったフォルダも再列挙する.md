---
id: TASK-451
title: reloadExpandedChildren が一覧に無くなったフォルダも再列挙する
status: To Do
assignee: []
created_date: '2026-08-11 13:39'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 116400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #483（TASK-442.3 のツリー展開切り出し）で、展開済みフォルダの再読み込みから存在確認の前提が落ちている。

- 移動前（SidebarNavigator+Expansion.reloadExpandedChildren）: `for token in expansion.invalidateChildren() { guard let url = folderEntryURL(forKey: token.key) else { continue }; loadChildren(for: token, at: url) }` — 現在の一覧に行が無い展開キーは列挙しない
- 移動後（BefoldApp/befold/App/SidebarTreePresenter.swift:119-123）: token が展開開始時（beginExpanding(_:at:)）の url を持ち回るようになり、`loadChildren(for:)` が無条件に走る

reloadExpandedChildren() は performListing の先頭で毎回呼ばれる（並び順の変更・隠しファイルの切り替え・リネーム・windowDidBecomeKey のたび）。ツリー表示で複数フォルダを展開したあと Finder 側でそれらを削除・リネームすると、以後ウィンドウがキーになるたびに存在しないパスへ childEntriesAsync が飛ぶ。低速なボリューム（ネットワーク/SMB）ではファイルシステムのタイムアウトまでブロックし、結果は .failed になるため、読み込み済みだった子行が毎回破棄される。

/code-review high の verifier は PLAUSIBLE（コードの変化はコード参照で確定。低速ボリュームでの体感影響は未実測）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 現在の一覧に存在しない展開キーに対して列挙要求が飛ばない（または、飛んでも既存の子行を破棄しない）
- [ ] #2 削除済みフォルダを展開状態のまま残して再列挙を走らせたとき、既存の子行が保持されることをユニットテストで担保している
<!-- AC:END -->
