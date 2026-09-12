---
id: TASK-536.4
title: Bookmark をフォルダー風の階層で整理できるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-21 07:28'
updated_date: '2026-09-12 14:26'
labels: []
milestone: m-9
dependencies:
  - TASK-536.1
parent_task_id: TASK-536
priority: medium
type: feature
ordinal: 780000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在の BookmarkStore はフラットな [String]（UserDefaults キー "BookmarkedPaths"）のみを保持し、グループ化やフォルダの概念が無い（実測: BookmarkStore.swift:8-59、PathListDefaults.swift）。近い概念としてサイドバーのファイルツリー（DirectoryListing.swift:9-59／SidebarRowBuilder／SidebarTreePresenter.swift）が階層表示・展開状態分離のパターンを持つが、これはファイルシステムのディレクトリ構造をそのまま反映するものであり、ブックマーク側は「ファイルシステムとは独立したユーザー定義の仮想フォルダ」を新設する必要がある（既存パターンをそのまま流用できない）。

ブックマークをユーザーが任意に作成した「フォルダー」にグルーピングし、階層的に整理できるようにする。

永続化フォーマットをフラットな配列から階層構造へ変更するため、CLAUDE.md の「UserDefaults キーの廃止・改名」節に準じ、既存のフラットな "BookmarkedPaths" からの移行（旧データの意味を保った変換・移行後の旧キー削除・(a)旧データあり (b)旧データなし (c)移行済みの3ケースのユニットテスト）を設計に含めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ユーザーは任意の名前のフォルダーを作成できる（同じ親の下で名前は一意）
- [x] #2 ブックマークを任意のフォルダーに所属させられる（フォルダーの入れ子も可能）
- [x] #3 フォルダーの一覧・展開状態・所属関係は永続化される
- [x] #4 フォルダーを削除しても配下のブックマークは失われない（親フォルダー、トップレベルならルートへ繰り上げる）
- [x] #5 フォルダーの改名で配下のサブフォルダーとブックマークの所属が全件追随する
- [x] #6 Bookmarks メニューでフォルダーはサブメニューとして表示される
- [x] #7 フォルダー操作の不変条件（同名禁止・削除で件数が減らない・改名の全件追随）をユニットテストで担保する（フラット配列からの移行は 536.1 で完了済み）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BookmarkLibrary に純粋操作を足す: createFolder(named:in:) / renameFolder(at:to:) / deleteFolder(at:) / move(_:to:) / setExpanded(_:for:) / children(of:)（フォルダー名順・エントリ表示名順）。同じ親の下でフォルダー名は一意（作成・改名・削除の繰り上げで衝突したら false）。削除は配下のサブフォルダーとエントリを親へ繰り上げる。フォルダー記録の無い所属（孤児）は読み出し時にルート扱いにする
2. BookmarkStore に同名の薄いラッパー（mutate を値を返す形に一般化）
3. BookmarksMenuController: フォルダーをサブメニューとして再帰的に構築（フォルダー → エントリの順）
4. BookmarkManagerModel: entries を library のスナップショットに置き換え（entries は互換の computed）。フォルダー操作は集合を変えないので onChange を呼ばない
5. BookmarkManagerView: DisclosureGroup(isExpanded:) の再帰ツリー、行 id は enum BookmarkRow { folder([String]) / bookmark(String) }。右クリック: ブックマーク行 = Rename… / Move to Folder（サブメニュー）/ Remove Bookmark、フォルダー行 = Rename Folder… / New Folder… / Delete Folder。下部に「New Folder…」ボタン。文字入力は 1 つの .alert を enum BookmarkManagerPrompt（alias / newFolder / renameFolder）で使い回す。名前の重複は別の alert で伝える
6. テスト: BookmarkLibraryTests（作成の重複拒否・入れ子・改名の接頭辞全件追随・削除の繰り上げで件数不変・繰り上げ衝突の拒否・孤児のルート扱い・展開状態の往復）/ BookmarksMenuControllerTests（サブメニュー）/ BookmarkManagerModelTests（フォルダー操作で onChange なし）
7. 検証: swift test、swiftformat、swiftlint ベースライン、xcodebuild、l10n-check、実機でフォルダー作成 → 移動 → メニューのサブメニュー表示

## /review-design（チェックリスト）
- 1 真実の源: フォルダーの存在は folders の記録で決め、エントリの所属パスから推定しない。記録の無い所属（手編集・旧版）は children(of: []) に含めて見えなくならないようにする
- 2 不変条件: 1 パス 1 件 / 同じ親でフォルダー名一意 / エントリの所属は存在するフォルダーかルート。操作側で守り、読み出し側は孤児を許容
- 3 消費経路: bookmarkedURLs は平坦のまま（Pruner / Quick Open / ツールバー不変）。階層を読むのはメニューとパネルの 2 つで、どちらも children(of:) を通す。改名の接頭辞書き換えはフォルダーとエントリを同じ 1 操作で行う
- 4 表示: 空フォルダーは中身の無い DisclosureGroup。重複名は alert で伝える
- 5/6/8: ライフサイクル・非同期の変更なし。メニュー構築は表示直前の再帰 1 回
- 7 測るもの: 値型のテストがフォルダー・エントリの配列を直接見る
- 9 粒度: 変更なし（同じ AppStores.bookmarkStore）
- 10 行数: BookmarkLibrary 121 → 約 230、BookmarkManagerView 100 → 約 230（プロンプトの enum は別ファイル）、Model 53 → 約 90、MenuController 58 → 約 80。いずれも閾値 400 の内側。モデルの注入クロージャは 2 のまま
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-09-12）

BookmarkLibrary にフォルダー操作（createFolder / renameFolder / deleteFolder / move / setExpanded / children(of:) / resolvedFolder(of:)）を純粋操作として足し、BookmarkStore は同名の薄いラッパー（mutate を値を返す形に一般化）。不変条件は「同じ親の下でフォルダー名一意」「削除は配下（サブフォルダー・エントリ）を親へ繰り上げ、繰り上げ先で名前が衝突するなら何もしない」「エントリの所属が記録の無いフォルダーを指していればルート扱いで読む（手編集・旧版で見えなくならない）」。改名は名前列の接頭辞をフォルダー・エントリとも 1 操作で書き換える。

メニュー: BookmarksMenuController がフォルダーをサブメニューとして再帰的に組む（各階層でフォルダーが先・エントリが後）。パネル: DisclosureGroup(isExpanded:) の再帰ツリー（再帰は AnyView で切る）、行 id は enum BookmarkRow、下部に「New Folder…」、フォルダー行の右クリック = Rename Folder… / New Folder… / Delete Folder、ブックマーク行 = Rename… / Move to Folder（サブメニュー、いま居る場所は無効）/ Remove Bookmark。文字入力は 1 つの .alert を enum BookmarkManagerPrompt（alias / newFolder / renameFolder）で使い回し、名前の重複だけ別 alert で伝える。フォルダー削除は配下が失われないので確認を挟まない（AC #4 の「ルートへ戻す」側を採り、入れ子では親へ）。フォルダー操作は集合を変えないので onChange（全窓ツールバー再同期）は呼ばない。

単純化の検討: BookmarkManagerPrompt を Identifiable にすると swiftlint identifier_name（id）が新規に鳴ったため、presenting: が識別子を要求しないことを確認して Equatable のみにした。

検証（実測）:
- swift test --skip Integration --skip FileWatcherTests: 1921 tests / 311 suites 通過（新規: BookmarkLibraryTests +7、BookmarksMenuControllerTests +2、BookmarkManagerModelTests +1）
- swiftlint ベースライン差分: main 48 / HEAD 48、新規 0・解消 0。swiftformat 全ターゲット 0 files。型グループ閾値以内（BookmarkLibrary 254 / BookmarkManagerView 225 / Model 96 / MenuController 75 / Prompt 61 / Row 6）
- xcodebuild build -scheme befold: 成功。l10n-check: 追加 10 キーとも en/ja 揃い
- 実機（Debug、実 defaults）: パネル下部「New Folder…」→ alert に「Work」→ Create で defaults に folders [Work]（isExpanded true）が書かれ、パネルはフォルダー行（開閉三角 + folder アイコン）とその下のブックマーク行のツリーになった。Bookmarks メニューにサブメニュー「Work」が一覧の先頭（エントリより前）に出た。**「Move to Folder」の実機操作は未確認**——階層化した List の行が System Events の entire contents に載らず、右クリックメニューを自動操作で開けなかった（移動の規則はユニットテスト BookmarkLibraryTests.moveRequiresExistingFolder と BookmarkManagerModelTests.folderOperationsRefreshWithoutNotifying で担保。UI は SwiftUI 標準の Menu）。検証後にフォルダーを消して元の状態へ戻した
- docs/dev/native-app-design.md: BookmarkStore / BookmarksMenuController / BookmarkManagerModel の行にフォルダーの規則・サブメニュー・ツリーを追記

responsibility-reviewer: must-fix 0、Medium 1（View がフォルダー名の正規化規則を写していた）・Low 4（一意性の述語が 3 通り / Prompt のキー解決テストなし / サブメニュー構築の重複 / 行→エントリの引き当てが 2 箇所）。すべて同一タスク内で反映: BookmarkLibrary.folderName(_:) に正規化を一本化、folderExists に述語を統一、NSMenu.addSubmenu(title:) を追加、BookmarkLibrary.entry(atPath:) を追加、BookmarkManagerPromptTests（3 本）を追加。反映後: swift test 1924 件通過、swiftlint 新規 0、xcodebuild 成功。レビューが見つけた「l10n キー解決テストの != String(describing:) が空振り」は前例（SidebarEmptyStateTests）と同型のため TASK-618 として起票した（3 箇所を一度に直す）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ブックマークをユーザー定義のフォルダーで階層化できるようにした。値型 BookmarkLibrary にフォルダーの作成・改名・削除・所属変更・展開状態の純粋操作を置き（同じ親で名前一意、削除は配下を親へ繰り上げ、記録の無い所属はルート扱いで読む）、BookmarkStore は薄いラッパー。Bookmarks メニューはフォルダーをサブメニューとして再帰的に組み、管理パネルは DisclosureGroup の再帰ツリーに右クリック操作（フォルダー行: 改名 / 新規 / 削除、ブックマーク行: 別名 / フォルダーへ移動 / 削除）と「New Folder…」を持つ。文字入力は 1 つの alert を BookmarkManagerPrompt で使い回す。検証: swift test 1924 件通過（フォルダー操作の不変条件 7 本ほか）、swiftlint 差分 0、xcodebuild 成功、実機でフォルダー作成 → ツリー表示とメニューのサブメニューを確認（移動の実機操作は自動化できず、ユニットテストで担保）。
<!-- SECTION:FINAL_SUMMARY:END -->
