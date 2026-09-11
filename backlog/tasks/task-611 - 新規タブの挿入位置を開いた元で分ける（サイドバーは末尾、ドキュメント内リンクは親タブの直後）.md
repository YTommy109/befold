---
id: TASK-611
title: 新規タブの挿入位置を開いた元で分ける（サイドバーは末尾、ドキュメント内リンクは親タブの直後）
status: To Do
assignee: []
created_date: '2026-09-11 07:45'
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
- [ ] #1 サイドバー由来（行クリック・キー操作・右クリックメニュー）で開いたタブが、既存タブの枚数と選択中のタブに関係なくタブバーの末尾に入る
- [ ] #2 ビューア内ドキュメントのリンク由来（`BridgeMessageRouter` / `DirectHTMLLinkPolicy`）で開いたタブが、クリック元タブの直後に入る
- [ ] #3 挿入位置の指定が `ViewerTabGrouping` の必須引数になっており、新しい呼び出し元がデフォルト引数に黙って乗れない
- [ ] #4 `addTabbedWindow(_:ordered:)` の `.above` が実際にどの位置へ入るかを実機で実測し、結果を Implementation Notes に記録する
- [ ] #5 セッション復元後のタブの並びが保存時の並びと一致する
- [ ] #6 タブの並び順を固定するユニットテストがある（現状 `ViewerWindowManagerTabTests` / `ViewerTabGroupingTests` に順序を見る assert は 1 件も無い）
<!-- AC:END -->
