---
id: TASK-536.1
title: Bookmark に別名を付けられるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-21 07:27'
updated_date: '2026-09-12 13:48'
labels: []
milestone: m-9
dependencies: []
parent_task_id: TASK-536
priority: medium
type: feature
ordinal: 777000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在ブックマークはパス文字列のみを保持し、表示名は常に `lastPathComponent` から算出される（`BookmarksMenuController.swift:29-44`）。任意の別名（表示名）を設定・保存できるようにする。

データモデル（`BookmarkStore` もしくは `PathListDefaults` 相当）に、ファイルパスと関連付けた表示名フィールドを追加する。既存の `noteRenamed(from:to:)`（`BookmarkStore.swift:56-58`、ファイルのリネーム・移動時にパスを追随させる仕組み）との整合を保つこと（パスは追随するが、ユーザーが設定した別名は保持される必要がある）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ブックマークごとに別名を設定できる（管理パネル Bookmarks > Edit Bookmarks… の右クリック「別名を変更…」）
- [x] #2 別名未設定のブックマークは従来どおりファイル名で表示される
- [x] #3 別名を設定したブックマークは Bookmarks メニューの一覧と管理パネルに別名で表示される（パス列はそのまま）
- [x] #4 ファイルのリネーム・移動時、パスが更新されても設定済みの別名（と所属フォルダー）は保持される
- [x] #5 別名の保存・読み込み・リネーム時の保持をユニットテストで担保する
- [x] #6 永続化を新キー Bookmarks（JSON の BookmarkLibrary）へ移し、旧キー BookmarkedPaths からの一度きり移行を (a) 旧値あり (b) 旧値なし (c) 移行済み の 3 ケースのユニットテストで担保する。旧キーは移行の有無にかかわらず削除される
- [x] #7 既存の読み手（Bookmarks メニュー / MissingBookmarksPruner / Quick Open / ツールバー）と書き手（⌘D / FileNotFoundUI / CLI --bookmark）は API 変更なしで動き、既存テストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldKit に BookmarkLibrary（folders / entries、名前列で階層）を値型で新設し、追加・削除・別名・rename 追随の純粋操作をここへ置く
2. BookmarkStore を「読む→1 操作→書く」の薄層にし、新キー Bookmarks（JSON Data）へ移す。init で旧キー BookmarkedPaths を一度だけ移行し defer で削除する
3. 既存 API（isBookmarked/add/toggle/remove/removeAll/bookmarkedURLs/noteRenamed）の意味を保つ。library() と setAlias(_:for:) を足す
4. NSMenu.addFileItems に表示名を渡せる形を足し、BookmarksMenuController が alias ?? lastPathComponent で並べる
5. HostedPanel.bookmarks と BookmarkManagerView / BookmarkManagerModel を新設（一覧・別名変更 alert・ダブルクリックで開く）。Bookmarks メニュー固定部に「Edit Bookmarks…」（キー等価なし）を足し、組み立て時と再生成時の両方で置く
6. テスト: BookmarkLibraryTests / BookmarkStoreMigrationTests（3 ケース）/ BookmarkStoreTests に alias 保持 / BookmarksMenuControllerTests に alias 表示と固定部 2 項目 / MainMenuBuilderTests
7. xcodegen generate、swiftformat、swift test、xcodebuild、swiftlint ベースライン、l10n-check。MainMenuBuilder の例外上限を実測値へ更新

## /review-design の結果（2026-09-12）

- 項目 1（真実の源）: 移行の判定は「新キーの Data が無い かつ 旧キーの配列がある」で、値の中身では決めない。別名は set 時に trim し空なら nil に正規化する（"" と nil の 2 状態を作らない）。デコード不能な新キーは空扱いで読み、書き込みは上書きする（フィールドは optional でしか足さないため到達しない前提。RecentRepositoriesStore と同じ）
- 項目 2（不変条件）: 「1 パス 1 件」は BookmarkLibrary.add / replace が守る。replace は PathListDefaults.replace と同じく、新パスの既存エントリを落として置き換えた側（alias / folder 付き）を残す。単一 writer（CLI 転送）は不変
- 項目 3（消費経路）: bookmarkedURLs の読み手 3 つ（Pruner / QuickOpen / メニュー）は API 不変。表示名の消費側はメニューとパネルの 2 つで、どちらも BookmarkEntry.displayName（alias ?? lastPathComponent）を通す。PathListDefaults の doc に残る BookmarkStore の記述を直す。開く経路は DocumentOpener.openViewer（唯一の入口）に揃えるため HostedPanelPresenter に openHandler を必須引数で渡す
- 項目 4（新しい状態の表示）: パネルの空状態文言を用意。別名 alert のキャンセルは無変更、空入力は別名解除
- 項目 5（順序）: 移行は BookmarkStore.init に閉じる（AppStores のプロパティ初期化時、CLI では static let の初回アクセス時）
- 項目 6（高頻度経路）: isBookmarked は validateMenuItem / ツールバー再同期から呼ばれるため、JSON を毎回デコードしない。BookmarkStore がデコード済み BookmarkLibrary をメモリに持ち、自分の書き込みで更新する。前提は「同一プロセスの writer はこのインスタンスだけ」（AppStores が 1 個、CLI は GUI 起動中は転送）で、doc に明記する
- 項目 7（測るもの）: 移行テストは defaults のキーを直接見る。alias 保持は noteRenamed 後の library() で測る
- 項目 8（非同期）: 536.1 に非同期の表示差し替えは無い（D&D は 536.3）
- 項目 9（粒度）: BookmarkManagerModel(store:open:) と HostedPanelPresenter(stores:windowManager:openHandler:) は既定値なし。パネル生成は HostedPanelPresenter.makeController の 1 箇所
- 項目 10（行数・責務）: BookmarkStore 59 行 → 約 130、BookmarkLibrary 新設 約 120、MainMenuBuilder 436 → 約 450（例外上限を実測値へ更新）、HostedPanelPresenter 約 90 → 約 110、BookmarkManagerModel / View 新設。BookmarkManagerModel の注入クロージャは open の 1 つ（削除時の onChange は 536.2 で足す）
- 紹介サイトの shortcuts.test.ts と Help の MenuShortcutCatalog はキー等価の無い項目を拾わない（parseCallChunk が null / filter で除外）ため、「Edit Bookmarks…」の追加でどちらも変わらない
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-09-12）

採った形: 値型 BookmarkLibrary（BefoldKit、名前列で階層・Codable 合成）に純粋操作を置き、BookmarkStore は「読む → 1 操作 → 書く」の薄層にした。新キー Bookmarks（JSON Data）。旧キー BookmarkedPaths は init で一度だけ移行し、移行の有無にかかわらず defer で削除する。isBookmarked が validateMenuItem / ツールバー再同期から高頻度で呼ばれるため、デコード済みの値をメモリに持つ（前提「同一プロセスの writer はこのインスタンスだけ」を doc に明記）。

管理パネルは HostedPanel.bookmarks（HostedPanelPresenter が生成、520×420）。Bookmarks メニュー固定部に「Edit Bookmarks…」（キー等価なし）。パネルからファイルを開く経路は HostedPanelPresenter が openHandler（DocumentOpener.openViewer）を必須引数で受ける。別名の入力は .alert + TextField。行に stat はしない。

スキーマの移行は起票時の想定（536.4）から 536.1 へ移した（2 度移行しないため）。536.4 の AC を書き換え済み。

単純化の検討: PathListDefaults を拡張して別名を持たせる案は、Session / Recent が使う共通プリミティブに 1 消費者だけの関心が入るため採らず、RecentRepositoriesStore と同じ Codable 単一キーにした。再帰的な木ではなく名前列にしたのは、Codable の手書きと木の探索を避けるため。

検証（実測）:
- swift test --skip Integration --skip FileWatcherTests: 1907 tests / 310 suites 通過（新規: BookmarkLibraryTests 10、BookmarkStoreMigrationTests 3、BookmarkStoreTests +2、BookmarksMenuControllerTests +2）
- 修正を戻すと落ちることを確認: 移行を無効化 → 移行テスト 2 件が失敗、replace で別名を落とす → 3 件が失敗（復元済み）
- swiftlint ベースライン差分: main 48 / HEAD 48、真の新規 0・解消 0（HostedPanelPresenter.makeController の function_body_length 56 行が一度出たため、設定・ブックマークの生成を専用ビルダーへ出して解消）
- swiftformat（全ターゲット --lint）: 0 files require formatting
- xcodebuild build -scheme befold: BUILD SUCCEEDED
- 型グループ: MainMenuBuilder 436 → 449 行（例外上限を実測値へ更新）。BookmarkStore 118 / BookmarkLibrary 117 / BookmarkManagerView 83 / BookmarkManagerModel 35
- l10n-check: 追加 7 キーとも en/ja 揃い
- 実機（Debug ビルド、実 defaults）: 起動で旧キーの 1 件が新キーへ移行され旧キーが消えた。Bookmarks メニューは [Bookmark, Edit Bookmarks…, ―, 一覧, ―, Remove Missing Bookmarks…]。パネルで右クリック → Rename… → 「Weekly demo」を保存すると、メニューの左列が「Weekly demo」・右列のパスは従来どおりになった（スクリーンショット .tmp/bookmark-panel-5.png）。検証後に解除して元の状態へ戻した
- docs/dev/native-app-design.md に BookmarkStore / BookmarkLibrary / BookmarksMenuController / HostedPanelPresenter / BookmarkManagerModel の行を追加し、MainMenuBuilder の行を更新

responsibility-reviewer: must-fix 0、Low 2（表示順の規則が 2 箇所 / addFileItems の並列配列の件数保証が doc だけ）。どちらも同一タスク内で対応: BookmarkLibrary.entriesSortedByDisplayName に順序を一本化し、addFileItems に precondition を置いた。対応後も swift test 1907 件通過・swiftlint 新規 0。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ブックマークの永続化を値型 BookmarkLibrary（別名・所属フォルダー・展開状態を持つ JSON、UserDefaults キー Bookmarks）へ移し、旧キー BookmarkedPaths からの一度きり移行（3 ケースのテスト付き、旧キーは必ず削除）を入れた。BookmarkStore は「読む → 1 操作 → 書く」の薄層で、既存 API と CLI --bookmark の経路は不変。Bookmarks メニューは別名で表示し、固定部に「Edit Bookmarks…」を足して管理パネル（HostedPanel.bookmarks、右クリック → Rename… の alert で別名を設定、ダブルクリックで開く）を新設した。検証: swift test 1907 件通過、修正を戻すと 5 テストが落ちることを実測、swiftlint ベースライン差分 0、xcodebuild 成功、実 defaults での移行と別名設定を GUI で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
