---
id: TASK-475
title: サイドバーの `..` 行を廃止し、ヘッダーのフォルダー名をパスポップアップにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-13 11:55'
updated_date: '2026-08-13 12:52'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 696000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバー上部が「基準ディレクトリ行 / フォルダー名＋トグル行 / 一覧先頭の `..` 行」の実質 3 段になっており、上位フォルダーへの移動だけで 1 行を占有している。`..` 行を両表示モード（ツリー / ドリルダウン）から廃止し、ヘッダーのフォルダー名（現在は `SidebarHeaderView` の静的な `Text(...).font(.headline)`）自体をクリック可能なパスポップアップにして 2 段へ畳む。

メニューには現在フォルダーから上位の祖先をホームまで並べ、選んだ階層へ移動する。「1 つ上」だけでなく多階層の移動も 1 操作で済む（Finder のウィンドウタイトル ⌘クリックと同じモデル）。ダブルクリックにも「1 つ上へ移動」を割り当て、マウスだけの利用者が手掛かりなしに戻れなくなる状態を作らない。

検討時に採らなかった案: (B) 名前の左に「上へ」ボタンを増やす案は、左群が「一覧の形（表示形式トグル）」の系統だと決めてある並び規約（`SidebarHeaderView` のコメント）を崩すため見送り。(C) ダブルクリックのみの案は、静的ラベルに手掛かりが一切なく発見できないため単独では不可。

移動範囲の制約を落とさないこと: 現状の `..` は `DirectoryLister.parentNavigationEntry(for:home:)` がホーム外で nil を返すことで「ホームより上へは出ない」を担保している。ヘッダー側へ移す際にこの上限を引き継がないと、ホーム外へ出られてしまう。

キーボードの ⌘↑（`SidebarKeyAction` の `.navigateToParent`）は既にあるため変更しない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバー一覧の先頭に `..` 行が出ない（ツリー表示・ドリルダウン表示のいずれでも）
- [x] #2 ヘッダーのフォルダー名をクリックすると、現在フォルダーから上位の祖先をホームまで並べたメニューが開き、選んだ階層へ移動する
- [x] #3 フォルダー名が押せることが視覚的に分かる（ホバー時の反応と、押下可能を示す指示子）
- [x] #4 ホーム直下ではホームより上の階層がメニューに現れず、押しても移動しない（メニュー自体を出さない）
- [x] #5 メニュー項目の組み立ては引数でフォルダーとホームを受け取る純粋関数へ切り出し、ホーム直下・深い階層・ホーム外の各ケースをユニットテストで押さえる
- [x] #6 `FileListEntry.Kind.parentNavigation` とその分岐（`SidebarRowBuilder.rows` の `parentEntry`、`FileListEntryRow`、`FileListModel+Snapshot`、`SidebarKeyAction`）が削除され、行の種類が 1 つ減っている
- [x] #7 ⌘↑ による親フォルダーへの移動は従来どおり動作し、行き先は上記の純粋関数から決まる
- [x] #8 プレビュー内フォルダー一覧（FolderListingView）からも `..` 行が消えている
- [x] #9 実装着手前に `/review-design` を 1 回実施し、結果を Implementation Plan へ反映している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 前提と裏付け

- (コード参照) `..` 行の供給は 1 本: `DirectoryLister.buildListing`(DirectoryLister.swift:101) →
  `DirectoryListing.parentEntry`(DirectoryListing.swift:11) → `SidebarRowBuilder.rows`(:71) が先頭へ append。
  ツリー / ドリルダウンは同じ `rows()` を通る(TASK-442.1 で単一化済み)ため、供給側で止めれば AC#1 は 1 箇所で満たす。
- (コード参照) ホーム上限の実体は `DirectoryLister.isWithinHome`(:187-191、normalizedPathKey の前方一致)。
  `SidebarNavigator.navigateToFolder`(SidebarNavigator+FolderNavigation.swift:18) も同じ関数でガードしており、
  `..` 廃止後もこちらは残る = 移動の上限は二重に担保される。
- (コード参照) ⌘↑ は現在 `FileListView+Keyboard.navigateToParent`(:107-115) が `snapshot.parentNavigationEntry`
  から行き先を取る。`..` を消すと `.ignored` になるため、行き先の源を差し替えないと AC#8 が破れる。
- (実測) 型グループ行数 `scripts/check-type-group-size.sh`:
  SidebarHeaderView 121 / FileListView 283 / DirectoryLister 226 / SidebarRowBuilder 161 / FileListSnapshot 110。
  本変更は DirectoryLister・SidebarRowBuilder・FileListSnapshot が減り、SidebarHeaderView が +40 程度。新規型 1 つ。
- (ユーザー判断) プレビュー内フォルダー一覧(FolderListingView)の `..` も同時に廃止する。上移動は ⌘↑ と
  サイドバーのパスポップアップに一本化する。

## 手順

1. 祖先の純粋関数を新設する(AC#6)。`BefoldApp/befold/Viewer/SidebarPathMenu.swift`
   - `static func ancestors(of directory: URL, home: URL) -> [URL]`(近い親から順、ホームまで。ホーム直下では空)
   - `static func parent(of directory: URL, home: URL) -> URL?` は **`ancestors(of:home:).first` として実装する**。
     ⌘↑・ダブルクリック・メニューが同じ上限判定を共有し、片方だけ直る形を作らない(チェック項目3の兄弟判断)。
   - 上限判定は `DirectoryLister.isWithinHome` を使い、この型の外にホーム判定を書かない(チェック項目1・9)。
   - ユニットテスト `SidebarPathMenuTests`: ホーム直下 / 深い階層 / ホーム外 / ホーム自身。

2. `..` 行の供給を止め、`FileListEntry.Kind.parentNavigation` を削除する(AC#1・#7)。
   - `DirectoryLister.parentNavigationEntry(for:home:)` を削除。`buildListing` / `listing(in:...)` の `home` 引数も
     不要になるので落とす(`isWithinHome` と `defaultHome` は移動ガードで使うため残す)。
   - `DirectoryListing.parentEntry` と `SidebarRowBuilder.rows(parentEntry:)` 引数・先頭 append を削除。
   - case を見ている消費側を全列挙して落とす(チェック項目3):
     FileListEntryRow.swift:82-93 / FileListSnapshot.swift:33,107-109 / FileListFilter.swift:41 /
     SidebarKeyAction.swift:108-113 / SidebarContextMenu.swift:18 / SidebarSelectionMemory.swift:32 /
     FileListView.swift:69 / FolderListingView.swift:162,204。
     空状態判定は `entries.isEmpty` へ(空配列の `allSatisfy` は true なので従来挙動と一致)。
   - コメントの列挙も同時に直す: FileListEntry.swift:30 / DirectoryListing.swift:6 /
     FileListModel+Snapshot.swift:12,44 / FileListEntryIndex.swift:22(重複 pathKey の例) /
     SidebarRowAssemblySingleSourceTests の走査対象。

3. ⌘↑ / delete の行き先を差し替える(AC#8)。
   - `FileListView+Keyboard.navigateToParent` を `SidebarPathMenu.parent(of: model.currentDirectory, home:)` へ。
   - `SidebarKeyAction` 側のキー割り当ては変更しない(`forward` の `.parentNavigation` case のみ削除)。

4. ヘッダーのフォルダー名をパスポップアップにする(AC#2・#3・#5)。
   - `SidebarHeaderView.navigationHeader` の `Text(...)` を `Menu`(プルダウン)へ。ラベルはフォルダー名 +
     押下可能を示す chevron。項目は `SidebarPathMenu.ancestors` を map し、選択で移動を起こす。
   - **祖先配列は Menu の content クロージャ内で作る**(body 毎の再構築とホーム解決を避ける = チェック項目6)。
   - **祖先が空(ホーム直下)のときは Menu を出さず従来の素の Text に落とす**。空メニューが開く状態を作らない
     (チェック項目4)。指示子も出ないので「押せない」ことが見た目と一致する。
   - 移動の呼び出しは **新しいクロージャを増やさず `FileListViewDelegate.fileListDidRequestNavigation(to:)` を通す**。
     SidebarHeaderView は既に 4 つのクロージャを受けており、5 つ目は責務規定(注入クロージャ 3 超)に抵触する。
     既存の絞り込み点を通すことで ⌘↑ と移動経路も 1 本になる(チェック項目3・10)。
   - 左群(一覧の形)/右群(絞り込み)の並び規約は崩さない。フォルダー名は従来と同じ中央位置のまま。

5. テストを更新する。Explore が列挙した影響先(DirectoryListerTests / DirectoryListerFlatRowsTests /
   SidebarRowBuilderTests / SidebarKeyActionTests / FileListViewTests / SidebarParentRowSelectionTests /
   FileListModelFilterTests / FileListModelTreeFilterTests / SidebarTreeFilterTests /
   FolderListingViewFilterTests / PreviewTargetResolverTests / FileListModelLookupTests /
   SidebarRowAssemblySingleSourceTests ほか `parentEntry: nil` を渡すだけの多数)。

6. 新規ファイル追加のため `xcodegen generate` を実行し、swiftformat / swiftlint のベースライン差分ゼロを確認する。

## 実装前に確定させた設計判断(担保付き)

- ホーム上限の真実の源は `SidebarPathMenu` 1 つ。`parent` は `ancestors.first`。→ `SidebarPathMenuTests` が
  「ホーム直下で ancestors が空かつ parent が nil」を同時に押さえる(片方だけ直ると落ちる)。
- 移動の入口は `fileListDidRequestNavigation(to:)` の 1 本。→ ヘッダーに移動用クロージャを新設しないことで
  構造的に守る。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
設計レビュー(/review-design)実施済み。判断 2 件をユーザー確認のうえ確定。
(1) FolderListingView(プレビュー内フォルダー一覧)も同じ供給経路(DirectoryListing.rows)のため `..` を同時に廃止する。上移動は ⌘↑ とヘッダーのパスポップアップへ一本化。
(2) 単クリックでメニューを開く仕様(AC#2)とフォルダー名のダブルクリックによる 1 つ上へ移動は併存できない(Menu はマウスダウンでイベントトラッキングを奪うため 2 打目がラベルへ届かない。未実測・GUI 層は自動テスト対象外)。単クリックのメニューを採り、旧 AC#4(ダブルクリック)は取り下げた。メニュー先頭が「1 つ上」にあたるため、マウスのみでも 2 アクションで戻れる。

検証(すべて実機 Debug ビルド + System Events による AX 実測、2026-08-13):
- AC#1 ドリルダウン/ツリーとも一覧に `..` 行なし(outline の行は対象ファイル・フォルダーのみ)。
- AC#2 ヘッダーのフォルダー名が AX 上 "menu button" として公開され、メニュー項目は近い親から順に [befold-475-probe, tokutomi(ホーム)]。ホームより上(/Users)は出ない。項目クリックでその階層へ移動した。
- AC#4 ホームへ移動するとフォルダー名は "static text" のみになり menu button ではなくなる(メニューが開かない)。
- AC#7 ⌘↑ でヘッダーが sub → befold-475-probe に変わり、一覧が親フォルダーの内容になった。
- AC#8 プレビュー内フォルダー一覧の行は diagram.mmd / note.md のみで `..` なし。
- AC#5 SidebarPathMenuTests 6 件。ホーム上限のガードを外すと 5 件が落ちてルート `/` まで登ることを確認済み(テストが空振りしていないことの確認)。
- 全体: swift test 1398 件パス、xcodebuild BUILD SUCCEEDED、swiftlint は main とのベースライン差分ゼロ。

未実測: AC#3 のうち「ホバー時の反応」は AX では測れず未確認(押下可能を示す chevron の存在と menu button 化は実測済み)。ホバー時の背景ハイライトは SidebarPathMenuButton の .onHover で実装しており、目視確認はリリース前の手動チェックに委ねる。

副次的な変更: FileListViewTests が type_body_length(250 行)を超えたため、修飾キー付きキー操作のテストを FileListViewNavigationKeyTests へ分割した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバー一覧の `..` 行(FileListEntry.Kind.parentNavigation)を廃止し、ヘッダーのフォルダー名を上位祖先のパスポップアップに置き換えた。ホーム上限の判定は新設した純粋関数 SidebarPathMenu(parent は ancestors.first)に集約し、⌘↑ / delete も同じ関数から行き先を取るため、メニューとキー操作が別々の上限判定を持つ形は構造的に作れない。供給元が 1 本だったためプレビュー内フォルダー一覧の `..` も同時に消えた(ユーザー確認済み)。検証は SidebarPathMenuTests 6 件(ガードを外すと 5 件が落ちることまで確認)、swift test 1398 件パス、xcodebuild BUILD SUCCEEDED、swiftlint は main とのベースライン差分ゼロ、および実機 Debug ビルドの AX 実測(メニュー項目の並び・ホームでの非表示・⌘↑ の移動・プレビュー内一覧)。
<!-- SECTION:FINAL_SUMMARY:END -->
