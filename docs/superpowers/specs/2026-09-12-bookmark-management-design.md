# ブックマーク管理（別名・削除・ドラッグ&ドロップ追加・フォルダー）

<!-- derived-from ./2026-07-16-bookmark-feature-design.md -->
<!-- constrained-by ../../adr/0002-presentation-state-and-capabilities.md#アプリの好みの規則 -->

> **これは 2026-09-12 時点の設計スナップショットです。**
> 現在の仕様は [`docs/dev/native-app-design.md`](../../dev/native-app-design.md)
> が単一の情報源。この文書は当時の意図と検討経緯を残すためのもので、
> 現在の実装と食い違っていることがある。着手前に必ずコードで裏を取ること。

## 背景

TASK-536 の 4 サブタスク（別名 / 管理 UI からの削除 / Finder からの D&D 追加 /
フォルダー階層）が共有する設計をここに 1 回だけ書く。サブタスクごとの
`/review-design` はこの文書を Implementation Plan の前提として回す。

現状（実測 2026-09-12、コード参照）:

- `BookmarkStore`（`BefoldApp/BefoldKit/BookmarkStore.swift`）は `PathListDefaults` 経由で
  UserDefaults キー `"BookmarkedPaths"` に正規化パスの `[String]` を持つだけ。別名・順序・
  フォルダーのメタデータは無い
- 一覧はトップレベルの Bookmarks メニュー（`BookmarksMenuController`、TASK-535）が
  表示直前に `lastPathComponent` 順で作り直す。**メニュー表示では stat しない**
  （`BookmarksMenuController` は `FileReading` を持たない。応答しないマウントで待たされるため）
- 読み手: メニュー / `MissingBookmarksPruner` / Quick Open（origin の付与だけ、候補には
  注入しない）/ ツールバー・View メニューの `isBookmarked`
- 書き手: ウィンドウのトグル（⌘D）/ `FileNotFoundUI` の「ブックマークから削除」/
  `MissingBookmarksPruner.removeAll` / rename 追随の `noteRenamed` / **CLI `--bookmark`**
  （GUI 起動中は転送して GUI を唯一の writer にする。`CLIBookmarkRouter`）
- 管理 UI は存在しない。単一インスタンスのパネルは `HostedPanel` +
  `HostedPanelPresenter` + `HostedPanelWindowController`（About / 設定 / Help 配下）の
  1 経路で、SwiftUI ビューを `NSHostingController` に載せる
- D&D はアプリ内に 0 件（`onDrop` / `NSDraggingDestination` とも実測 0）

## 決めたこと

### 1. 永続化: 1 キー・フラットな Codable レコード・一度きり移行

新キー `"Bookmarks"` に JSON `Data` で次を保存する（`RecentRepositoriesStore` と同じ
`JSONEncoder` / `defaults.data(forKey:)` の形）。

```swift
public struct BookmarkLibrary: Codable, Equatable, Sendable {
    public var folders: [BookmarkFolder]   // 空のフォルダーも存在させるため明示的に持つ
    public var entries: [BookmarkEntry]    // 保存順 = 表示順の基礎（今は表示時に名前順ソート）
}
public struct BookmarkFolder: Codable, Equatable, Sendable {
    public var path: [String]              // ルートからの名前列。["Work", "Specs"]
    public var isExpanded: Bool
}
public struct BookmarkEntry: Codable, Equatable, Sendable {
    public var path: String                // normalizedPathKey
    public var alias: String?              // nil = ファイル名で表示
    public var folder: [String]            // 所属フォルダーの名前列。[] = ルート
}
```

- **木ではなく名前列で階層を表す。** 再帰的な enum を Codable にするには手書きの
  `init(from:)` / `encode(to:)` が要り、フォルダーの改名・移動・削除が木の探索になる。
  名前列なら全操作が配列の filter / map で書け、`Codable` は合成で足りる
- 同じ親の下でフォルダー名は一意（`BookmarkLibrary` が作成・改名時に弾く）。
  フォルダーの同一性は名前列で決まるので UUID を持たない
- 純粋な操作（追加・削除・別名・フォルダー作成/改名/削除/移動・展開状態）はすべて
  値型 `BookmarkLibrary` の mutating メソッドに置き、`BookmarkStore` は
  「読む → 1 操作 → 書く」の薄い層にする。**単体テストは `BookmarkLibrary` で書き、
  UserDefaults を通すのは移行と永続化の往復だけ**
- 将来フィールドを足すときは optional / 既定値あり（`RecentRepositoryEntry` の doc と同じ理由）
- 旧キー `"BookmarkedPaths"` は `BookmarkStore.init` で一度だけ移行し、**移行の有無に
  かかわらず `defer` で削除する**（CLAUDE.md「UserDefaults キーの廃止・改名」）。
  旧配列の各パスは `alias: nil` / `folder: []` のエントリになる。
  テストは 3 ケース（旧値あり / 旧値なし / 移行済み）
- CLI（`befold-cli` プロセス）も同じ `BookmarkStore` を作るので、GUI 未起動時の
  `--bookmark` で移行が走ることがある。同じコードなので結果は同じ。単一 writer の規則は
  `CLIBookmarkRouter` が従来どおり守る。CLI からの追加は常にルート・別名なし
- `PathListDefaults` は Session / Recent が使い続けるので触らない。`BookmarkStore` だけが
  依存をやめる

### 2. 既存 API の意味は変えない

`isBookmarked` / `add` / `toggle` / `remove` / `removeAll` / `bookmarkedURLs` /
`noteRenamed` は今のまま（`bookmarkedURLs` は全フォルダーを平坦化して返す）。
`noteRenamed` はパスだけ差し替え、`alias` と `folder` は保持する（536.1 AC #4）。
これにより `MissingBookmarksPruner` / Quick Open / ツールバーの読み手は変更なし。

Quick Open は別名を検索対象にしない（候補は索引由来で、ブックマークは origin の付与だけ。
`2026-07-26-quick-open-design.md`）。別名で引けるようにするのは別タスク。

### 3. 管理 UI: `HostedPanel.bookmarks`

- `HostedPanel` に `.bookmarks` を足し、`HostedPanelPresenter.makeController` で
  `BookmarkManagerView`（SwiftUI）を `HostedPanelWindowController` に載せる
  （resizable、520×420、min 400×300）。文書の窓ではないので `ViewerWindowKind` には
  乗せない
- 入口は Bookmarks メニューの固定部「Edit Bookmarks…」（`menu.bookmarks.edit`、
  キー等価なし → 紹介サイトの `shortcuts.test.ts` の集合は変わらない）。固定部は
  `MainMenuBuilder.addBookmarkToggleItem(to:)` と同じ理由で組み立て時と再生成時の
  両方から置く。アクションは `AppDelegate.showBookmarkManager(_:)` → `panels.toggle(.bookmarks)`
- `BookmarkManagerModel`（`@MainActor @Observable`）が `BookmarkLibrary` のスナップショットを
  持ち、各操作は `BookmarkStore` へ書いてからスナップショットを取り直す。書いたあとに
  `onChange`（= `GlobalDisplayBroadcaster.refreshAllToolbars`）を呼び、開いている窓の
  ブックマークボタンを追随させる（536.2 AC #3）。パネルが key になったときも取り直す
  （窓側の ⌘D で変わった分を拾う）
- **パネルでも stat しない。** 欠落バッジは出さず、「開けないブックマークを削除…」は
  メニューの既存経路に任せる（`MissingBookmarksPruner` の約束を守る）
- 行の識別子は `enum BookmarkRow: Hashable { case folder([String]); case bookmark(String) }`。
  `List(selection:)` で単一選択、行の右クリックメニューに「別名を変更…」「削除」
  （フォルダー行は「名前を変更…」「削除」）、ツールバー風の「新規フォルダー」「削除」ボタン
- 文字入力（別名・フォルダー名）は **`.alert` に `TextField` を置く**（macOS 13+ で可、
  本アプリは 14+）。インライン編集は前例が無く、`List` 行の編集モードを自前で持つより小さい
- ダブルクリックで開く（`ViewerWindowManager.openViewer(for:)`）。`FileNotFoundUI` の
  既存経路にそのまま乗る
- 一覧は `DisclosureGroup(isExpanded:)` を再帰で組む。展開状態は
  `BookmarkFolder.isExpanded` に書き戻す（536.4 AC #3）

### 4. Finder からの D&D（536.3）

- `List` 全体に `.onDrop(of: [.fileURL], isTargeted:)`、フォルダー行にも同じ修飾子
  （落とし先 = そのフォルダー）。`NSItemProvider.loadObject(ofClass: URL.self)` で
  URL を取り、`Task { @MainActor in }` でモデルへ渡す
- 受け入れ規則（`BookmarkManagerModel.addDropped(_:into:)`、純粋関数として切り出す）:
  - 存在しない → 弾く（`FileReading.fileExists`。ドロップ時だけの stat なのでメニューの
    約束と衝突しない）
  - 通常ファイルで `FileType.isSupported` でない → 弾く
  - ディレクトリ → 受け入れる（`DocumentOpener` はフォルダーを開ける）
  - 既に登録済み → 追加しない（重複なし。既存の `add` の冪等性で足りる）
- 弾いた分は**モーダルにしない**。パネル下部の 1 行に「n 件を追加できませんでした」と
  パスを出す（`@State` の文字列）。ドロップは連続で起きるので、そのたびに NSAlert が
  出ると操作が止まる
- 受け入れた分は全部追加する（複数ファイル同時ドロップ = 536.3 AC #2）

### 5. フォルダー（536.4）

- 作成: 選択中のフォルダー（無ければルート）の下に。名前の重複は弾き、alert で伝える
- 改名: 名前列の接頭辞を持つ全フォルダー・全エントリを書き換える
- 削除: **配下のエントリとサブフォルダーは親へ（トップレベルなら = ルートへ）繰り上げる。**
  確認ダイアログは挟まない（失われるものが無いため。536.4 AC #4 は「ルートへ戻す、または
  削除確認」なので前者を採る）。繰り上げ先に同名フォルダーがあれば改名と同じ規則で弾く
- 所属変更: 右クリック「移動…」で既存フォルダーを Picker で選ぶ。パネル内の行 D&D は
  実装しない（Finder からの D&D と別の SwiftUI 機構で、今回のスコープ外）

### 6. サブタスクの順序と持ち分

スキーマは 1 回しか変えない。移行を 536.4 に置く起票時の想定を改め、**536.1 がスキーマと
移行を持つ**。

| 順 | タスク | 持ち分 |
| --- | --- | --- |
| 1 | 536.1 | `BookmarkLibrary` / 新キー・移行（3 ケース）/ `BookmarkStore` の薄層化 / メニューの別名表示 / **パネルの新設**（一覧・別名変更・ダブルクリックで開く）/ Bookmarks メニューの「Edit Bookmarks…」 |
| 2 | 536.2 | パネルからの削除（右クリック・ボタン）と全窓ツールバーの追随 |
| 3 | 536.4 | フォルダーの作成・改名・削除・所属変更・展開状態 |
| 4 | 536.3 | Finder からの D&D（落とし先がフォルダーでも動くよう、536.4 の後） |

依存は backlog の `--dep` で構造にする（536.2 / 536.4 → 536.1、536.3 → 536.4）。

## 破れたら落ちるもの

- 移行 3 ケース（`BookmarkStoreMigrationTests`）と、旧キーが `defer` で消えること
- `noteRenamed` 後に alias / folder が残ること（`BookmarkStoreTests`）
- `BookmarkLibrary` の不変条件: 同一パスは 1 件、同じ親でフォルダー名は一意、
  フォルダー削除で件数が減らない、改名で接頭辞が全件書き換わる
- メニュー表示が永続化を書き換えないこと（既存の
  `menuUpdateDoesNotMutatePersistedBookmarks` を維持）
- 固定部に「Edit Bookmarks…」が再生成後も残ること（`keepsBookmarkToggleAfterRebuild` と同型）
- D&D の受け入れ規則（`InMemoryFileReader` で存在・種別・重複の 4 通り）

## スコープ外

- 別名を Quick Open の検索対象にする
- パネル内の行 D&D（並び替え・フォルダー間移動）
- ブックマークの手動並び替え（保存順は持つが表示は名前順のまま）
- 欠落バッジ（stat を伴うため。既存の一括削除で足りる）
