# 「最近使ったリポジトリを開く」メニュー 設計

開いたファイルが git リポジトリ内だった場合、そのリポジトリ（本体または worktree）のルートを
自動的に「最近使ったリポジトリ」として記憶し、File メニューから素早く再オープンできるようにする。
再オープン時は、そのリポジトリで最後に開いていたタブ構成（ファイル・選択タブ）があれば復元する。

対応 Backlog タスク: task-190

## 背景

既存の File メニューには「Open Recent」（`RecentDocumentsStore` +
`RecentDocumentsMenuController`）と「Bookmarks」（`BookmarkStore` +
`BookmarksMenuController`）という 2 つの同型サブメニューがすでにある。
いずれも UserDefaults に URL 配列を保存し、`NSMenuDelegate.menuNeedsUpdate` で
表示直前にメニュー項目を再構築するパターン。

`GitRepository`（`befold/App/GitRepository.swift`）は `git rev-parse --show-toplevel` で
リポジトリルートを解決する `GitRootLookup`（`.root(URL)` / `.notARepository` /
`.undetermined`）を持つが、worktree 判定は `.git` ファイルの `gitdir:` 行を手動パースする
実装のみで、`--git-common-dir` / `--git-dir` の比較は行っていない。

`SessionRestorer` / `SessionStore`（`befold/App/SessionRestorer.swift` /
`SessionStore.swift`）は「アプリ全体で1つのグローバルセッション」を前提とした設計で、
`SessionLayout.groups: [TabGroup]` は開いている全ウィンドウをフラットに1配列へまとめており、
どのリポジトリ（ルートディレクトリ）に属するタブかという情報を一切持たない。
`TabGroup(paths:selectedPath:)` は「1ウィンドウ分のタブ配列+選択タブ」を表す値型で、これ自体は
リポジトリ単位の記録にもそのまま再利用できる。`SessionRestorer` はタブグループ単位の復元ロジック
（`restoreTabGroup`）をすでに持っている。

## スコープ

### やること

- git リポジトリ内のファイルを開いた際、そのリポジトリ/worktree のルートを自動記憶
- File メニュー内に独立したサブメニュー「Recent Repositories」を新設し、選択すると
  そのルートを新規ウィンドウで開く。**そのリポジトリの最後のタブ構成が記憶されていれば
  それを復元し、無ければ従来どおりルートフォルダをサイドバー表示で開く**
  （既存の「フォルダを開く」経路 / `SessionRestorer` のタブグループ復元ロジックに乗せる）
- リポジトリのウィンドウの最後のタブ構成を記憶する（アクティブ化・クローズ・アプリ終了時）
- 本体リポジトリと worktree をメニュー上のラベルで区別
- 保持件数上限（10件）超過時の自動追い出し、重複排除、手動クリア
- worktree がメニュー表示時点で存在しない場合の自動的な一覧メンテナンス

### やらないこと

- グローバルセッション（`SessionStore` の起動時全体復元）自体の仕様変更。今回追加するのは
  「リポジトリ単位」の別枠の記憶であり、既存のアプリ全体セッション復元とは独立に動作する
- 「Open Recent」（ファイル）メニューとの統合表示（独立サブメニューとする、下記参照）
- worktree の作成・削除などの git 操作 UI（読み取り専用の記憶・再オープンのみ）
- 同一リポジトリを複数ウィンドウで同時に開いていた場合の全ウィンドウ分の記憶。
  記憶するのは1リポジトリにつき直近で閉じた1ウィンドウ分のタブ構成のみ（下記参照）

## 決定事項（オープンな論点への回答）

- **保持件数上限**: 10件（`RecentDocumentsStore` と揃える）
- **クリア手段**: サブメニュー末尾に「Clear Menu」項目を用意する
- **既存メニューとの関係**: 「Open Recent」「Bookmarks」と並ぶ独立サブメニュー
  「Recent Repositories」として新設する。ファイルを開く動線とリポジトリを開く動線は
  開く対象（ファイル vs フォルダ）が異なり、混在させると分かりにくくなるため
- **worktree ラベル表記**: worktree ディレクトリ名を併記する（例: `befold (olla-rattler)`）。
  ブランチ名は頻繁に切り替わり表示の安定性を欠くため採用しない。本体リポジトリは
  接尾辞なし（例: `befold`）
- **タブ構成の記録タイミング**: ウィンドウのアクティブ化（`viewerWindowDidBecomeKey`）・
  クローズ（`viewerWindowWillClose`）・アプリ終了（`applicationShouldTerminate`）の3点で記録する。
  当初は close 時のみとしていたが、`windowWillClose` の時点では AppKit が既に当該ウィンドウを
  タブグループから外しており（`window.tabGroup == nil`）、閉じる1枚分の構成しか組み立てられない。
  タブ構成を正しく観測できるのはウィンドウが生きている間だけのため、アクティブ化を主たる
  記録契機とする（セッション記録の `noteActivated` と同じイベントに載る）。
  また、アプリ終了時には `windowWillClose` が発火しないことがあるため、終了時に
  開いている全ウィンドウの構成を一括で記録する。
  同一リポジトリを複数ウィンドウで同時に開いていた場合は、最後に記録したウィンドウの状態が残る
  （レアケースとして許容）

## アーキテクチャ

### RecentRepositoriesStore（新規）

`befold/App/RecentRepositoriesStore.swift`。`RecentDocumentsStore` と同型だが、
リポジトリ識別情報に加えて「最後のタブ構成」も1件のエントリにまとめて保持する。

```
struct RecentRepositoryEntry: Codable, Equatable {
    var root: URL
    var worktreeDirectoryName: String?   // nil なら本体リポジトリ
    var lastTabGroup: SessionLayout.TabGroup?
}

final class RecentRepositoriesStore {
    // UserDefaults キー "RecentRepositories" に最大10件のエントリ配列を保存（JSON エンコード）
    func record(root: URL, worktreeDirectoryName: String?)   // 開いた際の記録・並び替え
    func updateLastTabGroup(root: URL, _ group: SessionLayout.TabGroup)  // ウィンドウ close 時
    func entries() -> [RecentRepositoryEntry]
    func pruneMissing()   // FileManager.fileExists で存在しないルートを除去し永続化も更新
    func clear()
}
```

`record` は既存エントリがあれば `lastTabGroup` を保持したまま先頭へ移動し、無ければ
`lastTabGroup: nil` で新規追加する（重複排除・最終利用順の維持）。`updateLastTabGroup` は
該当エントリの `lastTabGroup` のみを上書きし、並び順（利用順）は変更しない。

`updateLastTabGroup(root:_:force:)` は、`force` が false のとき「保存済み構成の真部分集合」への
縮小だけの書き込みを拒否する。タブは1枚ずつ閉じるため、close の連鎖では縮んでいく構成が
次々に届き、素直に上書きするとタブ1枚まで潰れてしまうためである。セッション中の記録は
「増える方向のみ」となり、ユーザーが意図的にタブを減らした結果は終了時の一括記録
（`force: true`）が正として上書きする。

### GitRepository の拡張

`--git-common-dir` と `--git-dir` を実行し、正規化した上でパス比較する形で worktree
判定を確定させる（一致＝本体、不一致＝worktree）。worktree の場合は
`--git-common-dir` の親ディレクトリ名を本体リポジトリ名として取得する。
既存の `.git` ファイル手動パース（`gitDirectory(at:)`）はこの新しい判定に置き換えるか、
内部実装として温存しつつ公開 API は新判定に統一する（実装時に既存呼び出し元への影響を見て決定）。

### RecentRepositoriesMenuController（新規）

`befold/App/RecentRepositoriesMenuController.swift`。`RecentDocumentsMenuController` と同型。

```
final class RecentRepositoriesMenuController: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        store.pruneMissing()          // 表示直前に存在チェック・一覧メンテナンス
        let entries = store.entries()
        // ラベル整形（本体 / worktree）+ representedObject に root URL + Clear Menu 項目
    }
}
```

存在チェックは専用の `applicationDidBecomeActive` フックを設けず、
メニュー表示直前（`menuNeedsUpdate`）に一本化する。ユーザーが一覧を目にする瞬間は
常にメニューを開いた時であり、そこで毎回 `pruneMissing()` すれば見た目の一貫性は
保てるため、別経路の状態更新ロジックは追加しない（単純化）。

### ViewerWindowController / ViewerWindowManager（既存を拡張）

`ViewerWindowController` に `repositoryRoot: URL?`（新規プロパティ）を追加する。
`ViewerWindowManager.openViewer(...)` がウィンドウ生成時に root を1回解決した結果
（`recentRepositoriesStore.record(...)` に使うのと同じ呼び出し）をそのままこのプロパティに
キャッシュする。これにより、ウィンドウが閉じる際に git を再度呼ばずに済む。

root 解決とラベル解決はどちらも git の subprocess を待ち、`GitCommandFileIndex` の共有ロックの
内側で直列化されるため、MainActor で同期実行するとウィンドウを開くたびに UI が止まる。
解決は `Task.detached` で行い、結果の反映（`repositoryRoot` の代入と `record`）だけ MainActor へ
戻す（`SidebarNavigator` の `resolveGitRoot` と同じ方針）。解決完了前にウィンドウが閉じられた
場合、そのウィンドウ分の記録は行われない（次に開いたときに記録されるため許容する）。

`ViewerWindowManager` は `controller.repositoryRoot` が非 nil のとき、そのウィンドウのタブ構成
（`SessionRestorer` が `currentSessionLayout()` で使っているのと同じ「1ウィンドウ分の
`TabGroup` を組み立てるロジック」を `tabGroup(of window:)` として切り出す）を組み立て、
`recentRepositoriesStore.updateLastTabGroup(root:_:force:)` を呼ぶ。呼ぶ契機は
`viewerWindowDidBecomeKey`（force なし）・`viewerWindowWillClose`（force なし）・
`AppDelegate.applicationShouldTerminate` からの `recordAllRecentRepositoryTabGroups()`
（force あり、全ウィンドウ分）の3つ。
この処理は `SessionStore.isFrozen` の状態に関係なく常に実行する
（グローバルセッションの終了時凍結とは別目的のため）。終了時の一括記録は
`sessionStore.freeze()` より前、セッションレイアウトのスナップショットと同じ位置で行う。

### SessionRestorer（既存を拡張）

タブグループ復元ロジック（`restoreTabGroup`）を、グローバルセッション復元専用の
`private` から、単一の `TabGroup` を任意のウィンドウとして開ける形に整理し、
新規の公開メソッドを追加する。

```
func openRepository(root: URL, savedTabGroup: SessionLayout.TabGroup?, options: CLIOpenOptions = CLIOpenOptions())
```

`savedTabGroup` を実在パスに `filtered` した結果が空でなければ `restoreTabGroup` で
タブ構成ごと新規ウィンドウとして開く。`nil` または空になった場合は、`root`(ディレクトリ)を
`DirectoryLister.resolveFileToOpen(at:)` で中の対応ファイルへ解決してから
`windowManager.openViewer(for:, forceSidebarVisible: true, ...)` を呼ぶフォールバックへ縮退する
(`openViewer` はファイルを渡す前提のため、ディレクトリをそのまま渡すと壊れたウィンドウになる)。
対応ファイルが1つも無い場合は何もしない。

### MainMenuBuilder / AppDelegate（既存を拡張）

`MainMenuBuilder.makeFileMenuItem` に「Recent Repositories」サブメニューを
「Open Recent」「Bookmarks」と並べて追加する。`AppDelegate` に
`recentRepositoriesStore` / `recentRepositoriesMenuController`（`lazy var`）を追加し、
openHandler で `sessionRestorer.openRepository(root: url, savedTabGroup: entry.lastTabGroup)` を
呼ぶ（`AppDelegate` はすでに `sessionRestorer` を保持している）。

## データフロー

```
AppDelegate.openViewer(for:options:)
  → ViewerWindowManager.openViewer(...) 内で GitRepository.root(forFileAt:) を解決
  → .root(url) の場合のみ:
      controller.repositoryRoot = url にキャッシュ
      GitRepository の worktree 判定 → recentRepositoriesStore.record(root:worktreeDirectoryName:)
  → 通常の openViewer 処理を継続（既存フローに影響しない）

ウィンドウが閉じる時（viewerWindowWillClose）:
  controller.repositoryRoot が非 nil の場合:
    tabGroup(for: window) でそのウィンドウのタブ構成を組み立て
    → recentRepositoriesStore.updateLastTabGroup(root:, group)
  （既存の sessionStore.noteClosed(...) はそのまま継続）

メニュー表示時:
  RecentRepositoriesMenuController.menuNeedsUpdate
    → store.pruneMissing()
    → store.entries() をラベル整形してメニュー項目化

メニュー選択時:
  openHandler(entry) → sessionRestorer.openRepository(root: entry.root, savedTabGroup: entry.lastTabGroup)
    → savedTabGroup があり実在パスが残っていれば restoreTabGroup でタブごと復元
    → 無ければ root を DirectoryLister.resolveFileToOpen(at:) で中の対応ファイルへ解決し、
      windowManager.openViewer(for: 解決したファイル, forceSidebarVisible: true, ...) を呼ぶ
      (対応ファイルが1つも無ければ何もしない)
```

## エラー処理

- `GitRootLookup` が `.notARepository` / `.undetermined`（git 不在・実行失敗含む）の場合は
  記録しない（AC#5 を安全側に倒す）
- 記録後にディレクトリが消えた場合（worktree 削除など）は `pruneMissing()` で
  次回メニュー表示時に自動的に一覧から除去される
- worktree 判定用の git コマンドが失敗した場合は本体扱い（ラベル接尾辞なし）に縮退する
- `lastTabGroup` 内のパスが一部/全部消えている場合は `filtered` で存在するものだけに
  絞り込む。空になった場合はタブ復元をあきらめ、ルートフォルダを開くフォールバックへ縮退する

## テスト

- `RecentRepositoriesStore`: `makeIsolatedDefaults` を用い、追加・重複排除・
  上限（10件）超過時の追い出し・`pruneMissing`・`clear`・`updateLastTabGroup` による
  既存エントリの `lastTabGroup` 更新（並び順は変わらないこと）を検証
- `GitRepository` の worktree 判定拡張: 一時ディレクトリに本体リポジトリと
  `git worktree add` で作った worktree を用意し、`--git-common-dir` ベースの判定・
  本体リポジトリ名の取得が正しく行われることを検証
- `RecentRepositoriesMenuController`: ラベル整形（本体 / worktree 併記）・
  `pruneMissing` 呼び出しタイミング・Clear Menu 項目表示のロジックを単体テスト
- `SessionRestorer.openRepository`: 保存済み `TabGroup` の全パス実在時の復元、
  一部パス消失時の `filtered` 後の復元、全パス消失時のフォールバックの3パターンを検証
- WebView を伴わない純粋な AppKit メニュー・ウィンドウ構築のため、GUI 自動テストは対象外
  （リリース前に目視確認: 本体で開く／worktree で開く／worktree 削除後の一覧更新／
  タブ構成の記憶と復元／保存済みタブの一部ファイル削除後の縮退）
