---
id: TASK-659
title: パネル窓の frame autosave 名の登録失敗を無視しており、位置が黙って保存されなくなる（TASK-656 のレビュー指摘）
status: Done
assignee:
  - '@claude'
created_date: '2026-09-28 06:30'
updated_date: '2026-09-28 07:23'
labels:
  - bug
dependencies:
  - TASK-657
priority: low
type: bug
ordinal: 859000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-656 の実装後レビュー（/code-review high）の指摘。

`HostedPanelWindowController` の init が `window.setFrameAutosaveName(name)` の戻り値（Bool）を捨てている。同じ保存名を使う窓が既に生きていると AppKit は登録を拒否し、その窓の移動・リサイズは保存されない。失敗しても何も伝わらない。

テストでは既に起きている。`reopenedFrame` は 1 つ目の窓が生きたまま同名で 2 つ目を作るため、2 つ目の登録は失敗している。復元は登録より前に済むのでアサートは通るが、2 つ目の窓の移動は保存されない。

本番では現状パネルごとに 1 インスタンスなので起きていない。起きるのは、コントローラーを作り直す変更や、設定のビルダーを写して保存名を共有した新パネル（TASK-657 の指摘 4）が入ったとき。TASK-657 で方針の引き方を 1 箇所へ畳むと共有の経路が変わるため、そちらを先に片付ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 保存名の登録に失敗したことが、テストまたは開発時の検査で分かる
- [x] #2 同じ保存名を 2 つのパネルが持つ構成を作れない、または作ったら落ちるテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. HostedPanelWindowController.init で setFrameAutosaveName の戻り値を束縛し assert で検査する（release では止めない。失敗の帰結は位置が保存されないだけのため）
2. HostedPanel を CaseIterable にし、.remember の保存名が全パネルで一意であることをテストで固定する（AC#2）
3. 同名で 2 つ目のコントローラーを作る既存テスト 2 件は、1 つ目の窓に保存名を手放させて「前回の起動が終わった」状態を模す（実測: close では名前は解放されず、setFrameAutosaveName("") で解放され、保存済みの枠は残る）
4. テスト側の修正を外した状態で assert が発火することを実測で確かめる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測(プローブテスト): 同名 2 つ目の setFrameAutosaveName は false。1 つ目を close しても false のまま。1 つ目に "" を設定すると 2 つ目は true になり、UserDefaults の保存済みの枠は消えない。

採用した方針: 戻り値を束縛して assert で検査する（release では止めない。失敗しても位置が保存されないだけなので、アプリを落とすほどではない）。assert の中で呼ぶと release で登録そのものが消えるため、先に束縛する。保存名の重複は HostedPanel に CaseIterable を足し、全パネルの .remember の保存名が一意であることをテスト autosaveNamesAreUniqueAcrossPanels で固定した。保存名を case から導出する案は、永続化済みキー（NSWindow Frame BookmarkManagerWindow / SettingsWindow）の改名になるので採らなかった。
単純化の検討: コントローラーの作り直しは HostedPanelPresenter.controllers がパネルごとに 1 個を保持し続けるため、構造上すでに起きない。状態は増やしていない。
検証（修正を戻すと落ちるか）: テストを直す前の状態で HostedPanelWindowControllerTests を流すと、同名で 2 つ目を作るテストが 'Assertion failed: 保存名 … は別の窓が使用中' で落ちた（signal 5）。SettingsWindow を一時的に BookmarkManagerWindow にすると autosaveNamesAreUniqueAcrossPanels が Expectation failed になった。
テスト: swift test 全 2020 + 72 件通過。swiftformat の変更 0 件。swiftlint は origin/main と同じ 46 件で、新規も解消も 0 件。
responsibility-reviewer: 指摘なし。任意の提案（placementPerPanel の readOnly 列挙を allCases から導出する）は見送った。方針の選択は placement の網羅的な switch が既に強制しているため。
native-app-design.md の HostedPanelPresenter 行に、保存名の一意性と assert の不変条件を 1 文追記した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
HostedPanelWindowController.init で setFrameAutosaveName の戻り値を assert で検査するようにした。あわせて HostedPanel を CaseIterable にし、保存名がパネルごとに一意であることをテストで固定した。同名で窓を作り直す既存テスト 2 件は、1 つ目の窓に保存名を手放させる形へ直した。修正前のテストで assert が発火し、保存名を重複させると一意性テストが落ちることを実測済み。全テスト通過、swiftlint の新規違反なし。
<!-- SECTION:FINAL_SUMMARY:END -->
