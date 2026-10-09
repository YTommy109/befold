---
id: TASK-681
title: 「変更のあるファイルのみ」の ▾ のラベルとツールチップが縮退(親ブランチ不明→デフォルト)とコントロール名を伝えない
status: Done
assignee: []
created_date: '2026-10-08 08:48'
updated_date: '2026-10-08 10:57'
labels:
  - bug
dependencies:
  - TASK-680
priority: medium
ordinal: 870000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high(2026-10-08、TASK-678/679 の差分)の指摘 2 件。どちらも ▾ Menu のラベル・ツールチップ・VoiceOver 読み上げの中身の話で、TASK-678 の Implementation Plan 項目 5・6 が Done のまま未実装になっていたもの。

**縮退が見えない**: TASK-678 でツールバーのラベルを撤去した結果、GitComparisonResolution.baseBranch / degraded の読み手が本番コードから 0 になった(確認: rg で GitComparisonBase.swift 以外は 0 件、テストにしか無い)。親ブランチを解決できないブランチで「このブランチの変更」にチェックが付いたまま、実際は main との差分・バッジが出る。ツールチップ(SidebarHeaderControls.changedFilesOnlyMenu の help)もメニューも ComparisonTargetPresentation.title(for:) だけで「main から」を出さないため、ユーザーは縮退に気付けない。TASK-678 Plan 項目 5「ツールチップは resolution.baseBranch から組む」が未実装。縮退をツールチップ/項目名に出すか、出さないと決めて dead フィールドを落とし docs の記述も直すか、どちらかに決める。

**コントロール名が無い**: ▾ Menu の accessibilityLabel と help に「現在の基準の名前」(値)だけを入れており、撤去した NSPopUpButton が持っていた「差分の比較基準」(コントロール名、toolbar.mode.diff.base.group)に相当するラベルが無い。VoiceOver は「このブランチの変更, メニューボタン」と読み、何を切り替えるボタンか分からない。TASK-678 Plan 項目 6「Menu のラベルに accessibilityLabel を付けて後退させない」の意図は、名前→値の順で読ませる(accessibilityLabel に名前、accessibilityValue に基準)形。AC #8 はユーザー判断で外したが、1 行で直る後退。

TASK-680 と同じ SidebarHeaderControls.swift を触るので、そちらの後に着手する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 親ブランチを解決できずデフォルトブランチへ縮退しているとき、▾ のツールチップまたは項目名からそのこと(どのブランチと比べているか)が分かる。あるいは「出さない」と決めて baseBranch / degraded の dead フィールドを落とし、判断を Notes と docs に残す
- [x] #2 ▾ Menu の VoiceOver 読み上げが「コントロール名 → 現在の基準」の順になる(accessibilityLabel に名前、accessibilityValue に基準)
- [x] #3 accessibility-reviewer を回し、後退が無いことを Notes に残す
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC1: 縮退時(degraded)に ▾ とボタンのツールチップへ「親ブランチが不明なため main と比較しています」を出す(SidebarHeaderControlsModel.degradedComparisonBranch)。baseBranch/degraded は読み手が付いたので残す。AC2: ▾ の accessibilityLabel=メニュー名「比較基準」(menu.view.comparisonTarget を流用)、accessibilityValue=基準(縮退注記付き)。AC3: accessibility-reviewer 実施。読み上げ順の後退なし。指摘の value/help 重複は Value を .help と別文字列(改行なし)にして対応。実機 VoiceOver は未確認。
<!-- SECTION:NOTES:END -->
