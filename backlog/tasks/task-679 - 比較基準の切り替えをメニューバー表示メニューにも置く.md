---
id: TASK-679
title: 比較基準の切り替えをメニューバー(表示メニュー)にも置く
status: Done
assignee: []
created_date: '2026-10-08 08:17'
updated_date: '2026-10-08 08:25'
labels:
  - feature
dependencies:
  - TASK-678
priority: low
ordinal: 868000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-678 でツールバーの比較基準ポップアップを撤去し、切り替えの入口はサイドバーの「変更のあるファイルのみ」の ▾ だけになった。メニューバーに比較基準を切り替える項目が無く、サイドバーを畳むと基準を見る・変えるどちらも手段が無い(TASK-678 の「記録」で認めた帰結。2026-10-08 の実機確認でユーザーが指摘)。表示メニューに基準 3 種(ComparisonTargetPresentation.selectableTargets)をチェック付きで出し、書き込み口は ViewerDocumentPresenter.setComparisonTarget の 1 本のまま使う。他の表示切り替え(⌃⌘T ほか)の MainMenuBuilder+ViewMenu の流儀に揃える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 表示メニューに比較基準の項目が出て、現在の基準にチェックが付く
- [x] #2 選択肢は selectableTargets を使い、スタック全体は親ブランチがデフォルトと異なるときだけ出る
- [x] #3 git 管理外では項目が無効化(または出ない)で、メニュー項目の配線漏れを測るテストがある(/menu-audit で実測)
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
表示メニューに「比較基準」サブメニュー(3 種、tag で選択、selectComparisonTarget → setComparisonTarget)を追加。選択肢は selectableTargets、git 管理外は canFilterChangedFiles で無効。ComparisonMenuValidatorTests と MainMenuBuilderTests で配線を固定。/menu-audit 実測: 「このブランチの変更」✓・「作業中の変更」、スタック全体は親=デフォルトのため非表示。swiftlint 差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
