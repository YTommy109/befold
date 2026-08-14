---
id: TASK-482
title: サイドバーのファイルオープンを修飾キーで新規タブ・新規ウィンドウへ振り分ける
status: To Do
assignee: []
created_date: '2026-08-14 12:22'
updated_date: '2026-08-14 13:22'
labels:
  - feature
milestone: m-2
dependencies: []
priority: high
ordinal: 699000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーの行をクリックすると常に現在のタブでファイルが差し替わる（`FileListView.swift:117-141` のシングルタップが `switchFile` へ直行）。別タブ・別ウィンドウで開く手段は右クリックメニュー（`SidebarContextMenu.swift:34-37`）だけで、ビューア内の Markdown リンクが既に持っている修飾キーの操作体系がサイドバーには届いていない。

befold には修飾キーから開き方を決める単一の対応表 `OpenDisposition`（`BefoldKit/OpenDisposition.swift:16-22`）が既にあり、Markdown リンク（`BridgeMessageRouter.swift:54-64`）と直接 HTML モード（`DirectHTMLLinkPolicy.swift:17-47`）の両方がこれを通している。サイドバーだけがこの表を通っていない状態なので、新しい規則は作らず既存の表へ配線する。

対応表（既存・変更しない）:

| 修飾 | disposition |
|---|---|
| なし | `.currentTab` |
| ⌘ | `.newTab` |
| ⌘⇧ | `.newWindow` |
| ⌃ / 右クリック | コンテキストメニュー（開かない） |

配線先も既存で、`FileListViewDelegate.fileListDidSelectFile(_:)` と `fileListDidRequestOpenElsewhere(_:disposition:)`（`FileListViewDelegate.swift:20,26`）の 2 本がそのまま使える。新しい状態も新しい経路も増えない。

VSCode の Explorer では ⌘クリックは複数選択・⌥クリックが横に開くだが、befold のサイドバーは単一選択（`model.selection` が単一の id）で複数選択の概念が無く ⌘ が空いている。VSCode に合わせるのではなく befold 内のリンク操作へ揃える判断を採る（ユーザー確認済み）。

修飾キーの取得は `NSEvent.modifierFlags` をハンドラ内で読む方式を採る。`SpatialTapGesture` は修飾キーを運ばないため何らかの取得手段が要るが、`HistoryButtonView.swift:37-41` が既に同じ方式で ⌘/⌃クリックを判定しており前例と一致する。`NSClickGestureRecognizer` を重ねる案は、行の当たり判定を AppKit 側へ持ち込むため採らない（ユーザー確認済み）。

キーボード操作も同時に揃える。`SidebarKeyAction.action(key:modifiers:target:mode:)`（`SidebarKeyAction.swift:59-79`）は既に `EventModifiers` を受け取っており、Return に ⌘ / ⌘⇧ を足す形で拡張できる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーのファイル行を ⌘ クリックすると、現在のタブの表示を変えずに同じタブグループの新規タブでそのファイルが開く
- [ ] #2 サイドバーのファイル行を ⌘⇧ クリックすると、現在のタブの表示を変えずに新規ウィンドウでそのファイルが開く
- [ ] #3 ⌘ / ⌘⇧ クリックでは `model.selection` が移動しない（サイドバーの選択はそのウィンドウが表示中のファイルを表す不変条件を保つ）
- [ ] #4 修飾キー無しのクリックは従来どおり現在のタブで表示が差し替わり、選択も移動する
- [ ] #5 ⌃ クリックではファイルを開かない（コンテキストメニューに委ねる）
- [ ] #6 開閉三角の当たり判定（`SidebarRowIndent.isWithinDisclosure`）は修飾キーの有無にかかわらず従来どおり最優先で処理される
- [ ] #7 サイドバーにフォーカスがある状態で ⌘Return は新規タブ、⌘⇧Return は新規ウィンドウでファイルを開き、修飾キー無しの Return は従来どおり現在のタブで開く
- [ ] #8 修飾キーの対応表は `OpenDisposition` の 1 箇所のままで、サイドバー用の独自の判定表を新設していない
- [ ] #9 ユニットテストが ⌘ / ⌘⇧ / 修飾なし / ⌃ の 4 ケースについて、呼ばれるデリゲートメソッドと disposition、および selection が動くかどうかを検証している
- [ ] #10 テストは修正を戻すと落ちることを確認済み
<!-- AC:END -->
