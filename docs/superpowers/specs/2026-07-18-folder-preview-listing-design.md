# Folder Preview Listing Design

## Summary

サイドバーでフォルダーを選択した際、プレビューエリアが直前に開いていたファイルの内容を表示し続けてしまう問題を解消する。フォルダーが選択された場合、プレビューエリアにそのフォルダー直下の一覧を表示し、フォルダーの中に何があるかを見てから次の操作（開く／さらに降りる）を判断できるようにする。

## Requirements

- サイドバーでフォルダーをシングルクリックで選択したとき、プレビューエリアにそのフォルダー直下の一覧を表示する
- 一覧に含める項目（対応ファイル・非対応ファイル・サブフォルダー・隠しファイル）は、サイドバーの現在の隠しファイル表示設定（`HiddenFilesPreference.showHiddenFiles`）に従う。フィルタ内容を独自に持たない
- 並び順はサイドバーの現在のソート設定（`FileListModel.sortOrder`: フォルダー優先／アルファベット混在）に従う。固定値にしない
- 非対応ファイルの見た目・クリック時の扱いはサイドバーと同じ基準に揃える（除外・無効化はしない）
- プレビュー内の一覧でもシングルクリックは選択のみ、ダブルクリックでファイルを開く／サブフォルダーへ移動する（サイドバーと同じ操作感）
- フォルダーへの移動（ダブルクリック）時に自動的に最初のファイルを開く挙動を廃止し、移動後は新しいフォルダーの一覧を表示するだけにする
- プレビュー内の一覧でのダブルクリック操作（ファイルを開く／サブフォルダーへ移動）は、サイドバー側の表示（選択ハイライト・現在のディレクトリ）にもそのまま反映される（サイドバーとプレビューが別々の状態を持たないため、追従は自動的に成立する）
- 戻る操作は既存の「..」（親ディレクトリ）行をそのまま使い、新規UIは追加しない
- zip アーカイブの中身表示は本スペックのスコープ外（将来「フォルダーと同様に振る舞うコンテナ」として拡張する可能性があるとだけ記録する）

## Architecture

### 現在の構成

```
ViewerContentView
  └── ViewerWebView (WKWebView)  ← filePath を常に描画対象とする
        ViewerStore.filePath: URL?
```

サイドバー（`FileListView` / `FileListModel` / `SidebarNavigator`）でフォルダーを選択しても `ViewerStore` には何も伝わらず、プレビューエリアは無反応のまま。

### 変更後の構成

```
ViewerContentView
  ├── selection がファイル → ViewerWebView（既存のまま）
  └── selection がフォルダー → FolderListingView（新規、SwiftUI List）
```

`FolderListingView` は WKWebView を使わず、`DirectoryLister.listEntries` の結果をそのまま SwiftUI の `List` で表示するネイティブビュー。新しい状態やナビゲーションスタックは持たず、`FileListModel.selection` / `SidebarNavigator.currentDirectory` を単一の情報源として参照する。

## Changes to Existing Components

### ViewerContentView

- `FileListModel.selection` が指すエントリの `kind` を見て、`.file` なら既存の `ViewerWebView`、`.folder` なら `FolderListingView` を表示する分岐を追加する。

### FolderListingView（新規）

- 表示データは `DirectoryLister.listEntries(in: selectedFolder, sortOrder:, showHiddenFiles:)` を、`FileListModel.sortOrder` と `HiddenFilesPreference.showHiddenFiles`（サイドバーが参照しているのと同じ値）を渡して取得する。値を固定・複製せず、サイドバー側の設定が変わればこのビューの一覧にも同じ値が反映される。
- 行の見た目は `FileListView` の `entryRow` と同じ基準に揃える。非対応ファイルはラベルテキストを secondary カラーにするのみで、選択・クリック自体は禁止しない。
- シングルクリック: 行をハイライト選択するのみ（サイドバーの `singleTapGesture` と同じ）。
- ダブルクリック:
  - ファイル → 既存の `onSelect(url)` 経路を呼び、通常のファイルプレビューに切り替える（非対応ファイルの場合は既存の `ViewerStore` の非対応表示に委ねる）。
  - サブフォルダー → 既存の `SidebarNavigator.navigateToFolder(_:)` をそのまま呼ぶ。
- いずれの経路も `FileListModel`/`SidebarNavigator` の状態を直接更新するため、サイドバー（`FileListView`）の選択ハイライトや表示中ディレクトリも同じ操作で自動的に追従する。サイドバー側に個別の同期処理を追加する必要はない。

### SidebarNavigator.navigateToFolder

- 現在「移動後にファイルが存在すれば `entries.first(where: { $0.kind == .file })` を自動的に開き、ファイルが無ければ `selection = nil` にする」という条件分岐になっているものを、**ファイルの有無に関わらず常に `selection = nil`** にする処理へ一本化する。
- 移動後は `currentDirectory` の更新とエントリ再取得のみ行う（何も選択されていない状態 = プレビューエリアは「現在のディレクトリの一覧」を表示する状態になる）。
- 直接ファイルを開いた場合（`ViewerWindowController.init` 経由）や、サイドバー上でファイルを選択・切り替えた場合（`SidebarNavigator.syncAfterSwitch`）は従来通り `selection` がそのファイルに同期されるため、この変更と衝突しない（`selection` が nil のままになるのは常にフォルダー移動直後のみ）。

## Data Flow

```
1. サイドバーでフォルダーをシングルクリック
   → FileListModel.selection が変化（既存動作のまま）
   → ViewerContentView が selection の kind を見て FolderListingView に切り替え
   → FolderListingView が DirectoryLister.listEntries(in: 選択フォルダー) を表示

2. FolderListingView 内でファイルをダブルクリック
   → 既存の onSelect(url) → ViewerStore.openFile(_:)
   → ViewerContentView は selection が file になったので ViewerWebView に切り替わる

3. FolderListingView 内でサブフォルダーをダブルクリック
   → SidebarNavigator.navigateToFolder(url)（自動オープンなし）
   → currentDirectory 更新、selection はクリア
   → ViewerContentView は「selection なし・currentDirectory あり」を新ディレクトリの一覧表示として扱う
   → FolderListingView が新しい一覧を表示

4. 「..」行のダブルクリック
   → navigateToFolder(currentDirectory.deletingLastPathComponent())（既存動作のまま、自動オープンなしに統一）
```

## Edge Cases

- フォルダーに何も対応ファイル・サブフォルダーがない: 空状態メッセージを表示する（既存のサイドバー空状態メッセージと表現を揃える）
- 読み取り権限エラー・パス消失（表示中に削除された等）: 既存の `FileWatcher`/`ViewerStore` のエラー表示パターンに準拠する
- 非対応ファイルをダブルクリックした場合: 既存の `ViewerStore.isRejected` による非対応表示がそのまま出る（サイドバーで同じファイルを開いた場合と同一の見た目にする）

## Out of Scope

- zip アーカイブの中身表示（将来「フォルダーと同様に振る舞うコンテナ」として拡張する可能性のみ記録）
- サイドバーの開閉可能化（別案として検討中、本スペックには含めない）
- パンくずリストなどの新規ナビゲーションUI
- ソート順・隠しファイル表示の切り替えUIをプレビューエリア側に新設すること（サイドバー側の既存トグルの値を参照するのみで、プレビューエリア専用の切り替え操作は追加しない）
