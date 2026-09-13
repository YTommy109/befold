---
id: TASK-620.1
title: Bookmark Editor の行アイコンをサイドバーと同じファイル種別アイコンにする
status: Done
assignee:
  - '@claude'
created_date: '2026-09-13 11:42'
updated_date: '2026-09-13 15:30'
labels: []
milestone: m-9
dependencies: []
parent_task_id: TASK-620
priority: medium
type: feature
ordinal: 811000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bookmark Editor のブックマーク行は全行同じ SF Symbol `bookmark` を出しており、アイコンが情報を持っていない。サイドバーの `FileListEntryRow` はファイル種別のアイコンを出しているので、見た目と意味を揃えたい。

注意すべき制約: 行のコメントにあるとおり、`bookmark` にしたのは `NSWorkspace.icon(forFile:)` がディスク I/O を伴うため。Bookmark Editor と Bookmarks メニューは「表示では stat しない」を約束している（応答しないマウント上のブックマークで待たされるため。`docs/dev/native-app-design.md` の `BookmarkManagerModel` / `BookmarksMenuController` の行）。サイドバーは列挙済みのローカルなエントリを描くので同じ API で問題にならないが、ブックマークは切断済みのボリューム上にもありうる。拡張子から `UTType` を引いてアイコンを得るなど、ファイルに触れない方法があるかを着手時に確かめる。ディレクトリのブックマーク（Finder からの D&D で追加できる）は拡張子だけでは種別が決まらない点も考慮する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ファイルのブックマーク行に、サイドバーで同じファイルに出るものと同じ種別のアイコンが出る
- [x] #2 ディレクトリのブックマーク行にフォルダーのアイコンが出る
- [x] #3 一覧の描画でブックマーク先へのファイルシステムアクセスが発生しない（約束を変える場合は、その判断と理由を native-app-design.md に記録する）
- [x] #4 native-app-design.md の Bookmark Editor の記述が実装に追随している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
前提（実測）: BookmarkEntry.url は URL(fileURLWithPath:) で、ディレクトリを渡すと hasDirectoryPath=true になる＝ファイルシステムを見ている。Bookmark Editor の行描画・displayName（ソートの比較ごと）・Bookmarks メニュー（addFileItems → NSWorkspace.icon(forFile:)）・Quick Open の bookmarkedURLs()（MainActor）がすべてこれを通るため、「表示では stat しない」は現状守られていない。ユーザー確認のうえ、約束を守る形に直す。

1. BookmarkEntry に isDirectory: Bool?（nil = 記録なしの既存データ）
2. BookmarkLibrary.add(_:to:isDirectory:) — isDirectory は必須引数
3. 種別は追加の瞬間だけ調べる: BookmarkStore.add(_:)（⌘D・CLI）は注入した FileReading で、ドロップは dropDecision の stat 結果を BookmarkDropOutcome.Added で運び store.add(_:toFolder:isDirectory:) へ渡す（MainActor で調べ直さない）
4. BookmarkEntry.url を URL(filePath:directoryHint:) に。displayName / detailPath はパス文字列から
5. BookmarkEntry.iconType: UTType（純粋）
6. Bookmark Editor の行とメニュー項目のアイコンを NSWorkspace.shared.icon(for: iconType) に。addFileItems の icons を必須引数にし、未使用になった addFileItem を削除
7. テストと native-app-design.md
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
/review-design: 項目1（URL の形 hasDirectoryPath で種別を判定する当初案）と項目9（isDirectory の渡し忘れ）が該当し、ディスク問い合わせ + 必須引数へ変更。詳細は Plan の旧版に記録。
responsibility-reviewer: 要対応 1 件——BookmarkStore.add(_:toFolder:) が resourceValues を直接呼び、ドロップ経路で dropDecision（MainActor の外）と同じ stat を MainActor 上で繰り返していた（「stat は MainActor の外」の約束を破る）。→ ドロップは判定結果を BookmarkDropOutcome.Added で運んで add(_:toFolder:isDirectory:) へ渡し、ストアが調べるのは引数 1 つの add(_:) だけ、それも注入の口 FileReading 経由に直した。任意 2 件: (a) iconType を BefoldKit に置く点 → displayName/detailPath と同じ純粋派生値の前例に沿うので据え置き、project.yml の「Foundation だけ」コメントに UniformTypeIdentifiers を許容する旨を追記 (b) NSWorkspace.icon(for:) 呼び出しが 2 箇所 → 3 箇所目で共通化、今は据え置き。
単純化: addFileItems の icons を必須にしたことで addFileItem(title:filePath:...) の呼び出し元が 0 になり削除（NSMenu+Items 216 → 204 行）。Recent はパスから引くことを呼び出し元で明示する形になった。
既存データ: isDirectory が nil のエントリは拡張子が無ければフォルダーと推定（ponytail コメントで天井を明記。拡張子なしのファイルはフォルダーに見えるが、付け直せば記録される）。Bookmarks キーの意味は変えず optional フィールドの追加だけなので移行は不要（旧版は無視して読める）。
対象外として触らなかったもの: Recent 系（PathListDefaults.urls も URL(fileURLWithPath:)）は「表示で stat しない」約束の対象外。
検証:
- swift test --skip Integration --skip FileWatcherTests: 1933 件パス
- 戻すと落ちる: url を URL(fileURLWithPath:) に戻す → BookmarkStoreTests「add は実在のディレクトリとファイルの種別を記録し…」が hasDirectoryPath=true で落ちる / 種別判定を url.hasDirectoryPath に戻す → 同テストが isDirectory=false で落ちる / ドロップで種別を渡さない → BookmarkManagerModelTests のドロップテストが isDirectory=false で落ちる
- swiftlint: origin/main との差分ゼロ（途中で orphaned_doc_comment が 1 件出たので ponytail コメントを本体内へ移した）
- 型グループ: 閾値以内
- 実機（.tmp/TASK-620/6201-*.png）: CLI で sample-folder / diagram.mmd / table.csv を追加 → Bookmark Editor とメニューでフォルダー・CSV・書類のアイコン。同じフォルダーをサイドバーで開いたときのアイコンと一致。既存（isDirectory 記録なし）の .md も書類アイコン
native-app-design.md: BookmarkStore / BookmarksMenuController / BookmarkManagerView の行を更新

撤回（2026-09-14, TASK-621）: AC #2「ディレクトリのブックマーク行にフォルダーのアイコンが出る」は、フォルダーをブックマークできる前提（TASK-536.3 のドロップと CLI が受け入れていた）の上に立っていたが、フォルダーはブックマークできない仕様だった（ユーザー指摘）。TASK-621 で入口を塞ぎ、BookmarkEntry.isDirectory の記録とフォルダーアイコンを撤去した。表示で stat しない修正（url / icon(forFile:) の撤去）はそのまま有効。

PR #663 の CI（type-group-size ジョブの check-befoldkit-platform-free.sh）で BefoldKit の import UniformTypeIdentifiers が弾かれた。検査の許可基準は swift-corelibs にも実装があるモジュールで、UTType は Apple 専用のため満たさない。上の任意指摘 (a) の「BefoldKit に据え置き」を撤回し、iconType を befold/App/BookmarkEntry+IconType.swift の extension へ移した（呼び出し元はすべて befold ターゲット）。project.yml に足した許容のコメントも戻した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ブックマーク行（Bookmark Editor）と Bookmarks メニューのアイコンを、記録済みの種別と拡張子から引く型アイコンにした（ディレクトリはフォルダー）。種別は追加の瞬間だけ調べて BookmarkEntry.isDirectory に記録し、BookmarkEntry.url を stat しない形に直したことで、表示・ソート・Quick Open の候補収集でブックマーク先に触れなくなった（従来は URL(fileURLWithPath:) と icon(forFile:) で約束が破れていた）。Swift 1933 件パス、戻すと落ちるテスト 3 系統、実機でサイドバーと同じアイコンを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
