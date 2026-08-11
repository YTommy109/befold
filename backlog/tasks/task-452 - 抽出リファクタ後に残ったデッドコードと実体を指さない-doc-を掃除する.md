---
id: TASK-452
title: 抽出リファクタ後に残ったデッドコードと実体を指さない doc を掃除する
status: To Do
assignee: []
created_date: '2026-08-11 13:40'
updated_date: '2026-08-11 13:51'
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
- [ ] #1 RenderedStateMirror の破棄経路が 1 つになっている（reset() を残すなら実際の破棄点がそれを使う。撤去するなら doc 3 箇所とテストも追随している）
- [ ] #2 ViewerWindowController.sourceToggleTarget が撤去されている
- [ ] #3 差分の更新契機と差分レイアウトの参照が、doc の記述と実際の呼び出し経路で一致している（ファサードへ寄せるか、ファサードを撤去して doc を実態へ合わせるかは実装時に決める）
- [ ] #4 削除済みファイルを指す doc 参照が残っていない（scripts/check-doc-symbols.sh の対象外である散文の参照も含めて確認する）
- [ ] #5 SidebarNavigator のテスト観測用パススルーについて、待ち合わせ規則が散文でなく「破れたら落ちる」形になっている（テストの観測点を協調型側へ移す、規則を型で表現する等）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
優先度を low → medium へ引き上げ、ordinal を 100640 へ移した（2026-08-11 の優先順位評価）。理由: 内容が PR #483 の後始末そのもの（実体を指さない doc・デッドコード）であり、分割の判断が記憶に新しいうちに返すのが最も安い。単独の 1 PR とする想定。
<!-- SECTION:NOTES:END -->
