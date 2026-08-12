---
id: TASK-451
title: reloadExpandedChildren が一覧に無くなったフォルダも再列挙する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-11 13:39'
updated_date: '2026-08-11 21:45'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 100630
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
- [x] #1 現在の一覧に存在しない展開キーに対して列挙要求が飛ばない（または、飛んでも既存の子行を破棄しない）
- [x] #2 削除済みフォルダを展開状態のまま残して再列挙を走らせたとき、既存の子行が保持されることをユニットテストで担保している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. reloadExpandedChildren で、現在の entries にフォルダ行が無い展開キーをスキップする（分割前と同じ意味）。列挙先 URL は従来どおり ExpansionToken.url が運ぶ
2. 判定は TASK-450 で直した folderEntryURL を使う（述語を 1 箇所に保つ）
3. スキップしても invalidateChildren の epoch は進むため、走行中の古い結果は従来どおり捨てられる。スキップしたキーの子は古いまま残るが、行が無いので描画されない — この含意を doc に書く
4. 一覧に無いキーで childrenLister が呼ばれないことを呼び出し回数で数えるテストと、既存の子が保持されるテストを追加
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
優先度を low → medium へ引き上げ、ordinal を TASK-450 の直後（100630）へ移した（2026-08-11 の優先順位評価）。理由: TASK-448〜452 はいずれもマージ済み PR #483 由来の回帰・後始末であり、症状の軽さだけで沈めると分割済み実装のコンテキストを再学習し直すことになる。本件は TASK-450 と同じサイドバー抽出（TASK-442 系）由来なので 1 PR で返す想定。

実装: reloadExpandedChildren で、いまの一覧にフォルダー行が無い展開キーを飛ばす（分割前と同じ意味）。列挙先 URL は従来どおり ExpansionToken.url が運ぶため、TASK-442.3 の「一覧から引き当て直さない」設計は保つ。判定には TASK-450 で直した folderEntryURL を使い、述語を 1 箇所に保った。

判定に使う entries は「1 つ前の完了した一覧」（この関数はルートの列挙を発行する前に呼ばれる / SidebarListingCoordinator.swift:126）。そのためフォルダーが消えた直後の 1 回だけは従来どおり列挙が走り、その一覧が届いた後の取り直しから飛ばされる。この振る舞いはテストにも書いてある（count == 2 で頭打ち）。

スキップしても invalidateChildren() の epoch は進むため、走行中の古い結果は従来どおり捨てられる。飛ばしたキーの子は .loaded のまま残るが、親の行が無いので描画されない。

検証: swift test 全件 1428 tests / 211 suites 通過。新規テスト reloadSkipsFoldersMissingFromListing は、(a) 一覧から消した後に 3 回取り直しても childrenLister 呼び出しが 2 回で頭打ち、(b) フォルダーが復活したら保持していた子行がそのまま出て再列挙も起きない、を検証する。ガードを外すと 2 箇所の #expect が落ちることを実測で確認。swiftlint は main と完全一致、型グループ行数の増加もゼロ（SidebarTreePresenter は閾値未満）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
reloadExpandedChildren が、いまの一覧にフォルダー行が無い展開キーを取り直さないようにした（分割前と同じ意味）。列挙先 URL は券が運ぶ設計を保ち、判定は TASK-450 で直した folderEntryURL に一本化。消えたフォルダーへの列挙が繰り返されず、読み込み済みの子リストも捨てられないことをユニットテストで担保。swift test 1428 件通過、swiftlint は main と完全一致。
<!-- SECTION:FINAL_SUMMARY:END -->
