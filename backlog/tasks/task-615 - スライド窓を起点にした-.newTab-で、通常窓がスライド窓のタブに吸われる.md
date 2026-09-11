---
id: TASK-615
title: スライド窓を起点にした .newTab で、通常窓がスライド窓のタブに吸われる
status: To Do
assignee: []
created_date: '2026-09-11 13:53'
labels: []
dependencies: []
ordinal: 805000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-613 のコードレビュー（finderA）で検出し、実測で確定した既存の穴。TASK-613 が「同じファイル」のケースまで広げた。

実測（ヘッドレスのテストホスト、`MockedViewerWindowManager`）: スライド窓 A を起点に `.newTab` で別ファイル B を開くと、B の通常窓（`kind == .viewer`）が A のタブグループに入る。同じファイル A を `.newTab` で開いた場合も同様（TASK-613 前はスライド窓自身が再利用候補になって前面化していたが、今は候補から外れて通常窓が新しく開き、それがスライド窓のタブになる）。`ViewerWindowChrome` はスライド窓に `tabbingMode = .disallowed` を立てているが（コード参照）、これは**自動**タブ化を止めるだけで、`NSWindow.addTabbedWindow(_:ordered:)` の明示的な結合は通る（実測: `tabbingMode.rawValue == 2` のまま `tabGroup` が非 nil になった）。

経路（コード参照）: スライド窓内のリンク cmd+クリック → `ViewerWindowController+References.openReference` → `openFileElsewhere(url, .newTab, .afterSource, window)` → `ViewerWindowManager.openViewer(disposition: .newTab, relativeTo: slideWindow)` → `ViewerTabGrouping.present(asTabOf: slideWindow)` → `attachAsTab`。起点側の種別（`joinsTabs`）を見る場所がどこにも無い。

方針の候補: 起点の窓が `joinsTabs == false` なら `.newTab` を `.newWindow` として扱う。判定を置くのは `openViewer`（`asTabOf:` を決めている 1 箇所）か `ViewerWindowOpenPolicy`。起点の `kind` は `sourceWindow.windowController as? ViewerWindowController` から引ける（`ViewerTabGrouping.viewerPath(of:)` と同じ形）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 スライド窓を起点に `.newTab` で別ファイルを開くと、独立した通常窓が開き、スライド窓のタブグループには入らない
- [ ] #2 スライド窓を起点に `.newTab` で同じファイルを開いた場合も同様に独立した通常窓が開く
- [ ] #3 通常窓を起点にした `.newTab` の挙動（タブ合流・置き場所・背面で開く）は変わらない
- [ ] #4 起点の種別で分岐する判定は 1 箇所に置き、`ViewerWindowManagerTabTests` で実配線のテストを持つ
<!-- AC:END -->
