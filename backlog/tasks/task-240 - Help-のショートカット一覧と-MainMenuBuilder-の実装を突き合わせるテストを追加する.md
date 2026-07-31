---
id: TASK-240
title: Help のショートカット一覧と MainMenuBuilder の実装を突き合わせるテストを追加する
status: To Do
assignee: []
created_date: '2026-07-31 23:26'
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
- [ ] #1 MainMenuBuilder が設定するショートカットと KeyboardShortcutsView の一覧が一致することを検証するテストがある
- [ ] #2 AppKit 標準提供などテスト対象外とする項目が、理由付きで明示されている
- [ ] #3 現状の実装でテストがパスする(既存の乖離があれば表側を修正する)
<!-- AC:END -->
