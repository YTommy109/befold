---
id: TASK-537
title: git 管理外のフォルダーでは「変更のあるファイルのみ」を無効化する
status: To Do
assignee: []
created_date: '2026-08-22 12:39'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 781000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
git 管理下でないディレクトリを開いていても、View メニューの「変更のあるファイルのみ表示」とサイドバーヘッダーの同トグルが操作でき、メニューも有効のまま。実際には何も起きない（絞り込む git 状態が無いため）ので、操作できること自体が誤り。ユーザーは「効かない機能」に見える。

現状の実装:
- BefoldApp/befold/App/AppDelegate.swift:276 validateMenuItem は sidebar 表示 3 項目の有効／無効を SidebarDisplayMenuState.isEnabled で決めているが、この値は「アクティブなビューアウィンドウがあるか」だけを見ており、開いているフォルダーが git 管理下かを見ていない（BefoldApp/befold/App/SidebarDisplaySettings.swift:105 付近）。
- サイドバーヘッダー側のトグル（BefoldApp/befold/Viewer/SidebarHeaderView.swift:24 onToggleChangedFilesOnly）も同様に常に押せる。
- 実際の絞り込みは SidebarListingCoordinator.swift:90 で showChangedFilesOnly を反転させ、git 状態を一覧タスクへ結合する経路（同 145 付近）。git リポジトリ外なら git 状態が空なので結果が変わらない。

「変更のあるファイルのみ」だけの話ではなく、git 由来の UI（差分表示など）が同じ穴を持っていないかも合わせて確認する。CLAUDE.md の「同型のバグが 2 回目に出たら構造で塞ぐ」に従い、個別の分岐追加ではなく『開いているフォルダーが git 管理下か』を 1 箇所で持ち、メニューとヘッダーの双方がそこを参照する形にできないか検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 git 管理下でないフォルダーを開いているとき、View メニューの「変更のあるファイルのみ表示」が無効（グレーアウト）になる
- [ ] #2 同じ状況でサイドバーヘッダーの同トグルも操作できない（または表示されない）
- [ ] #3 git 管理下のフォルダーでは従来どおり操作でき、絞り込みが効く
- [ ] #4 git 管理下かどうかの判定は 1 箇所に集約され、メニューとヘッダーが同じ値を参照する
- [ ] #5 ユニットテストで、git 管理外／管理下それぞれの有効・無効状態を固定する
<!-- AC:END -->
