---
id: TASK-660
title: 表示中の About・Help 配下のパネルをメニューから前面化すると中央へ跳ぶ
status: Done
assignee:
  - '@claude'
created_date: '2026-09-28 06:30'
updated_date: '2026-09-28 07:38'
labels:
  - bug
  - ui
dependencies: []
priority: low
type: bug
ordinal: 860000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-656 の実装後レビュー（/code-review high）の指摘。TASK-656 以前からある挙動で、TASK-656 の回帰ではない。

読むだけのパネル（About・機能概要・キーボードショートカット・AI 連携・OSS ライセンス）は、`HostedPanelWindowController.showAndActivate()` の呼び出しのたびに `center()` される。`toggle()` は最前面でなければ `showAndActivate()` を呼ぶので、表示中だが key でない窓を前面化するときも中央へ動く。

再現手順（想定）: Help > キーボードショートカットを開き、ビューアの窓の横へ動かす。ビューアの窓をクリックする（パネルは表示されたまま key を失う）。もう一度 Help > キーボードショートカットを選ぶと、パネルが画面中央へ跳ぶ。

TASK-656 で決めた「読むだけのパネルは毎回中央」の意図は、閉じていた窓を開くときの位置であって、表示中の窓を前面化するときに動かすことではない。

## 未確認
上の再現手順は実機で確かめていない（コードの経路から導いたもの）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 表示中の読むだけのパネルをメニューから前面化しても、位置が変わらない
- [x] #2 閉じていた読むだけのパネルを開くと、従来どおり中央に開く
- [x] #3 前面化で位置が変わらないことを確かめるテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. HostedPanelWindowController の centersOnNextShow を撤去する。.remember で保存値が無い初回の中央寄せは init で保存名の登録前に行い、showAndActivate は「保存名が無く、窓が表示されていない」ときだけ center() する
2. テスト: centered の表示中の窓を動かして toggle（最前面でない）しても位置が変わらないこと。保存値なし初回中央を設定窓の構成でも確かめる
3. 修正を戻して新テストが落ちることを確認する
4. swift test（該当スイート）・swiftlint ベースライン差分ゼロを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: 単純化を先に検討し、centersOnNextShow（.centered は毎回・.remember は保存値なしの初回だけ、の 2 つの意味を持つフラグ）を撤去した。.remember の保存値なし初回の中央寄せは init（保存名の登録前）へ移し、showAndActivate は「保存名が無い（.centered）かつ窓が表示されていない」ときだけ center() する。stored property は 1 つ減り、表示時の判定は窓の状態（frameAutosaveName / isVisible）だけで決まる。
テスト: centeredKeepsPositionWhenActivatingVisibleWindow を追加（.centered の窓を動かし、表示したまま isFrontmost=false で toggle → 枠が変わらない）。rememberCentersWithoutSavedFrame を設定窓の構成（settingsLayout: true）にも広げた。
修正を戻して落ちることの実測: (1) showAndActivate の !window.isVisible を外すと centeredKeepsPositionWhenActivatingVisibleWindow が 'window.frame == moved' で失敗。(2) init の center() を外すと rememberCentersWithoutSavedFrame(settingsLayout: false) が 'window.frame == shown' で失敗。settingsLayout: true は中央寄せを外しても通ったので、このケースが担保するのは中央寄せそのものではなく「init で中央へ置いた設定窓が、表示時に中身に合わせて大きさを変えても中央からずれない」こと（中央寄せを表示時から init へ移したことで生じうる回帰への備え）。
検証: swift test 全体 2021 件 + 72 件成功。HostedPanelWindowControllerTests 15 件（引数付き 2 ケース含む）成功。swiftformat による変更なし。swiftlint は origin/main 46 件 / 作業ツリー 46 件で、真の新規・解消ともに 0。check-type-group-size --check は閾値以内。新規ファイルなし（xcodegen 不要）。型・stored property・注入クロージャは増やしていない（1 つ減らした）ので responsibility-reviewer は起動していない。
未確認: Description の再現手順の実機確認はしていない。挙動はテストで確認した（isFrontmost シームで『表示中だが key でない』状態を作っている）。
docs/dev/native-app-design.md の HostedPanelPresenter / HostedPanelWindowController の行を更新した（読むだけのパネルは閉じていた窓を開くたびに中央、表示中の前面化では動かさない）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
表示中の読むだけのパネル（About・Help 配下）をメニューから前面化しても中央へ跳ばないようにした。centersOnNextShow を撤去し、.remember の保存値なし初回の中央寄せは init で、.centered の中央寄せは閉じていた窓を開くときだけ行う。前面化で位置が変わらないテストを追加し、修正を戻すと落ちることを実測済み。swift test 全体成功、swiftlint の main との差分 0。
<!-- SECTION:FINAL_SUMMARY:END -->
