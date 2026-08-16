---
id: TASK-503
title: ショートカット一覧にメニュー外のキー操作を載せる
status: To Do
assignee: []
created_date: '2026-08-16 11:41'
updated_date: '2026-08-16 11:42'
labels:
  - chore
dependencies: []
priority: medium
ordinal: 111500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Help > キーボードショートカットは MenuShortcutCatalog がメインメニューから生成しており（BefoldApp/befold/App/MenuShortcutCatalog.swift:38-51）、メニュー項目に割り当てたキーは漏れなく載る。一方、メニューを経由しないキー操作が一切載らない。

載っていないもの（TASK-502 の調査で判明）:
- ビューア内スクロール: Space / ⇧Space（ページ）、j / k / ↑ / ↓（行）、⇧+それら（半ページ）、Esc（検索バーを閉じる）— BefoldApp/viewer-src/keyboard.js:36-48, :56
- サイドバーのキー操作: j/k/↑/↓ 選択、l/→/Return で進む、h/← で戻る・畳む、⌘↑ と delete で親へ、⌘Return 新規タブ、⌘⇧Return 新規ウィンドウ — BefoldApp/befold/Viewer/SidebarKeyAction.swift:60-85
- Quick Open パネル内の ↑/↓/Tab/Esc — BefoldApp/befold/App/QuickOpenView.swift:41-56
- マウス/トラックパッド操作: ⌃ホイールでズーム、水平スワイプで戻る/進む、⌘クリック / ⌘⇧クリック / ⌃クリック — docs/dev/native-app-design.md:247, 258-262

論点は「メニュー由来の一覧に、別の情報源のものをどう混ぜるか」。メニュー定義を唯一の情報源にした TASK-240 の判断を壊さない形（例: 由来ごとにセクションを分け、非メニュー分はそれぞれの実装側に定義を持たせて引く）で設計する。載せる文言をビューにハードコードするのは、同じ乖離を作り直すことになるので採らない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ビューア内スクロール・サイドバー・Quick Open のキー操作がショートカット一覧に載っている
- [ ] #2 マウス/トラックパッド操作を載せるかどうかを判断し、結論を Implementation Notes に残している
- [ ] #3 非メニュー由来の項目も、表示用の文字列をビューにハードコードせず実装側の定義から導いている
- [ ] #4 実装側の割り当てを変えたときに一覧との乖離が検出できるテストがある
<!-- AC:END -->
