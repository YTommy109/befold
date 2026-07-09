# 不可視ファイル表示トグル設計

## 概要

サイドバーのファイル一覧に、不可視ファイル・フォルダー(ドットファイル)の表示/非表示を切り替えるトグル機能を追加する。デフォルトは非表示。ユーザーの選択は `UserDefaults` に永続化し、次回起動時も最後のモードを継続する。切り替えはアプリ全体・全ウィンドウで共通の状態として即座に連動する。

操作経路は3つ用意する:
- キーボードショートカット `Cmd+.`(Unix 慣習でピリオド始まりのファイルが不可視になることに由来)
- View メニューの新規メニュー項目
- サイドバー右上、既存のソート順ボタンの隣に置くアイコンボタン

## アーキテクチャ

```
AppDelegate
  ├── HiddenFilesPreference       # 新規: showHiddenFiles: Bool、UserDefaults 永続化
  ├── toggleHiddenFiles(_:)       # 新規アクション。NSMenuItemValidation でメニュー文言反転
  └── ViewerWindowManager
        ├── hiddenFilesPreference (注入、zoomStore と同列)
        ├── refreshAllSidebars()  # 新規: 全 controllers のサイドバーを再読み込み
        └── ViewerWindowController (per window)
              └── SidebarNavigator
                    └── DirectoryLister.listEntries(in:sortOrder:showHiddenFiles:)

MainMenuBuilder
  └── View メニューに新規項目(keyEquivalent: ".")

FileListView
  └── header 内に新規アイコンボタン(sort ボタンの隣)
```

## 詳細設計

### 1. `HiddenFilesPreference`(新規、`App/HiddenFilesPreference.swift`)

`ZoomStore` と同じ「注入して共有する」パターンに倣う、薄い永続化専用クラス。

```swift
@MainActor
final class HiddenFilesPreference {
    private let defaults: UserDefaults
    private static let showHiddenFilesKey = "ShowHiddenFiles"

    var showHiddenFiles: Bool {
        didSet {
            defaults.set(showHiddenFiles, forKey: Self.showHiddenFilesKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showHiddenFiles = defaults.bool(forKey: Self.showHiddenFilesKey)
    }
}
```

- デフォルト値: `false`(不可視ファイルは非表示)
- `AppDelegate.init()` で1つだけ生成し、`ViewerWindowManager` に注入する(`sessionStore` / `zoomStore` / `recentDocumentsStore` と同列)
- 複数ウィンドウで同一インスタンスを共有するが、`@Observable` にはしない。SwiftUI の自動連動には頼らず、変更時は明示的に `refreshAllSidebars()` で再読み込みを指示する(既存コードベースにウィンドウ横断のライブ連動の前例がないため、単純な「共有インスタンス + 明示的リフレッシュ」で揃える)

### 2. `DirectoryLister` の拡張

`listEntries(in:sortOrder:)` に `showHiddenFiles: Bool` パラメータを追加し、`FileManager.contentsOfDirectory` に渡す `options` から `.skipsHiddenFiles` の付与を条件分岐する。

```swift
static func listEntries(
    in directory: URL, sortOrder: SortOrder, showHiddenFiles: Bool
) -> [FileListEntry] {
    let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
    // ...
}
```

`listFiles(in:)` / `containsSupportedFile` / `firstSupportedFile` は対象外(初期表示ファイルの自動選択ロジックであり、一覧の表示/非表示トグルとは無関係)。

呼び出し側3箇所(いずれも `showHiddenFiles` 引数を追加):
- `SidebarNavigator.refreshFileList()`
- `SidebarNavigator.navigateToFolder(_:)`
- `ViewerWindowController.init` の初期 `listEntries` 呼び出し

`SidebarNavigator` は `HiddenFilesPreference` への参照を保持し(`FileListModel` には複製しない、`sortOrder` とは異なり単一の真実の源をそのまま参照する)、呼び出し時に `hiddenFilesPreference.showHiddenFiles` を直接読む。

### 3. `ViewerWindowManager.refreshAllSidebars()`(新規)

```swift
func refreshAllSidebars() {
    for controller in controllers.values {
        controller.sidebar.refreshFileList()
    }
}
```

`AppDelegate.toggleHiddenFiles(_:)` から呼ばれ、開いている全ウィンドウのサイドバーを即座に再読み込みする。

### 4. `AppDelegate` のアクション・メニュー検証

```swift
@objc func toggleHiddenFiles(_ sender: Any?) {
    hiddenFilesPreference.showHiddenFiles.toggle()
    windowManager.refreshAllSidebars()
}
```

`AppDelegate` は `NSMenuItemValidation` に準拠し、`validateMenuItem` で `toggleHiddenFiles(_:)` のメニュー項目タイトルを `showLineNumbers` と同じ「表示/非表示」文言反転方式で切り替える(チェックマークではなくラベル反転が本アプリの既存慣習)。

### 5. メニュー項目(`MainMenuBuilder.makeViewMenuItem()`)

`toggleSidebar` の区切り線の後に追加する。

```swift
menu.addItem(
    withTitle: String(localized: "menu.view.showHiddenFiles", bundle: .l10n),
    action: #selector(AppDelegate.toggleHiddenFiles(_:)),
    keyEquivalent: "."
)
```

`target` は `nil`(レスポンダチェーン経由で `AppDelegate` に到達する。`showOpenPanel` と同じ方式)。`keyEquivalent: "."` はデフォルトの Cmd 修飾のみで `Cmd+.` となるため、`keyEquivalentModifierMask` の上書きは不要。

ローカライズキー(`Localizable.xcstrings` に追加): `menu.view.showHiddenFiles` / `menu.view.hideHiddenFiles`

### 6. サイドバーのアイコンボタン(`FileListView.swift`)

`header` の `HStack` 内、既存のソートボタンの隣に追加する。

```swift
Button {
    onToggleHiddenFiles()
} label: {
    Image(systemName: hiddenFilesPreference.showHiddenFiles ? "eye" : "eye.slash")
        .foregroundStyle(hiddenFilesPreference.showHiddenFiles ? .primary : .secondary)
}
.buttonStyle(.borderless)
.help(hiddenFilesPreference.showHiddenFiles
    ? String(localized: "sidebar.hiddenFiles.hide", bundle: .l10n)
    : String(localized: "sidebar.hiddenFiles.show", bundle: .l10n))
```

- アイコン: 表示中は `"eye"`、非表示中(デフォルト)は `"eye.slash"`
- 配色: `ViewerTopBar` の `showLineNumbers` トグルと同じルール(オン時 `.primary`、オフ時 `.secondary`)
- タップ時の処理は `onToggleHiddenFiles: () -> Void` クロージャ経由で `AppDelegate.toggleHiddenFiles(_:)` と同じ経路(トグル + `refreshAllSidebars()`)を通す。`ViewerWindowController` から `onSortOrderChanged` と同様に配線する
- ローカライズキー: `sidebar.hiddenFiles.show` / `sidebar.hiddenFiles.hide`

他ウィンドウでの切り替えも `refreshAllSidebars()` により即座に反映されるため、ボタンの見た目・メニュー文言は常に最新状態を表示する。

## 状態伝搬の流れ

1. ユーザーがショートカット(`Cmd+.`)・メニュー・アイコンボタンいずれかを操作
2. `AppDelegate.toggleHiddenFiles(_:)` が呼ばれ、`hiddenFilesPreference.showHiddenFiles` をトグルして `UserDefaults` に永続化
3. `windowManager.refreshAllSidebars()` が開いている全 `ViewerWindowController` の `sidebar.refreshFileList()` を呼ぶ
4. 各 `SidebarNavigator` が `DirectoryLister.listEntries(in:sortOrder:showHiddenFiles:)` を現在の `hiddenFilesPreference.showHiddenFiles` で再実行し、`fileListModel.entries` を更新
5. SwiftUI が各ウィンドウのサイドバー・アイコンボタン・メニュー項目タイトルを再描画

## テスト計画

- `DirectoryLister` のユニットテスト: `showHiddenFiles: true/false` それぞれでドットファイル・ドットフォルダーの出現有無を検証
- `HiddenFilesPreference` のユニットテスト: トグルと `UserDefaults` 永続化・再読み込み
- 手動テスト: `Cmd+.`・メニュー・アイコンボタンそれぞれからの切り替え、複数ウィンドウを開いた状態での即時連動、再起動後のモード継続
