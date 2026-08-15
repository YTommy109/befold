---
id: TASK-484.1
title: ショートカット表と機能記載の陳腐化を解消する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-14 13:05'
updated_date: '2026-08-15 11:05'
labels: []
milestone: m-1
dependencies: []
parent_task_id: TASK-484
priority: high
type: task
ordinal: 706000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイトの記載が実装に追いついていない箇所のうち、判断を伴わない機械的なずれを先に潰す。他のサブタスクと独立して進められる。

`site/src/views/features.tsx:26-32` のコメントは、表示モードの `⌘1`〜`⌘3` を「フィーチャーゲートで項目数が変わるため確定するまで書かない」としているが、**そのゲートは 2026-08-14 の #518 で撤去済み**で、コメントと判断が実態に合っていない。表示モードは レンダリング / ソース / 差分 の 3 択で確定している。

また差分レイアウトの上下・左右切替（`⌘\`）もショートカット表に無い。

`site/test/shortcuts.test.ts` が Swift 実装と表記を突き合わせているため、表を増やしたらこのテストも通ること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `⌘1` / `⌘2` / `⌘3`（レンダリング / ソース / 差分の切替）がショートカット表にある
- [x] #2 `⌘\`（差分レイアウトの上下・左右切替）がショートカット表にある
- [x] #3 features.tsx の FeatureGate を前提としたコメントが削除または実態に合う内容へ直っている
- [x] #4 日英の両方の表記が更新されている
- [x] #5 `site/test/shortcuts.test.ts` が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. features.tsx の FeatureGate 前提コメントを削除し、実態（表示モード 3 択は #518 で確定）に合う説明へ差し替える
2. SHORTCUTS 表へ ⌘1/⌘2/⌘3（表示モード切替）と ⌘\（差分レイアウト切替）を日英併記で追加。実装にゲートが 1 つも残っていないため、同じく表に無かった ⌃⌘G（変更ファイルのみ表示）・⌃⌘T（サイドバーのツリー表示）も追加する
3. shortcuts.test.ts の GATED_LOCALIZATION_KEYS はゲート全撤去（#518）で全件が実態とずれているため、ゲート機構ごと撤去する
4. ⌘1〜⌘3 は keyEquivalent が String(mode.menuItemTag) の計算値のため、ViewerDisplayMode.swift / ModeSegments.swift を vitest バインディングへ追加し、menuItemTag と ModeSegments.all をパースして静的に解決する
5. (cd site && vitest run + typecheck) で全テスト通過を確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装確認: FeatureGate は #518 でリポジトリから全撤去済み（rg 'FeatureGate' が BefoldApp のプロダクトコードで 0 件）。これに伴い shortcuts.test.ts の GATED_LOCALIZATION_KEYS（⌃⌘G/⌃⌘T/⌘\ の 3 件）も全件が実態とずれていたため、ゲート機構ごと撤去した。

スコープ追加: 表に無かった stable ショートカット ⌃⌘G（変更されたファイルのみ表示）・⌃⌘T（サイドバーのツリー表示）も表へ追加した。AC には無いがタスク表題「ショートカット表の陳腐化を解消する」の範囲内で、ゲート撤去により載せない理由が消えたため。

⌘1〜⌘3 の解決: メニュー定義のキー等価は String(mode.menuItemTag) の計算値でリテラルが現れないため、ViewerDisplayMode.swift（menuItemTag の対応）と ModeSegments.swift（並びと個数）を vitest バインディングへ追加し、parseSwiftMenuItemTags / parseSwiftModeSegments で静的に解決した。site.yml の paths にも両ファイルを追加（Swift 側だけ変えたときに site CI が回るように）。

検証: (cd site && npx vitest run) 181 件全通過、npm run typecheck 通過。逆方向の検証として、実装に無い ⌘9 を表へ一時追加すると『表のショートカットが実装の割り当てに存在する』と『詳細ページの記載が実装の割り当てに存在する』の 2 件が落ちることを実測（ページ描画にも表の行が反映されることの証跡）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
紹介サイトのショートカット表を実装（MainMenuBuilder*.swift）へ追随させた。⌘1/⌘2/⌘3（表示モード切替）・⌘\（差分レイアウト切替）に加え、同じくゲート撤去済みの ⌃⌘G・⌃⌘T を日英併記で追加。features.tsx の FeatureGate 前提コメントを実態に合わせて書き換え、テスト側の GATED_LOCALIZATION_KEYS 機構を撤去、⌘1〜⌘3 は ViewerDisplayMode.swift / ModeSegments.swift のパースで静的に解決するようにした。検証: site の vitest 181 件と typecheck が通過、架空の ⌘9 追加で検知テストが落ちることも実測。
<!-- SECTION:FINAL_SUMMARY:END -->
