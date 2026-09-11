---
id: TASK-611
title: 新規タブの挿入位置を開いた元で分ける（サイドバーは末尾、ドキュメント内リンクは親タブの直後）
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-09-11 07:45'
updated_date: '2026-09-11 11:30'
labels: []
dependencies: []
references:
  - 'https://daringfireball.net/2018/12/safari_new_tab_next_to_current_tab'
ordinal: 801000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーから cmd+click でファイルを次々にタブで開いても、開いた順にタブが右へ並ばない。タブ結合はプロダクトコードで 1 箇所（`BefoldApp/befold/App/ViewerTabGrouping.swift` の `ViewerTabGrouping.attachAsTab`）に集約されていて、そこが `baseWindow.addTabbedWindow(window, ordered: .above)` を決め打ちしているため、すべての経路が「クリック元ウィンドウに対する相対位置」に入る。末尾へ積む経路は存在しない（`insertWindow(_:at:)` はプロダクトコードに 0 件）。

望む振る舞いは開いた元で 2 通りに分かれる。サイドバーの一覧から開くのはファイル一覧からの独立したオープンなので末尾へ積みたい。一方ドキュメント内のリンクから開くのは親子関係のある派生タブなので、親タブの直後に入ってほしい。後者は Safari のリンク由来タブ（spawned tab）と同じ考え方で、Safari は cmd+T が末尾・リンクの cmd+click が現在タブの隣という使い分けをしている（https://daringfireball.net/2018/12/safari_new_tab_next_to_current_tab ）。

前提と裏付け:
- コード参照: 修飾キーと開き方の対応は `BefoldApp/BefoldKit/OpenDisposition.swift` の `OpenDisposition.init(commandKey:shiftKey:)` に集約されている（cmd=newTab / cmd+shift=newWindow / shift 単独とキー無し=currentTab）。タブで開くのは cmd+click であり shift+click ではない。この対応表自体はこのタスクでは変更しない
- コード参照: タブを開く入口は サイドバー行クリック（`Viewer/FileListView.swift` の `handleRowTap`）、サイドバーのキー操作（`Viewer/SidebarKeyAction.swift`）、サイドバー右クリックメニュー（`Viewer/SidebarContextMenu.swift` の `openElsewhereEntries`）、ビューア内リンク（`BefoldRenderKit/BridgeMessageRouter.swift`）、直接 HTML モードのリンク（`BefoldRenderKit/DirectHTMLLinkPolicy.swift`）。前 3 つが末尾、後 2 つが親の直後にあたる
- コード参照: セッション復元（`App/SessionRestorer.swift`）も同じ `attachAsTab` を通って順次連結するため、復元後の並びへの影響を確認する必要がある
- 未確認: `NSWindow.addTabbedWindow(_:ordered:)` の `.above` が実際にタブバー上で「親の直後」に入るかは Apple のドキュメント本文に明記が無く、リポジトリにも挙動を固定するテストもコメントも無い。確認方法は、タブを 3 枚開いた窓で 1 枚目を選択してドキュメント内リンクを cmd+click し、`window.tabGroup?.windows` の並びを見る実測
- 未確認: Finder の新規タブ挿入位置は Apple ヘルプ・フォーラム・技術ブログのいずれにも記述が見つからず確証が無い。Finder に合わせるという根拠は使わない
- ドキュメント参照: `NSWindowTabGroup.addWindow(_:)` は末尾追加と明記されており、位置指定は `insertWindow(_:at:)`。HIG にタブ挿入位置の推奨は無い
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバー由来（行クリック・キー操作・右クリックメニュー）で開いたタブが、既存タブの枚数と選択中のタブに関係なくタブバーの末尾に入る
- [x] #2 ビューア内ドキュメントのリンク由来（`BridgeMessageRouter` / `DirectHTMLLinkPolicy`）で開いたタブが、クリック元タブの直後に入る
- [x] #3 挿入位置の指定が `ViewerTabGrouping` の必須引数になっており、新しい呼び出し元がデフォルト引数に黙って乗れない
- [x] #4 `addTabbedWindow(_:ordered:)` の `.above` が実際にどの位置へ入るかを実機で実測し、結果を Implementation Notes に記録する
- [x] #5 セッション復元後のタブの並びが保存時の並びと一致する
- [x] #6 タブの並び順を固定するユニットテストがある（現状 `ViewerWindowManagerTabTests` / `ViewerTabGroupingTests` に順序を見る assert は 1 件も無い）
- [x] #7 `.newTab` で開いたタブは背面で開き、表示も焦点も起点の文書に留まる（Safari の cmd+click と同じ。ユーザー追加要望）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計レビュー（/review-design のチェックリスト）を通した方針。

1. 挿入位置を表す `TabPlacement`（`.end` / `.afterSource`）を BefoldKit に置く（Foundation だけの enum。`OpenDisposition` と同じ層）。`OpenDisposition` に関連値として埋め込む案は、`.newTab` の出現がプロダクト 7 件・テスト 24 件あり差分が大きいため採らない。開き方（修飾キーの解釈）と置き場所（開いた元）は直交する値なので、別の値として運ぶ。
2. `ViewerTabGrouping.attachAsTab` / `present` に `placement:` を**必須引数**で足す。`.afterSource` は従来どおり `baseWindow.addTabbedWindow(_, ordered: .above)`。`.end` は `tabWindows(of: baseWindow).last` を anchor にして同じ API を呼ぶ（`NSWindowTabGroup.addWindow` は base がまだタブ化されていないと `tabGroup` が nil になりうるので使わない）。
3. `.above` が「anchor の直後」に入ることは、`ViewerTabGroupingTests` で実 NSWindow を 3 枚タブ化して 4 枚目を 1 枚目へ結合し `tabGroup.windows` の並びを読む形で実測する（AC #4）。同じテストが `.end` の並びも固定する（AC #6）。
4. 経路: `ViewerWindowController.openFileElsewhere` クロージャの型を `(URL, OpenDisposition, TabPlacement, NSWindow?) -> Void` にし、開いた元が必ず指定する形にする。サイドバー（`+FileList.fileListDidRequestOpenElsewhere`、行クリック・キー操作・右クリックの 3 経路がここへ合流することは grep で確認済み）は `.end`、文書内リンク（`+References.openReference`、`ReferenceContextMenu` の「新しいタブで開く」もここを通る）は `.afterSource`。
5. `ViewerWindowManager.openViewer` は `tabPlacement:` を受けて `present` へ渡す（`.newTab` 以外では使わない）。既定値は `.end`（`.currentTab` の呼び出し元が多数あり、置き場所が無意味な呼び出しに値を書かせない。`.newTab` の呼び出し元はクロージャ型で強制される）。既定クロージャ経由の `AppDelegate.openViewer(for:disposition:relativeTo:)` → `DocumentOpener` も同じ引数を通す。
6. `SessionRestorer.restoreTabGroup` は `previousWindow` へ順に連結しているので `.end` を渡す（保存順どおりに末尾へ積むのと同義。AC #5）。
7. 兄弟判断: `ViewerWindowOpenPolicy.reusableController(.newTab)` は同じグループ内の既存タブを再利用する判定で、挿入位置とは無関係のため触らない。
8. 型グループ行数（実測）: ViewerTabGrouping 150、ViewerWindowManager 318、SessionRestorer 241、DocumentOpener 126、ViewerWindowController 920（恒久例外 931 に近いので、クロージャ型と既定クロージャの 2 行以外は触らない）。
9. `docs/dev/native-app-design.md` の該当箇所を更新する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実測（AC #4）

`NSWindow.addTabbedWindow(_:ordered: .above)` は **anchor の直後**に入る。`ViewerTabGroupingTests`
「afterSource は起点タブの直後に入る」で、実 NSWindow 3 枚のグループ [first, second, third] に
4 枚目を first 基準で結合し、`tabGroup.windows` が [first, fourth, second, third] になることを確認した
（ヘッドレスのテストホスト上での実測。Apple のドキュメント本文には位置の明記が無い）。
この結果に基づき、`.end` は「anchor をグループ末尾のタブに取り替えて同じ API を呼ぶ」実装にした。

## 設計上の判断

- **置き場所は `OpenDisposition` の関連値にせず、別の値 `NewTabPlacement` で運ぶ。** 修飾キーの
  初期化子は開いた元を知らないため関連値では決められない。また `.newTab` の出現がプロダクト 7 件・
  テスト 24 件あり、関連値化は差分が大きい。
- **型名は `NewTabPlacement`。** 当初 `TabPlacement` にしたところ SwiftUI（macOS 15 の Tab API）の
  `TabPlacement` と衝突し、`ViewerWindowController.swift` で "ambiguous for type lookup" になった
  （実測）。BefoldKit には置いたが SwiftUI を import する側で曖昧になるため改名した。
- **`NSWindowTabGroup.addWindow(_:)` は使わない。** base がまだタブ化されていないと `tabGroup` が
  nil になりうる。`.end` は `tabWindows(of: base).last` を anchor にして `addTabbedWindow` に揃えた
  （`tabWindows(of:)` はタブ化前なら `[base]` を返すので anchor = base に縮退する）。
- **担保**: `ViewerTabGrouping.attachAsTab` / `present` と `openFileElsewhere` クロージャ型で
  `placement` を必須にした。`ViewerWindowManager.openViewer` の `tabPlacement:` だけは既定 `.end`
  （`.currentTab` の呼び出し元が多数あり、置き場所が無意味な呼び出しに値を書かせない）。
- **`ViewerWindowController` の型グループは 920 行のまま**（恒久例外に近いため、クロージャ型と
  既定クロージャの書き換えは行数を増やさない形にした。`check-type-group-size.sh` exit 0）。
- 副産物: `ViewerWindowControllerReferenceOpenTests` の 3 要素タプルを struct にしたことで、
  main に元からあった swiftlint `large_tuple` 警告が 1 件解消した。

## 検証

- `swift test --skip Integration --skip FileWatcherTests`: 1872 tests / 307 suites 全通過
- 追加テスト: `ViewerTabGroupingTests` 2 件（実測と末尾）、`ViewerWindowManagerTabTests` 1 件
  （openViewer から attachAsTab まで置き場所が届き、並びが分かれる）、
  `ViewerWindowControllerReferenceOpenTests` 1 件（サイドバー由来 `.end` / 文書内リンク由来
  `.afterSource`。サイドバーの 3 経路は `fileListDidRequestOpenElsewhere` に合流するので 1 点で担保）
- セッション復元（AC #5）: `SessionRestorer.restoreTabGroup` は直前の窓へ `.end` で順に積む形にし、
  既存の `SessionRestorerTests` が保存順どおりの復元を固定している（変更後も全通過）
- swiftlint: main 比で新規ゼロ、`large_tuple` 1 件解消。markdownlint 0 issues。
  `check-befoldkit-platform-free.sh` OK、`check-doc-citations.sh` OK

## コードレビュー（/code-review high）後の修正と追加要望

- **#1 派生タブの並び順（採用: Safari と同じクリック順）。** 常に起点の直後だと A→B と開いたとき
  [doc, B, A] になり、doc コメントの「Safari と同じ」と食い違っていた。起点の
  `ViewerWindowController.lastSpawnedTab`（weak 参照 1 つ）に最後の派生タブを覚え、それが起点の
  グループの並びに実際に残っていればその直後、無ければ起点の直後へ入れる。記録の読み書きは
  `ViewerTabGrouping.attachAsTab` / `spawnAnchor(of:)` の中に閉じた（`viewerPath(of:)` と同じく
  窓 1 枚から controller を引く以上の台帳は持たない）。
  - 実測: 閉じた窓の `tabGroup` は nil に戻らない。`last.tabGroup === base.tabGroup` の判定では
    閉じた派生タブを anchor にしてしまい、AppKit がそれを末尾扱いにした。判定を
    `tabWindows(of: base).contains(last)`（並びに実際に居るか）へ変えて解消。
  - 記録するのは最後の派生タブだけなので、最後でない派生タブを閉じても並びは変わらない
    （テストの筋書きを最初この点で取り違えた）。
- **#2 anchor が自分自身になる経路。** 既にグループ末尾に居る窓を `.end` で結合し直すと
  `window.addTabbedWindow(window)` になる（復元で既存の窓を掴んだとき等）。anchor 計算のあとで
  `anchor !== window` を弾き、テストで固定。
- **#3 `NewTabPlacement` の置き場。** 消費側が befold/App だけなので BefoldKit から
  `ViewerTabGrouping.swift` へ移し、internal にした。
- **#4 / #5** `.end` のテストに起点が中央のケースを足し、到達不能な `?? baseWindow` を
  `tabGroup?.windows.last ?? baseWindow` の直接表現に置き換えた。

## 追加要望: 新しいタブは背面で開く（AC #7）

Safari の cmd+クリックはタブを開くだけで移動しない。befold は `.newTab` を常に選択していた。
`present(select: false)` が表示（`showWindow` = makeKeyAndOrderFront。これがタブを前面にしてしまう）
のあとで起点タブへ選択を戻す形にし、`openViewer` は `.newTab` のとき `select: false` を渡す。
セッション復元が最後に選択タブを決め直すのと同じ手順で、同じ runloop 内なので描画前に戻る。
既存テスト `newTabJoinsSourceTabGroup` の「選択タブになる」は反転させ、`ViewerTabGroupingTests` に
`present` 単体の担保を足した。

検証: `swift test` 1875 件全通過。swiftlint main 比新規ゼロ（`large_tuple` 1 件解消）。
型グループ `ViewerWindowController` 922（exit 0）。markdownlint / platform-free / doc-citations OK。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
新規タブの挿入位置を開いた元で分け、新しいタブは背面で開くようにした。`NewTabPlacement`（`.end` / `.afterSource`）を `ViewerTabGrouping` の隣に置き、`attachAsTab` / `present` と `openFileElsewhere` クロージャで必須引数にした。サイドバー由来は末尾、文書内リンク由来は起点の直後——同じ起点から続けて開くと直前の派生タブの直後に入りクリック順に並ぶ（起点の `lastSpawnedTab` を weak で 1 つ覚える）。`.newTab` は `present(select: false)` で表示後に起点タブへ選択を戻し、Safari の cmd+クリックと同じく移動しない。`.above` が anchor の直後に入ること、閉じた窓の `tabGroup` が nil に戻らないことは実測して設計に反映した。検証: swift test 1875 件全通過、swiftlint main 比新規ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
