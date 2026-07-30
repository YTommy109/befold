---
id: TASK-183
title: サイドバーヘッダーに基準ディレクトリ（git ルート/フォルダ）を表示する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 13:54'
updated_date: '2026-07-30 06:54'
labels: []
dependencies: []
documentation:
  - docs/superpowers/specs/2026-07-28-sidebar-base-directory-indicator-design.md
ordinal: 261000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
相対パスのコピーと Quick Open がどのフォルダを基準にしているかをサイドバー上部に常時表示し、ユーザーが挙動を予測できるようにする。基準は既存の resolveGitRoot（gitFileIndex.repositoryRoot）と同じ gitRoot ?? workspaceRoot 規則で決定し、git ルート時と非 git フォールバック時をアイコンで区別する。情報表示のみ（クリック操作はスコープ外）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバー（FileListView）ヘッダー最上部に、アイコン＋基準フォルダ名の 1 行インジケータが表示される
- [x] #2 git 管理下のファイルでは git ルートのフォルダ名と git を想起させるアイコンが表示される
- [x] #3 git 管理外のファイルでは workspaceRoot のフォルダ名と通常フォルダアイコンが表示される
- [x] #4 ツールチップに基準ディレクトリのフルパスと「Git リポジトリ／通常フォルダ」の区別が表示される
- [x] #5 ツールチップ文言は Localizable.xcstrings に追加され翻訳漏れがない
- [x] #6 基準ディレクトリの名前・種別・パスを算出する純粋ロジックが BefoldKit にあり、git あり/なし・ボリューム直下のエッジを含むユニットテストで検証されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldKit に BaseDirectoryDescriptor（kind: .gitRoot/.plainFolder, url, name）を新設し、gitRoot ?? workspaceRoot 規則で決定する純粋ロジックとして実装＋ユニットテスト
2. BefoldKit の GitFileIndexing に repositoryRoot(forDirectoryAt:) を extension で追加する（既存の forFileAt: は末尾要素を落として親で判定するため、ディレクトリを直接渡すと意味がずれる。この差を1か所に閉じ込める）
3. FileListModel に baseDirectory: BaseDirectoryDescriptor? を追加する
4. SidebarNavigator に resolveGitRoot クロージャを注入し、refreshFileList / navigateToFolder / init の契機で世代番号ガード付きの非同期タスクとして baseDirectory を更新する（git rev-parse を View の body から呼ばずメインスレッドを塞がないため。既存の directoryLister 注入と同じ形）
5. ViewerWindowController から gitFileIndex 由来のクロージャを注入する
6. FileListView の header を VStack にし、最上部にアイコン＋基準フォルダ名の1行インジケータを追加。ツールチップにフルパスと種別を出す
7. Localizable.xcstrings（アプリ側）に en/ja のツールチップ文言を追加
8. swift build / swift test / LocalizationTests で検証
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。

- BefoldKit/BaseDirectoryDescriptor.swift: gitRoot ?? workspaceRoot 規則で kind(.gitRoot/.plainFolder)・url・name を決める純粋な値型。ボリューム直下(/)で name が空にならないようパス表記へフォールバックする。
- BefoldKit/TrackedPathResolver.swift: GitFileIndexing に repositoryRoot(forDirectoryAt:) を追加。既存の forFileAt: は末尾要素を落として親で判定する契約のため、ディレクトリを直接渡すとリポジトリルートで nil になる。この 1 階層のずれをこの extension に閉じ込めた。
- FileListModel.baseDirectory を追加し、SidebarNavigator が init / refreshFileList / navigateToFolder の契機で世代番号ガード付きの非同期タスクとして更新する。ViewerWindowController から gitFileIndex 由来の解決器を Task.detached 経由で注入。設計ドキュメントは View の再描画経路に乗せる想定だったが、キャッシュ未命中時に git rev-parse の subprocess を同期で待つため、SwiftUI の body から呼ばない形に変更した。
- 表示は befold/Viewer/BaseDirectoryIndicator.swift に独立した View として切り出した(FileListView に直接書くと SwiftLint の type_body_length 250 行を超えたため)。
- ツールチップは書式引数を使わず Swift 側で 3 行を連結する(翻訳側に順序制約を持ち込まないため)。

検証: swift build / swift test(799 tests, 108 suites 全パス。うち新規 12) / SwiftLint(触ったファイルに新規警告なし) / swiftformat --lint クリーン。AC #5 は LocalizationTests の訳漏れ検出テストで担保。AC #1〜#4 は GUI 層のため手動確認が必要。

GUI 検証(スクリーンショット): git 管理下(README.md, repo olla-rattler)でブランチアイコン+riポジトリ名、git管理外(/tmp配下)でフォルダアイコン+ディレクトリ名を確認。ツールチップのホバーも CGEvent でマウス移動して再現し、「相対パスと Quick Open の基準／Git リポジトリ／フルパス」の3行表示を確認した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバー(FileListView)ヘッダー最上部に基準ディレクトリ(相対パスコピー・Quick Openの基準)を示す1行インジケータを追加した。BefoldKit.BaseDirectoryDescriptorがgitRoot ?? workspaceRoot規則で種別・名前・パスを算出する純粋ロジックとしてユニットテスト付きで実装され、SidebarNavigatorが一覧更新と同じ契機でメイン外(非同期)にgit rootを解決してFileListModel.baseDirectoryへ反映する。表示はBaseDirectoryIndicator(独立View)、ツールチップ文言はLocalizable.xcstringsにen/ja追加。検証: swift build成功/swift test 799件全パス(新規12件)/SwiftLint・swiftformat --lint クリーン/GUI手動確認(git管理下でブランチアイコン+repo名、git管理外でフォルダアイコン+dir名、ツールチップの3行表示をスクリーンショットで確認)。
<!-- SECTION:FINAL_SUMMARY:END -->
