---
id: TASK-240
title: Help のショートカット一覧と MainMenuBuilder の実装を突き合わせるテストを追加する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 23:26'
updated_date: '2026-07-31 23:40'
labels:
  - refactor
dependencies: []
priority: low
ordinal: 443000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KeyboardShortcutsView.swift:18-61 のショートカット一覧は、MainMenuBuilder が実際に設定する keyEquivalent と対応関係があるが、乖離を検出する仕組みが無く人力で同期している。メニュー側のショートカットを変更・追加してもヘルプ表が古いまま残る。両者を突き合わせるユニットテストを追加して乖離をビルド時に検出できるようにする。なお cmd+h / cmd+q / cmd+m のように AppKit が標準で提供しメニュー構築コードには現れない項目があるため、単純な集合一致では落ちる。例外リストを明示的に持つか、突合対象を『MainMenuBuilder が keyEquivalent を設定する項目』に限定する必要がある。

(TASK-238 の調査中に発見。ハードコードされた静的テーブルの外部リソース化を検討したが、LocalizedStringResource のキー参照による型安全性が失われるため Swift のまま維持し、代わりに整合性テストで担保する方針とした)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 MainMenuBuilder が設定するショートカットと KeyboardShortcutsView の一覧が一致することを検証するテストがある
- [x] #2 AppKit 標準提供などテスト対象外とする項目が、理由付きで明示されている
- [x] #3 現状の実装でテストがパスする(既存の乖離があれば表側を修正する)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
起票時の前提「cmd+h / cmd+q / cmd+m は AppKit 標準提供でメニュー構築コードに現れない」は誤りだった。MainMenuBuilder は cmd+h(59行) cmd+q(68行) cmd+m(236行) を含め全ショートカットを明示的に設定している。したがって「二重管理して突合テストで守る」のではなく、単純化して二重管理自体を無くす。

1. MenuShortcutCatalog(新規)を追加し、NSMenu ツリーを走査して keyEquivalent を持つ項目を (メニュー名, 項目名, キー表記) として抽出する。修飾キー表記は ctrl→opt→shift→cmd の標準順
2. KeyboardShortcutsView のハードコード表(44行)を削除し、NSApp.mainMenu から生成した一覧を表示する
3. MenuShortcutCatalog のユニットテストを追加(MainMenuBuilder.build が作る実メニューを入力にして、キー表記・グループ化・keyEquivalent 無し項目の除外を検証)
4. 生成結果を実機スクリーンショットで確認し、旧表との差分(乖離していた項目)を記録する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 突合テストではなく二重管理の解消を選んだ。MenuShortcutCatalog(新規)が NSMenu からキー等価付き項目を抽出し、KeyboardShortcutsView のハードコード表(44行)を削除して生成結果を表示する。乖離は構造的に起きない。

AppKit は NSApp.mainMenu に設定した後 Close All(opt+cmd+w) / Quit and Keep Windows / Start Dictation / Emoji & Symbols / Show All Tabs などを差し込むことを実機のメニュー走査で確認したため、AppDelegate が mainMenu へ設定する前に MenuShortcutCatalog.snapshot として抽出しておく方式にした(除外理由はコード内コメントに明記)。

旧一覧の乖離を 2 件検出: (1) Help の項目名が存在しないローカライズキー menu.help.appHelp を参照しており、パネルにキー文字列がそのまま出ていた(正しくは menu.help.visitWebsite)。(2) Window > Zoom など一部項目の扱い。いずれも生成方式で解消。

検証: MenuShortcutCatalogTests(5 テスト/パラメータ 8 ケース)、swift test 1006 件パス、Debug ビルドを起動しパネルをスクリーンショット確認(AppKit 差し込み項目が出ないこと・全グループが並ぶことを目視)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Help のショートカット一覧をハードコード表からメニュー定義由来の生成に変えた。MenuShortcutCatalog が MainMenuBuilder の組み立てたメニューからキー等価付き項目を抽出し、KeyboardShortcutsView はそれを表示するだけになったため、乖離が構造的に起きなくなった。AppKit が後から差し込む項目を含めないよう、mainMenu へ設定する前のスナップショットを使う。旧一覧にあった存在しないキー参照(menu.help.appHelp)も解消。MenuShortcutCatalogTests を追加し swift test 1006 件パス、実機スクリーンショットで表示確認。
<!-- SECTION:FINAL_SUMMARY:END -->
