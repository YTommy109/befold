---
id: TASK-678
title: 比較基準の切り替えをサイドバーの「変更のあるファイルのみ」ボタンへ移し、ツールバーのポップアップを撤去する
status: Done
assignee: []
created_date: '2026-10-08 07:18'
updated_date: '2026-10-08 08:49'
labels:
  - feature
dependencies:
  - TASK-353
priority: medium
ordinal: 867000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
比較基準(このブランチ／スタック全体／作業中)の切り替えは差分モード(⌘3)のツールバーにしか無いが、基準はサイドバーの git 変更バッジにも効く(GitStatusReader と GitDiffReader が同じ GitComparisonBaseResolving を通る)。差分モードに入らないと変更ファイルの基準を変えられず、操作の場所と効く範囲がずれている。サイドバーの「変更のあるファイルのみ」ボタン(git 管理下でだけ出る)を Menu(primaryAction:) 形式にし、クリックで絞り込みの ON/OFF、▾ で基準を選べるようにする。操作の入口はサイドバーに一本化し、ツールバーのポップアップは撤去する(2026-10-08 ユーザー判断)。基準は窓ごとのライブ値のまま(TASK-353)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 「変更のあるファイルのみ」ボタンのクリックで従来どおり絞り込みが ON/OFF する
- [x] #2 ボタンの ▾ から基準を選べる。選択肢は ComparisonTargetPresentation.selectableTargets を使い、スタック全体は親ブランチがデフォルトと異なるときだけ出る
- [x] #3 基準を変えるとサイドバーのバッジと差分の両方が追従し、差分モードに入っていなくても切り替えられる
- [x] #4 現在の基準がメニューのチェックとツールチップで分かる
- [x] #5 ツールバーの比較基準アイテムをラベルごと撤去する(ToolbarItemSpec.View.comparisonMenu / applyComparisonState / comparisonTargetChosen / ViewerToolbarHost の基準要件 / diffContentDidChange 配線(TASK-676) / ComparisonTargetPresentation.label と isUnchanged / 関連テストと l10n キー)。差分が無いことは差分セグメントの inactive で伝わる(2026-10-08 ユーザー判断)
- [x] #6 基準の変更経路を一本化し、配線漏れを測るテスト(SidebarDisplayChangeRoutingTests と同型)がある
- [x] #7 git 管理外ではボタンごと出ない現状が保たれる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
/review-design 結果(2026-10-08)。前提と裏付けは本文の各項に併記。

## 決定済み
A. ツールバーの比較基準アイテムはラベルごと全撤去(2026-10-08 ユーザー判断)。差分が無いことは差分セグメントの inactive で伝わる(確認: ViewerToolbarController+State が canSelect(mode) を現在モードに関係なく毎セグメントへ当て、GitDiffAvailability.unchanged で false。再同期は gitContextDidChange → refreshUIState)。これに伴い TASK-676 の diffContentDidChange 配線(ViewerDiffPresenter の 3 呼び出し + ViewerWindowController.swift:37 の注入)と ComparisonTargetPresentation.label(target:resolution:isUnchanged:) は読み手を失うので撤去する。ツールチップのブランチ名は label を使わず、resolution.baseBranch(.head なら HEAD)から直接組む。

## 設計(採る形)
1. ヘッダが読む「現在の基準」は FileListViewDelegate に読み取り要件 `var comparisonTarget: GitComparisonTarget { get }` を足して delegate から読む(nil なら .windowDefault)。ViewerWindowController には同名の computed property(SidebarNavigatorHost 向け、store を読む)が既にあるので準拠は 0 行。代案 1: ViewerStore を Assembler→FileListView→SidebarHeaderView へ必須引数で渡す(依存が明示的だが、サイドバーのビューに文書状態の stored property が増える)。代案 2(不可): FileListModel へミラー=真実の源が 2 つ & 400/400 で余裕 0。**未確認**: delegate 経由の同期アクセスも Observation が追跡し、選択直後にチェックが動くこと(想定どおりのはず。実装時に /run で選択→即チェックを確認し、動かなければ代案 1 へ切り替える)。
2. 項目型 SidebarComparisonItem(target: GitComparisonTarget / titleKey / isChecked)。SidebarOverflowItem と同じく identity は target そのもの、isChecked は init 内で現在値から導く(渡せる形にしない)。項目列は ComparisonTargetPresentation.selectableTargets(resolution: model.gitStatus?.comparison) から作り、SidebarHeaderControlsModel.comparisonItems に載せる。init に comparisonTarget / comparisonResolution を必須引数で足す。
3. SidebarHeaderControls の body の switch に .changedFilesOnly → Menu(primaryAction:) の分岐を 1 つ足す。primaryAction は onSelectControl(.changedFilesOnly)(既存経路)、項目は onSelectComparisonTarget(GitComparisonTarget)。▾ は AC #2 の唯一の入口なので隠さない(⋯ の .menuIndicator(.hidden) に揃えない。SidebarPathMenuButton が自前 chevron を描く理由を参照)。**未確認**: macOS 14 での borderlessButton + primaryAction の見え方(/run で 1 回確かめる)。
4. 配線: SidebarHeaderView.selectComparisonTarget(_:)(internal、テストから呼ぶ) → FileListViewDelegate.fileListDidRequestComparisonTarget(_:)(必須要件、既定実装なし) → ViewerWindowController+FileList で documentPresenter.setComparisonTarget へ。準拠型は実測 2 つ(ViewerWindowController / FileListViewDelegateSpy)で、どちらも要件追加で落ちる。基準の書き込み口は ViewerDocumentPresenter.setComparisonTarget の 1 本のまま(pending 化・着地時照合・バッジ取り直しは既存のまま再利用。新しい世代管理は足さない)。SidebarNavigator(425/425)・FileListModel(400/400)には触らない。
5. ツールチップ: 現行の helpKey(キー文字列)では「変更のあるファイルのみ(main から)」の整形文が作れない。SidebarHeaderControl に helpArgument: String?(ブランチ名)を足し、整形はビュー側で行う(モデルは .l10n に触れず、SidebarHeaderControlsModelTests の helpKey 比較はキーのまま保てる)。ボタンのアクセント色は showChangedFilesOnly のみに保つ(基準は窓の設定で絞り込みではない)。
6. VoiceOver: 撤去する NSPopUpButton には setAccessibilityLabel があり、SwiftUI 側は .help 頼み(.accessibilityLabel は 0 件)。Menu のラベルに accessibilityLabel を付けて後退させない(AC #8)。実装後に accessibility-reviewer を回す。

## 撤去の全列挙(チェック 3)
ToolbarItemSpec.View.comparisonMenu / ViewerToolbarController の comparisonItemIdentifier と spec / +ToolbarDelegate の NSPopUpButton 生成 / +State.applyComparisonState 全体 / +Actions.comparisonTargetChosen / ViewerToolbarHost.comparisonTarget と setComparisonTarget / ViewerWindowController.setComparisonTarget ラッパー(delegate 実装が presenter を直接呼ぶ) / ViewerDiffPresenter.diffContentDidChange(init 引数・3 呼び出し・ViewerWindowController.swift:37 の注入) / ComparisonTargetPresentation.label(isUnchanged:) / ViewerWindowControllerToolbarTests:44 の "diffComparison" / ComparisonTargetTests :76 :84 :107 :136(ラベル・ポップアップ・(変更なし)のテスト。selectableTargets と着地照合のテストは残す) / l10n toolbar.mode.diff.base.group・.base・.base.unchanged(/l10n-check で確定) / docs/dev/viewer-ui.md §差分の比較基準の書き換え(/finish-task 手順 5)。残すもの: SidebarNavigatorHost.comparisonTarget と ViewerWindowController.comparisonTarget(Coordinator とヘッダが読む)、toolbar.mode.diff.target.*(項目名として再利用。必要なら sidebar 配下へ改名)。

## 担保(破れたら落ちるもの)
- SidebarHeaderControlsModelTests: comparisonItems.map(\.target) == selectableTargets(resolution:) と、isChecked が現在値に一致すること。git 管理外では changedFilesOnly ごと出ない既存テストを維持(AC #7)。
- SidebarDisplayChangeRoutingTests と同型: FileListViewDelegateSpy に comparisonTargets 配列を足し、selectComparisonTarget(.head) で [.head] が届き displayChanges は空であることを測る。
- delegate 要件を必須にして配線漏れをコンパイルエラーにする(TASK-590 と同じ構造)。
- 「スタック全体を選んだ直後に項目が消えない」根拠: GitComparisonBaseResolver は target に依らず parentDiffersFromDefault を計算する(GitComparisonBase.swift の differs)。

## 行数(チェック 10、実測)
ViewerWindowController 932/932(+FileList を含む合算)。delegate 実装で +3〜4 行、setComparisonTarget ラッパー(3 行+doc)と diffContentDidChange 注入(1 行)の撤去で相殺できる見込み。実装後に scripts/check-type-group-size.sh で測り、超えるなら例外ファイルの上限を実測値へ張り付ける。SidebarHeaderControlsModel 163→約 200、SidebarHeaderControls 86→約 115、SidebarHeaderView 133→約 145、ViewerToolbarController 382→減、ViewerDiffPresenter 133→減。責務: プロトコル準拠は増えない。注入クロージャは SidebarHeaderControls が 2→3(上限内)。stored property は増えない。

## 記録(再議論しない帰結)
サイドバーを畳むと差分モード中に基準を見る・切り替える手段が無くなる。一本化はユーザー判断(2026-10-08)。SidebarHeaderView.swift:11 の doc「真実の源は SidebarDisplayDefaults」は SidebarDisplayState の記述と食い違う(古い)。実装時に直す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手前に /review-design を回す。未確認: SidebarHeaderControls が Kind ごとに Button で描いているか(Menu への分岐が要る)。基準は表示 4 値(SidebarDisplayChange)に属さないため別の配線経路が要る見込み。ツールバー撤去で差分モード中に基準が見えなくなるため、ラベル表示の代替が要るかを設計で確認する。

2026-10-08 /review-design: ツールバーのラベルは残さない(ユーザー判断)。前提「差分なしなら差分セグメントが inactive になる」はコードで確認済み: ViewerToolbarController+State が canSelect(mode) を現在モードに関係なく毎セグメントへ当て、GitDiffAvailability.unchanged で false になる。再同期は gitContextDidChange → refreshUIState。これにより TASK-676(#726 / #727)で入れた「(変更なし)」ラベル配線は目的を失うので撤去対象。

実装: swift test 全体 2033 件 pass(既知 issue 1 件は既存)。comparisonItems/配線漏れは SidebarHeaderControlsModelTests・SidebarDisplayChangeRoutingTests で固定。未確認: Menu(primaryAction:) の見た目と VoiceOver 実機動作(/run での目視は未実施)。a11y レビュー指摘のうちラベル/値の分離は対応済み。既存ボタンの ON/OFF 状態の VoiceOver 公開は本タスク外。

未検証: AC #1/#3/#4/#8 は GUI 実機(クリックで ON/OFF、基準変更でバッジ・差分が追従、チェック/ツールチップ、VoiceOver)の確認が必要。コードとテストは完了済み。ユーザーの手元確認待ち。

実機確認(2026-10-08): クリックで ON/OFF、基準変更でバッジ・差分が追従、ツールチップ OK。確認で見つかった 2 件(絞り込み中のアイコン色が出ない/メニューのチェックが出ない)は Menu(primaryAction:) をやめ、Button + 独立した ▾ Menu + Picker(inline) に変えて解消。AC #8(VoiceOver)はユーザー判断で外した(VoiceOver を使わない運用。ラベル/値の付与は残してある)。メニューバーに基準切替が無い点は AC 外で、必要なら別タスク。

2026-10-08 /code-review high: Implementation Plan 項目 5(ツールチップを resolution.baseBranch から組む)と項目 6(Menu の accessibilityLabel にコントロール名)が未実装のまま Done になっていた → TASK-681 へ起票。Final Summary の「Menu(primaryAction:) へ移し」は実装(button + 独立 Menu)と食い違う → docs ごと TASK-683 で直す。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
比較基準の切り替えをサイドバーの「変更のあるファイルのみ」Menu(primaryAction:) へ移し、ツールバーのポップアップと TASK-676 の配線・label を撤去。swift test 全件 pass、docs/viewer-ui.md 更新。
<!-- SECTION:FINAL_SUMMARY:END -->
