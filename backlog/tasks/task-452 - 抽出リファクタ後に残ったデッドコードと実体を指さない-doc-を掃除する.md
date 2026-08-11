---
id: TASK-452
title: 抽出リファクタ後に残ったデッドコードと実体を指さない doc を掃除する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-11 13:40'
updated_date: '2026-08-11 22:42'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 100640
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #483（TASK-440 / 441 / 442 の抽出リファクタ）の後始末。/code-review high で CONFIRMED / PLAUSIBLE として残った 5 件をまとめる。いずれも 1 PR でレビューできる範囲。

1. `RenderedStateMirror.reset()` がプロダクトから呼ばれていない。`exitDirectHTMLMode` が `DirectHTMLModeController.exit` へ置き換わり、そこでは `recordRendered(RenderedStateMirror())` を代入する形になったため。唯一の呼び出し元は ViewerRendererMessageHandlingTests.swift:231（reset() の動作を確かめるためだけのテスト）。一方で doc コメント 3 箇所（RenderedStateMirror.swift:7 / DirectHTMLModeController.swift:59 / ViewerRenderer+RenderHelpers.swift:50）は「reset() でミラーを一括破棄する」と読者を誘導しており、ミラーにフィールドを足す次の人が呼ばれていない側だけを更新して実際の破棄点を取りこぼす形になっている。

2. `ViewerWindowController.sourceToggleTarget`（ViewerWindowController.swift:138-141）が呼び出し元ゼロ。cmd+U の戻り先の実体は `ViewerDocumentPresenter.toggleSourceView()` 側へ移っている。internal な NSWindowController のプロパティなのでコンパイラは警告しない。

3. `refreshDiff()` のファサードが片方の契機からバイパスされている。ViewerWindowController.swift:55-58 の doc は「契機は表示モード遷移と git 状態の反映の 2 つ」と書いているが、git 状態側は ViewerWindowController+SidebarHost.swift:26 で `diffPresenter.refresh()` を直接呼ぶ。`refreshDiff()` の残る呼び出し元は ViewerDocumentPresenter.swift:139 のみ。`isDiffLayoutSideBySide` も同型（ラッパーが :51、直接参照が +MenuActions.swift:156）。TASK-330 の「バッジと差分の更新契機を 1 つにする」を doc の入口から追う人が、生きている契機を見落とす。

4. 削除済みファイルを指す doc 参照が 5 箇所残っている。`ViewerWindowController+Presentation.swift` / `+DiffPresentation.swift` はこの PR で削除されたが、ViewerWindowController.swift:27, :93, :333-334、+WindowDelegate.swift:8、+FileNavigation.swift:10（ファイル名で明記）が名指ししたまま。責務表（ViewerWindowController.swift:12-22）だけが更新されている。同型が FileListModel+TreeRows.swift:5、OneShotRenderer.swift:1、docs/dev/quicklook.md:149 にもある。

5. SidebarNavigator にテスト観測用の読み取り専用パススルーが 4 本残っている（SidebarNavigator.swift:149 付近の `pendingListingTask` / `pendingGitStatusTask` / `pendingBaseDirectoryTask` / `expandedFolderKeys`）。分割で隠したはずの協調型の状態を再公開しており、しかも「絞り込みが ON のときは listing タスクを含めない」といった待ち合わせ規則が doc コメントの散文としてだけ存在する。テストが誤った待ち合わせ先を await しても、古い完了済みタスクを観測して黙って通る（TASK-293 型の順序回帰が戻る経路）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 RenderedStateMirror の破棄経路が 1 つになっている（reset() を残すなら実際の破棄点がそれを使う。撤去するなら doc 3 箇所とテストも追随している）
- [x] #2 ViewerWindowController.sourceToggleTarget が撤去されている
- [x] #3 差分の更新契機と差分レイアウトの参照が、doc の記述と実際の呼び出し経路で一致している（ファサードへ寄せるか、ファサードを撤去して doc を実態へ合わせるかは実装時に決める）
- [x] #4 削除済みファイルを指す doc 参照が残っていない（scripts/check-doc-symbols.sh の対象外である散文の参照も含めて確認する）
- [x] #5 SidebarNavigator のテスト観測用パススルーについて、待ち合わせ規則が散文でなく「破れたら落ちる」形になっている（テストの観測点を協調型側へ移す、規則を型で表現する等）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. RenderedStateMirror.reset() を撤去。実際の破棄点は DirectHTMLModeController.exit の recordRendered(RenderedStateMirror())。doc 3 箇所（RenderedStateMirror.swift:7 / DirectHTMLModeController.swift:59 / ViewerRenderer+RenderHelpers.swift:50）を実体名へ。既存の struct 単体テスト（7 フィールド中 diffState を検証しておらず名称も古い）を、exit 後に renderer.rendered == RenderedStateMirror() を検証する振る舞いテストへ置換する（ミラー全体比較なのでフィールド追加に自動追随＝破れたら落ちる形）。
2. ViewerWindowController.sourceToggleTarget（:140-143）を削除。参照ゼロで、cmd+U は +MenuActions → ViewerDocumentPresenter.toggleSourceView() を通る。
3. 差分の参照をファサードへ寄せる（A 案）。+SidebarHost.swift:26 の diffPresenter.refresh() → refreshDiff()、+MenuActions.swift:156 の diffPresenter.isLayoutSideBySide → isDiffLayoutSideBySide。isDiffLayoutSideBySide は ViewerToolbarHost のプロトコル要件のため撤去（B 案）は不可。+MenuActions.swift:80 の toggleLayout() の扱いは対称性を見て判断する。
4. 削除済みファイルを指す doc 参照 7 箇所を修正: ViewerWindowController.swift:27 / :95 / :335-336、+WindowDelegate.swift:8、+FileNavigation.swift:10、FileListModel+TreeRows.swift:5、docs/dev/quicklook.md:149。md 相対リンク切れは全件確認済みで 0 件。
5. SidebarNavigator のテスト観測用パススルー: 「絞り込み ON では git 反映が listing タスクに載る（TASK-293 の不変条件）」を doc の散文から実装の保証へ移す。方針はユーザーに確認してから着手する。

5-1. /review-design の結果を反映: SidebarNavigator に awaitSettled() を足し、listing → gitStatus → baseDirectory の 3 本を順に待つ。baseDirectory を外すと『awaitSettled の後に baseDirectory を読むと stale』という散文規則が復活するため（performListing:121 が毎回 baseDirectory.refresh() を発行する）。
5-2. 素朴に pending* を並べて待っているテスト呼び出しを awaitSettled() へ置換する。ハンドルを先取りする競合テスト（ListingCoherence/Generation/GitStatus の 11 箇所）は対象外。
5-3. TASK-293 の不変条件を直接検証するテストを足す: 絞り込み ON で refreshFileList() した直後、pendingGitStatusTask が更新されない（git 反映が listing タスクに載る）こと。ON 経路が gitStatus 側へ載せ替えられたら落ちる。構造（5-1）だけでは不変条件が壊れたときに落ちないため、両方を置く。
5-4. pendingListingTask / pendingGitStatusTask の doc から ON/OFF の待ち先規則を削除し、用途を『ハンドルを先取りする競合テスト専用』に限定する。awaitSettled() の doc には『待てるのは発行済みの仕事だけで、取り直しが始まる前に測る問題は解決しない』という適用範囲を明記する。
5-5. expandedFolderKeys は待ち合わせではなく状態観測（参照 1 箇所）のため対象外。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
優先度を low → medium へ引き上げ、ordinal を 100640 へ移した（2026-08-11 の優先順位評価）。理由: 内容が PR #483 の後始末そのもの（実体を指さない doc・デッドコード）であり、分割の判断が記憶に新しいうちに返すのが最も安い。単独の 1 PR とする想定。

## 検証

- swift test: 1430 tests / 211 suites 全通過（main 時点は 1429。RenderedStateMirror の struct 単体テスト 1 件を撤去し、DirectHTML 復帰の振る舞いテストと TASK-293 不変条件テストの 2 件を追加）
- swiftlint: main とのベースライン差分で新規違反ゼロ。ViewerRendererMessageHandlingTests の type_body_length 違反が 1 件解消
- swiftformat（fix モード）: 変更なし
- markdownlint-cli2: 70 ファイル 0 issues
- scripts/check-doc-symbols.sh: 指摘なし
- 変異テスト: SidebarListingCoordinator.performListing の ON 分岐を applyWhenReady へ載せ替えると、新テスト changedFilesOnlyCouplesGitStatusIntoListingTask が 2 件の expectation で落ちることを実測（確認後に復元）

## 実装の判断

1. RenderedStateMirror.reset() は撤去。破棄点は DirectHTMLModeController.exit の recordRendered(RenderedStateMirror()) 1 箇所に統一し、doc 3 箇所を実体名へ直した。旧テストは struct の 7 フィールド中 6 つしか見ておらず diffState が抜けていたため、exit 後に rendered == RenderedStateMirror() を比較する振る舞いテストへ置換した（全体比較なのでフィールド追加に自動追随する）。

3. ファサード撤去（B 案）は不可。isDiffLayoutSideBySide は ViewerToolbarHost のプロトコル要件（ViewerToolbarController.swift:23）なので、撤去するとプロトコル定義とツールバー側 2 箇所まで波及する。ファサードへ寄せる A 案を採り、+SidebarHost.swift:26 と +MenuActions.swift:156 の 2 行を差し替えた。残る diffPresenter. 参照はすべてファサードの本体側（ViewerWindowController.swift:47/52/60/65 と、ViewerToolbarHost.toggleDiffLayout(_:) の実装本体である +MenuActions.swift:80）で、バイパスではない。

4. 候補 7 箇所のうち ViewerWindowController.swift の行番号は起票時とずれていた（:93→:95、:333-334→:335-336）。OneShotRenderer.swift:1 は空振りで、実際の壊れた参照は docs/dev/quicklook.md:149 側だった。網羅スキャンで .claude/CLAUDE.md:108 にも同型（SidebarNavigator+History / +SelectionMemory / +Expansion を分割の前例として挙げているが 3 つとも現存しない）を発見し、現存する分割へ差し替えた。md の相対リンク切れは 0 件。

5. /review-design を実施し、当初案（awaitSettled が listing と gitStatus の 2 本を待つ）を 2 点修正した。
   - baseDirectory を含めた 3 本にした。performListing:121 が毎回 baseDirectory.refresh() を発行するため、2 本だけだと『awaitSettled の後に baseDirectory を読むと stale』という散文規則が場所を変えて復活する。
   - 構造（選択肢を無くす）だけでは不変条件が壊れたときに落ちないため、TASK-293 の不変条件を直接検証するテストを併せて足した。awaitSettled は両方待つので、ON の反映が gitStatus 側へ載せ替えられても待ち合わせ側では検出できない。
   - awaitSettled の doc に適用範囲（待てるのは発行済みの仕事だけで、取り直しが始まる前に測る問題は解決しない）を明記した。
   - テスト呼び出し 74 箇所のうち、ハンドルを先取りする競合テスト 3 ファイル（ListingCoherence / GitStatus / ViewerWindowControllerGitStatus）を除く 12 ファイルを awaitSettled() へ一括置換した。
   - expandedFolderKeys は待ち合わせではなく状態観測（参照 1 箇所）のため対象外とした。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PR #483 の抽出リファクタで残ったデッドコード 2 件と、実体を指さない doc 参照 8 箇所を掃除し、差分更新契機のファサードのバイパス 2 箇所をファサード経由へ寄せた。加えて SidebarNavigator の待ち合わせ規則（絞り込み ON では git 反映が一覧タスクに載る / TASK-293）を doc の散文から構造へ移し、3 本のタスクをまとめて待つ awaitSettled() を入口にして待ち先を選ばせない形にしたうえで、不変条件そのものを検証するテストを追加した。検証: swift test 1430 件全通過、swiftlint はベースライン差分で新規ゼロ・1 件解消、markdownlint 0 issues、変異テストで新テストが不変条件の破壊を検出することを実測。
<!-- SECTION:FINAL_SUMMARY:END -->
