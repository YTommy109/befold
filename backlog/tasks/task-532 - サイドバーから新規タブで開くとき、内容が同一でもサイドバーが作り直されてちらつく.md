---
id: TASK-532
title: サイドバーから新規タブで開くとき、内容が同一でもサイドバーが作り直されてちらつく
status: In Progress
assignee: []
created_date: '2026-08-19 14:49'
updated_date: '2026-08-19 15:29'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 774000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーでファイルを Cmd+クリックして新規タブで開くと、サイドバーの表示内容は変わらないはずなのにリフレッシュされてちらつく。

## 前提の訂正

起票時の見立ては「タブで開いたファイルにサイドバーを追従させるロジックが働いている」だったが、コード上そのような追従は Cmd+クリック経路に存在しない。親ディレクトリ追従（SidebarNavigator.syncAfterSwitch → SidebarPostSwitchSync.apply, SidebarNavigator.swift:302-310）が走るのは .currentTab の switchFile・履歴適用・リネーム・フォルダー移動のみで、ViewerWindowManager.openViewer（ViewerWindowManager+OpenViewer.swift:21-73）は追従を一切呼ばない。

指摘の本質（サイドバーの情報が正なので作り直す必要がない）はそのまま成立する。実態は「追従して動いている」のではなく「同じ内容を作り直しているのに差分を取っていない」。

## 原因（コード参照。実機未計測）

Cmd+クリック 1 回につき、同一ディレクトリのまま全件再列挙が最大 3 回走る。

1. 新規タブは空の一覧から作られる — ViewerWindowAssembler.swift:28-45 が entries: [] で SidebarNavigator を新造し、ViewerWindowController.swift:321-323 が直後に非同期 refreshFileList()。元タブが同じディレクトリを列挙済みでもそれを引き継がず、「空 → 列挙 → 描画」の 2 段階を必ず通る。TASK-530 は空状態の文言を出さなくしただけで、この 2 段階自体は残っている。
2. キー化のたびに無条件再列挙 — ViewerWindowController+WindowDelegate.swift:26-31 の windowDidBecomeKey が同一性チェックなしで refreshFileList() を呼ぶ（「ディレクトリ監視をしていないのでキーになった契機で取り直す」というコメント付き）。新規タブのキー化で 1 回、元タブへ戻すと元タブでも 1 回。
3. 結果が同一でも代入する — SidebarListingCoordinator.performListing（SidebarListingCoordinator.swift:154-200）は毎回 generation += 1 と tree.reloadExpandedChildren() を実行し、FileListModel.setEntries（FileListModel.swift:48-55）に「同じ結果なら代入しない」比較が無い。entries 代入で entryIndex 再構築と notifyPresentationTargetChangeIfNeeded() が走り、SwiftUI の List が行を作り直す。

## 検討すべき方針（着手時に /review-design で確定する）

新しい状態やフラグ（「サイドバー由来のオープンか」など）を足す方向は採らない。区別に必要な情報は既にあるため、次のいずれか、または組み合わせで、経路を増やさずに済むはず。

- 列挙結果の等価比較を FileListModel.setEntries に入れ、同一なら代入しない（3 の除去。1・2 が残っても描画は動かなくなるので、これ単独で症状が消える可能性がある）
- 新規タブが同じディレクトリなら、元タブ（sourceWindow）の列挙済み一覧を初期値として引き継ぐ（1 の除去）
- windowDidBecomeKey の再列挙に、直近の列挙からの経過や mtime による早期 return を入れる（2 の抑制。ただしファイル監視をしていない前提を崩さないこと）

## 関連

- TASK-529（ウィンドウ枠のちらつき、Done）: 別事象。タブ結合と表示の順序を ViewerTabGrouping.present へ閉じ込めて解決済み。本件はサイドバー内容の再描画で、529 の修正後も残る。
- TASK-530（読み込み中の「対応ファイルがありません」、Done）: 同じ「空 → 埋まる」2 段階が原因だが、対処は文言のガードのみ。本件は 2 段階そのものを無くす話。
- 105ce54a fix: サイドバーからタブを開く周辺の不具合 3 件を修正する (#577)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同一ディレクトリのファイルを Cmd+クリックで新規タブに開いたとき、サイドバーの行が再構築されず、目視でちらつきが確認できない
- [ ] #2 着手時に実機でちらつきを再現・記録し、修正後の比較結果を Implementation Notes に残す（コード上の推論のまま修正しない）
- [ ] #3 同一ディレクトリでの再列挙が実際に何回走っているかを計測し、修正後の回数と併せて記録する
- [ ] #4 サイドバーの表示内容が実際に変わる場合（別ディレクトリのファイルを新規タブで開く・フォルダー移動・隠しファイルトグル・並び順変更・レイアウト切替・リネーム）は従来どおり更新される
- [ ] #5 ファイル監視をしていない前提（windowDidBecomeKey での取り直し）が要る場面 — 外部でファイルが追加・削除された後にウィンドウをキーにする — で、一覧が更新されることを確認する
- [ ] #6 「同じ内容なら作り直さない」ことを固定する回帰テストを追加し、修正を戻すと落ちることを実測で確かめる
- [ ] #7 着手前に /review-design を 1 回回し、結果を Implementation Plan に反映する（既存の状態・経路を増やさない方針の妥当性を確認するため）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果（AC#7）と、実測による前提の訂正

起票時の原因分析 3 のうち「SwiftUI の List が行を作り直す」は **誤り**だった。
実測（使い捨ての probe テストを書いて withObservationTracking で計測、計測後に削除）:

| 操作 | 観測の発火回数 |
|---|---|
| `entries` へ同値（同一インスタンス）を再代入 | 0 |
| `entries` へ等値な別インスタンスを再代入 | 0 |
| `sortOrder` / `filterText` へ同値を代入 | 0 |
| `gitStatus` / `baseDirectory` へ同値を代入 | 0 |
| `listSnapshot`（サイドバーの行を作る導出）を読む観測 | 0 |
| `previewTarget` を読む観測 | **1** |

Swift の Observation は Equatable な値の同値代入では観測を汚さない。したがって
「同じ結果でも代入すればサイドバーの行が作り直される」は起きない。
実際に汚れるのは `FileListModel.entryIndex`（Equatable ではない）の作り直しを経由する
側だけで、それを読むのは `previewTarget` = ViewerContentView とツールバー同期。

**帰結: 原因 3 は、報告されたサイドバーのちらつきを説明しない。**
残る候補は原因 1（新規タブが空の一覧で作られ「空 → 列挙 → 描画」の 2 段階を必ず通る /
ViewerWindowAssembler.swift:35-44 + ViewerWindowController.swift:323）。

## 採った方針

原因 3 の除去（列挙結果が前回と完全に同一なら反映しない）だけを入れた。判定は
`SidebarTreePresenter.applyRows` に置く——`lastListing` の更新と同じ同期区間に収める
必要があるため（モデル側へ置くと材料だけが進む窓ができる / SidebarTreePresenter.swift:63-64
の不変条件）。

レビューで挙がった兄弟箇所（`gitStatus` / `baseDirectory` の同値再代入）へのガードは
**入れない**。上の実測どおり Swift 側が既に抑止しており、書いても冗長だから。
その前提が変わったら気づけるよう、回帰テストとしてだけ固定した。

## 残っていること

- AC#1 / AC#2 の実機目視は未実施。このセッション（バックグラウンドジョブ）は
  TCC が下りず System Events がタイムアウトするため GUI 操作ができない。
- 原因 1 の除去（新規タブが同じディレクトリなら元タブの一覧を引き継ぐ）は未着手。
  ツリー展開の材料は元タブの SidebarTreePresenter が持つため、行だけ引き継ぐと
  直後の refreshFileList で展開が畳まれて別のちらつきになる。着手には方針判断が要る。
<!-- SECTION:PLAN:END -->
