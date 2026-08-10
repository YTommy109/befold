---
id: TASK-413
title: CLI の表示オプションが保存値を書き換える／既に開いているファイルでは無視される
status: To Do
assignee: []
created_date: '2026-08-10 07:26'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 501000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
openViewer への入口が枝ごとに違う扱いをしており、同じフラグが経路によって「保存値を汚す」「黙って捨てられる」の両方に転ぶ。

1. 保存値の書き換え（ViewerWindowManager.swift:192）: applyDisplayOverrides は CLI の --source / --preview を controller.setDisplayMode 経由で適用するが、setDisplayMode は ViewerWindowController.swift:741 で perFileState.displayMode.setDisplayMode(_:for:) を呼び保存する。パスなしの `befold --source` を打つと、開いている全ファイルの保存済み表示モードが恒久的に上書きされ、以後そのファイルはフラグなしでも source で開く。同じループの隣にある store.applyShowLineNumbersOverride は保存を避けるために存在し、ViewerWindowController.init（:330）も「保存値は書き換えない(この起動限りの上書き)」というコメント付きで非永続の applyDisplayMode を使う。同じフラグがパス指定の有無で逆の永続性になっている。

2. オプションの取りこぼし（ViewerWindowManager.swift:233）: .currentTab の重複抑止は NSApp.activate() / existing.focusWindow() / return だけで、options も forceSidebarVisible も読まない。foo.md を開いた状態で `befold --line-numbers foo.md`（--source / --sidebar / --sort も同様）を打つと、窓が前面に来るだけでフラグは適用されず通知もない。openViewer の doc コメント自身が「options を丸ごと受けるのは途中でオプションを落とさないため」と書いている。

3. 開く順序の非決定（AppDelegate.swift:337）: showOpenPanel は allowsMultipleSelection = true（:329）なのに、完了ブロックで URL ごとに openViewer(for:) を呼ぶ。この 1 引数オーバーロード（:263）は 1 件ごとに Task を張り、その中で Task.detached のファイル解決を待つため、5 件選ぶとウィンドウとキーウィンドウの順序が任意になる。application(_:open:)（:227）と openPaths（:290）は「渡された順にウィンドウが出るよう 1 本の Task で逐次に開く」と明記して 1 本の Task でループしており、Open パネル経路だけがその不変条件から外れている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 パスなしの befold --source / --preview が保存済み表示モードを書き換えない（この起動限りの上書きになる）
- [ ] #2 既に開いているファイルを対象に CLI フラグを渡したとき、フラグが適用される（--line-numbers / --source / --sidebar / --sort）
- [ ] #3 Open パネルで複数選択したとき、選択順にウィンドウが開く
- [ ] #4 オプション適用が openViewer の単一経路に一本化され、入口ごとの分岐で取りこぼせない構造になる
- [ ] #5 上記をユニットテストで担保する（経路を増やしたら落ちる形にする）
<!-- AC:END -->
