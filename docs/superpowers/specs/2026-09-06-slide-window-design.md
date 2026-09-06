# スライドモードを専用ウィンドウへ移す

<!-- supersedes ./2026-09-04-sidebar-slide-mode-design.md -->
<!-- constrained-by ../../adr/0002-presentation-state-and-capabilities.md -->

> **これは 2026-09-06 時点の設計スナップショットです。**
> 現在の仕様は [`docs/dev/native-app-design.md`](../../dev/native-app-design.md)
> が単一の情報源。この文書は当時の意図と検討経緯を残すためのもので、
> 現在の実装と食い違っていることがある。着手前に必ずコードで裏を取ること。

## 目的

TASK-585 / 587 で入れたスライドモードは、**今の窓のサイドバーを 54pt に細めて
行をマスクする**形だった。プレゼン中に映すものとしてはサイドバー自体が不要で、
細めた列を残す設計はマスクの穴（TASK-588 のツールチップ漏れ、TASK-589 の
再描画）を生み続ける。

置き換え後の形は次のとおり。

- サイドバーのコンテキストメニューで「スライドモードで開く」を選ぶと、
  **サイドバーの無い新しいウィンドウ**（以下、スライド窓）がそのファイルで開く
- スライド窓では Space / ↓ で次のファイル、Backspace / Shift+Space / ↑ で
  前のファイルへ移る
- サイドバーを開くショートカット（⌘S）と、サイドバーへフォーカスを移す
  ⌘← はスライド窓では効かない
- ソース表示・差分表示（⌘1 / ⌘2 / ⌘3、⌘U、⌘\）は従来どおり使える
- 旧スライドモード（幅の固定・行のマスク・View メニューの切替・ヘッダーの
  解除アイコン）は撤去する

## 決めたこと（2026-09-05 のヒアリング）

| 論点 | 決定 |
| --- | --- |
| 旧スライドモード | 廃止して置き換える。TASK-588 / 589 は対象が消えるので見送り |
| 「次のファイル」の並び | 開いた時点の元サイドバーの表示順（並び順・不可視・変更のみ・ツリーの展開状態）を引き継ぐ。フォルダー行は飛ばす。ファイルの追加・削除は監視で追随 |
| 長い本文 | キーは前後移動専用。本文のスクロールはトラックパッド・マウスホイールのみ |
| 窓の性質 | タブに合流させない。ツールバーを出さない。セッション復元の対象外。フルスクリーンにはしない |
| 入口 | サイドバーのコンテキストメニューだけ（View メニュー・CLI には置かない） |
| 端の挙動 | 最後で「次へ」、最初で「前へ」は何もしない（周回しない） |
| 退出 | 窓を閉じるだけ（⌘W / 赤ボタン）。専用キーは設けない |

## 案の比較

**案 A（採用）: 既存のビューア窓に窓種別を足す。** `ViewerWindowController` に
生成時に `kind`（`.viewer` / `.slide`）を渡し、`.slide` のときはアセンブラが
ツールバー無し・サイドバー折りたたみ固定・タブ合流なしで組む。`FileListModel`
は隠れたまま持ち続けるので、前後移動は既存の `FileListSnapshot.next(after:)` /
`previous(before:)` で辿れる。表示モード・ファイル監視・履歴・タイトル更新・
per-file の表示メモリは既存経路がそのまま効く。

**案 B（不採用）: 専用の `SlideWindowController` を新設する。** 分割ビューを
持たない独立した窓型。隔離は綺麗だが、`ViewerDocumentPresenter` の配線・
メニュー検証・表示モード・per-file メモリを二重に持つ。
`ViewerWindowManager+OpenViewer.swift` の `makeController` は生成時オプションを
10 個持ち、その大半を再実装することになる。

**案 C（不採用）: 折りたたみ窓に lock の Bool を足す。** 「開かせない」だけなら
足りるが、「ツールバー無し・タブ合流なし・復元対象外」も同じ Bool で判定する
ことになり、フラグの意味が膨らむ。種別の列挙にしておけば同じコストで名前が付く。

## 設計

### 入口: コンテキストメニュー

`SidebarContextMenu` の `openElsewhereEntries` 表に「スライドモードで開く」を
1 行足す。dispatch は既存の `fileListDidRequestOpenElsewhere(_:disposition:)`
1 本のままで、`OpenDisposition` に `.slide` を足す。delegate メソッドは増やさない。

フォルダー行では「新しいウィンドウで開く」と同じく `DirectoryLister.firstSupportedFile`
で最初の対応ファイルを開き、無ければ項目を無効にする。

l10n キーは既存の `sidebar.context.openInNewWindow` の隣に
`sidebar.context.openInSlideMode`（en / ja）を置く。旧キー `menu.view.slideMode` と
`sidebar.slideMode.exit` は撤去する。

### 窓の組み立て

`openViewer(for:options:disposition:)` は `.slide` を常に新規窓として扱う
（`.newWindow` と同じ再利用規則）。`makeController` に `kind: .slide` を渡し、
アセンブラは次を変える。

- `ViewerWindowChrome`: `tabbingMode = .disallowed`、ツールバーを付けない
- `initialSidebarCollapsed = true`。**この折りたたみは `SidebarStateStore.recordToggle`
  に書かない**（ADR 0002: ライブ値は窓ごと、保存値は次に開く窓の出発点。
  スライド窓の折りたたみは種別の帰結であって利用者の選択ではない）
- 一覧の初期値は元の窓から引き継ぐ。「新しいウィンドウで開く」が使う
  `SidebarListingSeed` は directory / listing / sortOrder / showHiddenFiles の 4 つ
  しか運ばない（`SidebarListingSeed.swift` で確認）。「開いた時点の表示順」には
  ツリー／フラットのレイアウト・「変更のみ」・ツリーの展開状態も要るので、
  seed にこの 3 つを足し、`canApply(to:)` の一致条件も同じだけ広げる。
  この拡張は「新しいウィンドウで開く」にも同じ引き継ぎをもたらす（意図した副作用。
  別窓で開いたときに展開状態が消える現状より自然になる）

### サイドバーを開かせない

3 箇所で止める。1 箇所でも漏れると「サイドバーの無い窓」が崩れるので、
種別 `.slide` の窓で ⌘S / ⌘← / ツールバー経由のどれを試しても
`sidebarItem.isCollapsed` が変わらないことをテストで固定する。

- `ViewerMenuValidator`: ⌘S（`toggleSidebar`）と ⌘←（`focusSidebar`）を
  `.slide` では無効にする
- `ViewerSplitViewController.toggleSidebar(_:)`: `.slide` では何もしない
  （メニュー検証を迂回する経路への保険）
- ツールバーが無いので `.system(.toggleSidebar)` は存在しない

### 前後移動キー

スライド窓にだけ `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` を付ける
（前例: `SwipeHistoryMonitor` の scrollWheel）。窓の `isKeyWindow` を見て自窓の
イベントだけを扱い、窓が閉じたら外す。

| キー | 動作 |
| --- | --- |
| Space、↓ | 次のファイル |
| Backspace（delete）、Shift+Space、↑ | 前のファイル |

- ⌘ / ⌥ / ⌃ が付いたイベントは素通しする（メニューのキー等価が勝つ）
- first responder がテキスト入力（`NSTextView` / `NSTextField`。検索欄など）なら
  素通しする
- 隣の解決は `model.listSnapshot` を **キー 1 回につき 1 度だけ読み**
  （`listSnapshot` は読むたびに再計算する。TASK-418）、`next(after:)` /
  `previous(before:)` を `kind == .file` の行に当たるまで繰り返す。行き先が
  無ければ何もしない
- ファイルを開く経路は通常窓と同じ `ViewerWindowController+FileNavigation` を通す
  （履歴・タイトル・per-file メモリが従来どおり効く）
- JS 側の `spaceScroll` フィーチャと `viewer-src/keyboard.ts` の矢印スクロールは
  触らない。モニタが先に消費するので本文には届かない

### セッション復元

`SessionRestorer` / `ViewerTabGrouping.tabGroup(of:)` のスナップショットから
`.slide` の窓を除外する。`SessionLayout` には種別を足さない（復元しないので
記録しない）。

### 旧モードの撤去

- `SlideModeCoordinator`、`SidebarSlideMetrics`、`SidebarTransientState.isSlideMode`
  と `setSlideMode(_:)`
- `ViewerSplitViewController.setSlideMode(_:)` と `thicknessBeforeSlideMode`、
  `setAutosaveEnabled(_:)`、`SidebarCollapsible.setSlideMode`
- `FileListView` の `.redacted(reason:)`、`SidebarHeaderView` の解除アイコン分岐
- `MainMenuBuilder+ViewMenu.swift` の項目、`ViewerWindowController.toggleSlideMode(_:)`
  と `isSlideMode`、`ViewerMenuValidator` の該当分岐
- `ViewerWindowAssembler.makeSidebarDidHide` のスライド解除呼び出し
- `SidebarDisplayRequest.slideMode`（`.display` だけになるなら列挙ごと畳む）
- xcstrings の 2 キー、`native-app-design.md` の 4 行

TASK-590〜592 は `.slideMode` を前提にした記述を持つので、撤去後に
Description / AC を書き換える。

## 未確認の前提

- **WKWebView がフォーカスを持つ状態でローカルモニタが keyDown を先取りできるか**は
  未実測。`addLocalMonitorForEvents` は `sendEvent` の前に呼ばれるので
  first responder に依らないはずだが、前後移動のサブタスクの最初に実機で確かめる。
  取れない場合は `NSWindow` のサブクラスで `sendEvent(_:)` を上書きする形へ切り替える
- **ツリーの展開状態を `FileListModel` がどの形で持っているか**（`SidebarDisclosureResolver`
  の入力）は未確認。seed へ足す型はサブタスク 2 の着手時に決める

## テスト

- `OpenDisposition.slide` がコンテキストメニューの表から delegate へ届く（既存の
  `openElsewhereEntries` のテストへ 1 行）
- `.slide` の窓で ⌘S / ⌘← / `toggleSidebar` が `isCollapsed` を変えない
- `.slide` の窓が `SidebarStateStore` に書かない
- 隣の解決: フォルダー行を飛ばす、端で nil、絞り込み・不可視・変更のみを反映する
  （`FileListSnapshot` を直接組む純粋テスト）
- キー表: Space / ↓ → 次、Backspace / Shift+Space / ↑ → 前、修飾キー付きは素通し、
  テキスト入力中は素通し（`SidebarKeyAction` と同じ純粋な表にして測る）
- セッションのスナップショットに `.slide` の窓が入らない
- 撤去: 旧シンボルが `rg` で 0 件、`/l10n-check` が通る

GUI 層（実際の窓・ツールバーの有無・タブ合流）は自動テスト対象外なので、
`/run` で起動して目視する。

## backlog の分割

親 1 件 + サブタスク 3 件。着手順は依存で表す。

1. 旧サイドバー内スライドモードを撤去する（TASK-588 / 589 を見送りで閉じ、
   TASK-590〜592 の記述を直す）
2. 窓種別 `.slide` と「スライドモードで開く」を追加する（1 に依存）
3. スライド窓の前後移動キーを実装する（2 に依存）

各サブタスクは着手前に `/review-design` を回す。
