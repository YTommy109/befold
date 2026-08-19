---
id: TASK-532
title: サイドバーから新規タブで開くとき、内容が同一でもサイドバーが作り直されてちらつく
status: To Do
assignee: []
created_date: '2026-08-19 14:49'
updated_date: '2026-08-19 15:48'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 2026-08-20: 原因 3 の除去まで完了。実機確認待ちで中断

**着手再開の条件: 対話セッション（GUI 操作ができる環境）で下の再現手順を 1 回実行すること。**
バックグラウンドジョブでは TCC が下りず、System Events が -1712 でタイムアウトするため
GUI 自動操作ができない（`osascript -e 'tell application "System Events" to get name of first process'`
で実測）。

### 完了したこと

- 56b212bf: 同一ディレクトリの再列挙で `FileListModel.entryIndex` を作り直さない
  （判定は `SidebarTreePresenter.applyRows`）
- 41dda9a6: 原因分析の訂正を Implementation Plan へ記録
- 回帰テスト `SidebarIdenticalListingTests`（7 件）。うち 3 件は修正を戻すと落ちることを実測で確認
  （残り 4 件は AC#4 の手すりと前提の固定で、ガードの有無に関わらず通る＝担保ではない）
- swift test 1678 件通過。swiftlint 新規違反 0（main 54 → head 54、ルール×ファイルで差分なし）

### AC の状況

- AC#3（計測）: 済。列挙回数は 3 回のまま変わらない（この修正では減らない）。減ったのは
  一覧の反映＝索引の作り直しと提示対象の無効化で 3 → 1。`SidebarIdenticalListingTests` の
  最後のテストが数字を固定している。
- AC#4 / AC#5 / AC#6 / AC#7: 済
- AC#1 / AC#2: **未。実機目視が要る。**

### 再開時の手順

1. befold を起動し（`/run`）、任意のファイルを開く
2. サイドバーの別ファイルを Cmd+クリックして新規タブで開く
3. 新しいタブのサイドバーが
   - (a) 一瞬空になってから埋まる → 原因 1。`ViewerWindowAssembler.makeSidebarNavigator`
     が `entries: []` で作り、`ViewerWindowController.swift:323` が非同期に埋める 2 段階が残っている。
     除去には「新規タブが同じディレクトリなら元タブの一覧を引き継ぐ」が要るが、ツリー展開の
     材料は元タブの `SidebarTreePresenter` が持つため、行だけ引き継ぐと直後の refreshFileList で
     展開が畳まれて別のちらつきになる。展開状態の引き継ぎまで含めた設計が要る。
   - (b) 内容は出ているが再描画される → 上記のどれでもない別の原因。再調査から。
   - (c) もうちらつかない → 原因 3 の除去で消えていたことになる。AC#1/#2 を埋めて完了へ。

## 2026-08-20 追記: (a)/(b) をモデル層で実測し、原因 1 も除去した

GUI 目視はできないが、(a)/(b) の判別は客観的に測れたので測った。
`ViewerWindowControllerFixture` で実ディレクトリ（4 ファイル）に対し窓を 2 枚作った実測:

```
first  : hasLoadedEntries=true  rows=4
second@init   : hasLoadedEntries=false rows=0   ← 空を経由している
second@settled: hasLoadedEntries=true  rows=4
same-directory-rows-equal = true                 ← 作り直す必要が無かった
```

**(a) で確定。** 新規タブは必ず「空 → 列挙 → 描画」の 2 段階を通り、しかも埋まった
結果は元タブと完全に同一だった。

### 入れた修正（e2738b37）

起点の窓が同じフォルダを列挙済みなら、その結果を出発点として引き継ぐ
(`SidebarListingSeed`)。

- **運ぶのは行ではなく材料**(`DirectoryListing`)。行は窓ごとの展開状態を当てて作るので、
  元タブの展開を写すと新しい窓と食い違う。材料を渡して新しい窓自身に畳ませれば、
  その窓が自分で列挙したときと同じ行になる。**懸念していた「展開が畳まれて別の
  ちらつきになる」は、この形にしたことで起きない**（`lastListing` はルートの材料だけで、
  展開の材料は各窓の `SidebarTreePresenter` が別に持つため）。
- 引き継ぎは `attach` と同じ区間で当てる。最初の `refreshFileList` より前になることが
  構造で決まり、「後から当てて新しい結果を古い写しで潰す」順序ミスが起きない。
- 引き継がない条件（`SidebarListingSeed.canApply`）: 別フォルダ / 列挙の入力
  （並び順・不可視ファイル）が食い違う / 列挙に失敗した結果 / 引き継ぎ先が既に一覧を持つ
- disposition では絞らない。新規タブでも新規ウィンドウでも、同じ一覧を出すなら
  空から作り直す理由が無い。

### 検証

- `swift test` 1684 件通過
- swiftlint 新規違反 0（main 54 → head 54、ルール×ファイルで差分なし）
- 型グループ超過なし（受け皿として `SidebarNavigatorHost` を自分のファイルへ分離）
- 引き継ぎを外すと `SidebarListingSeedTests` / `SidebarIdenticalListingTests` の
  **6 件が落ちる**ことを実測（配線を切るだけでも `openViewer が…引き継ぐ` が落ちる）

### 残り

AC#1 / AC#2 の実機目視のみ。`/run` で起動し、サイドバーの別ファイルを Cmd+クリックして
ちらつきが消えていることを確認する。消えていなければ、(b) の別原因が残っていることになる。
<!-- SECTION:NOTES:END -->
