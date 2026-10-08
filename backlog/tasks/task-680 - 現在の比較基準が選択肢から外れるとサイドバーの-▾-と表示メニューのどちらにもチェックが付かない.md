---
id: TASK-680
title: 現在の比較基準が選択肢から外れるとサイドバーの ▾ と表示メニューのどちらにもチェックが付かない
status: To Do
assignee: []
created_date: '2026-10-08 08:47'
labels:
  - bug
dependencies: []
priority: medium
ordinal: 869000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high(2026-10-08、TASK-678/679 の差分)の指摘 4 件を同じ原因で束ねたもの。

**原因**: 「現在の基準」と「選べる基準」の対を 2 箇所(SidebarHeaderControlsModel の comparisonItems + comparisonTarget、ViewerMenuValidationSource.comparisonMenuState の ComparisonMenuState)で別々に導いており、どちらも「現在の基準が選択肢に含まれる」ことを保証していない。ComparisonTargetPresentation.selectableTargets は resolution.parentDiffersFromDefault が false なら .defaultBranch を落とすが、store.comparisonTarget を戻す処理はどこにも無い(確認: rg で comparisonTarget への書き込みは ViewerDocumentPresenter.setComparisonTarget の 1 本、呼び手はメニューとサイドバーのユーザー操作のみ)。

**再現**: 「スタック全体の変更」を選んだ後に、サイドバーを別リポジトリ・git 管理外のフォルダーへ移す、または親ブランチ == デフォルトになるブランチへ切り替える。comparisonTarget は .defaultBranch のまま、selectable は [.parentBranch, .head]。サイドバーの Picker は tag 不一致で選択無し(SwiftUI の invalid selection 警告)、表示メニューは .defaultBranch の項目を isHidden にして現在の基準そのものが消える。差分もバッジも .defaultBranch で取れ続けるので UI と実体がずれる。

**同じ原因に乗る小さな指摘**(同じタスクで片付ける):
- SidebarComparisonItem.isChecked は本番コードから読まれていない(ビューは Picker(selection:) で判定。rg で読み手は overflow 用の SidebarHeaderControls の 1 箇所のみ)。SidebarHeaderControlsModelTests の isChecked 固定は本番が消費しない値を測っている
- ComparisonMenuState.isAvailable の doc は「git 管理外では選べない」だけだが、実装は kind.allowsSidebar でもゲートしている。サイドバーの ▾ は canFilterChangedFiles だけを見るので、型 doc の「サイドバーの▾と同じ判定」と食い違う
- ComparisonTargetPresentation.menuItemTag(for:) の firstIndex(of:) ?? 0 は到達不能な失敗を .parentBranch のタグへ静かに写す。allCases を手動定義に変えて 1 ケース落とすと誤配線が見えなくなる

**方針の当たり**(レビューの提案。実装時に /review-design で確定する): current を必ず含める選択肢の導出を ComparisonTargetPresentation に 1 本置き、サイドバーモデルと ViewerMenuValidationSource の両方がそれを読む形にすれば、SidebarComparisonItem と ComparisonMenuState の二重化も畳める。

**経緯**: TASK-679 は新しい状態型・validate 述語・プロトコル要件を 5 ファイルにまたがって足したが /review-design を回していない(rg SECTION:PLAN で 0 件)。本件は設計文の突き合わせで導ける型だった。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 「スタック全体の変更」を選んだ状態で親ブランチ == デフォルトのブランチ(または git 管理外)へ移っても、サイドバーの ▾ と表示メニューの両方で現在の基準にチェックが付き、項目が消えない
- [ ] #2 現在の基準と選べる基準の対を導く場所が 1 箇所で、サイドバーと表示メニューがその同じ値を読む(現在の基準が選択肢に含まれないと落ちるテストがある)
- [ ] #3 ComparisonMenuState.isAvailable の allowsSidebar 条件は、意図した制限なら理由を doc に書き、そうでなければ落として canFilterChangedFiles 1 本にする
- [ ] #4 menuItemTag(for:) の ?? 0 を precondition か強制アンラップへ変え、列挙漏れが静かに別の基準へ写らない
- [ ] #5 本番コードが読まない isChecked(SidebarComparisonItem)とそのテストを残さない
<!-- AC:END -->
