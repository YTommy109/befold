---
id: TASK-620.5
title: Bookmark Editor の「名前を変更」を「別名」の操作として表示し、別名を付けてもファイル名が分かるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-09-13 11:43'
updated_date: '2026-09-13 15:11'
labels: []
milestone: m-9
dependencies: []
parent_task_id: TASK-620
priority: medium
type: feature
ordinal: 815000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bookmark Editor のブックマーク行の右クリックメニューは `bookmarks.manager.renameAlias` で、表示は「名前を変更…」/「Rename…」、入力 alert のタイトルは「ブックマークの名前」/「Bookmark Name」になっている。実際に変わるのはブックマークの表示名（`BookmarkEntry.alias`）だけでファイルは改名されないのに、ファイル自体の改名と誤解される。TASK-536 の設計文書では「別名を変更…」とする想定だった（`docs/superpowers/specs/2026-09-12-bookmark-management-design.md`）。

加えて、別名を付けると行の 1 行目が `displayName`（別名 ?? ファイル名）に置き換わり、2 行目は親ディレクトリのパスなので、**ファイル名がどこにも出なくなる**。何のファイルのブックマークか分からない。

Bookmarks メニュー（`BookmarksMenuController`）も表示名 = 別名、右列 = 親ディレクトリで同じ構造を持つ。本タスクの対象は Bookmark Editor。メニューも揃えるかは着手時にユーザーへ確認する。

l10n キーは意味が変わるので、キー名（`renameAlias`）の改名も検討する。`Localizable.xcstrings` はソートし直さない（CLAUDE.md）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 操作の表示が別名の設定であると分かる文言になっている（ja / en の両方。メニュー項目・alert タイトル・プレースホルダー）
- [x] #2 別名を付けたブックマーク行に、別名とあわせて元のファイル名が表示される
- [x] #3 別名の無いブックマーク行の表示が冗長にならない（ファイル名が 2 回出ない）
- [x] #4 l10n の翻訳漏れが無い（/l10n-check）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. l10n キー renameAlias 系を setAlias 系へ改名し、文言を「別名を設定…」「ブックマークの別名」「別名（空欄ならファイル名）」へ（en も同様）。folder 改名と共用の apply は bookmarks.manager.save へ
2. BookmarkEntry.detailPath を足し、行の 2 行目に使う（別名なし = 親ディレクトリ、別名あり = ファイル名まで含むパス）
3. テストと native-app-design.md を更新
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: 行の 2 行目だけを切り替えた。別名があるときはフルパス（truncationMode(.head) で末尾のファイル名が必ず残る）、無いときは従来どおり親ディレクトリ。3 行目を足す・1 行目に括弧でファイル名を並べる案より行の高さも構成も変わらず小さい。detailPath はパス文字列の操作だけで作る（URL を経由すると URL(fileURLWithPath:) が stat するため。TASK-620.1 で扱う）。
メニュー（BookmarksMenuController）はユーザー確認のうえ対象外（Bookmark Editor だけ）。
l10n キー: renameAlias → setAlias、renameAlias.title/.placeholder → setAlias.title/.placeholder、renameAlias.apply（フォルダー改名と共用で名前が実態とずれていた）→ save。xcstrings はキー名の置換だけで並べ替えていない。
文言: 当初 en placeholder を「Alias (leave empty to show the file name)」にしたところ、実機の alert の入力欄で途中で切れた（ja も余裕なし）ため、「Alias (empty for file name)」/「別名（空欄ならファイル名）」へ短縮し、実機で収まることを確認。
検証:
- swift test --skip Integration --skip FileWatcherTests: 1931 件パス
- detailPath を常に親ディレクトリに戻すと BookmarkLibraryTests「添えるパスは別名があればファイル名まで、無ければ親ディレクトリ」が落ちる
- l10n: en/ja の欠落・空・未翻訳 state・プレースホルダ不一致なし（xcstrings を JSON で全件走査）。rg で renameAlias の残存なし
- swiftlint: origin/main との差分ゼロ
- 実機（en / ja を -AppleLanguages で切替、スクショは .tmp/TASK-620/6205-*.png）: 別名 Degino の行の 2 行目が …/Dropbox/Degino/CLAUDE.md、別名なしの行は親ディレクトリのみ。右クリックが Set Alias… / 別名を設定…、alert タイトル Bookmark Alias / ブックマークの別名、プレースホルダーが欄に収まる
native-app-design.md: BookmarkManagerView の行に行表示と文言を追記した
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
別名の操作を「別名を設定…」/「Set Alias…」と表示し（alert タイトル・プレースホルダーも別名として明示、l10n キーも setAlias へ改名）、別名のあるブックマーク行では 2 行目をファイル名まで含むパスにした（別名なしは親ディレクトリのまま）。Swift 1931 件パス、l10n 漏れなし、実機の en/ja で表示を確認。メニューはユーザー判断で対象外。
<!-- SECTION:FINAL_SUMMARY:END -->
