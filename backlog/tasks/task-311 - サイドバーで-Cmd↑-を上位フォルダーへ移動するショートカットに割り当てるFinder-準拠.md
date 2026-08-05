---
id: TASK-311
title: サイドバーで Cmd+↑ を上位フォルダーへ移動するショートカットに割り当てる(Finder 準拠)
status: Done
assignee:
  - '@claude'
created_date: '2026-08-05 02:34'
updated_date: '2026-08-05 04:47'
labels: []
dependencies: []
priority: medium
ordinal: 509000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FileListView.handleKey(_:)(FileListView.swift:308-321)は KeyPress のキーだけで分岐しており、修飾キーを見ていない。.leftArrow / "h" / .delete がいずれも navigateToParent()(:372-378)を呼ぶ実装のため、Cmd+←(左矢印)は既に(意図せず)navigateToParent と同じキーにマッチしている。ユーザー確認済み: この重複はそのままでよい。

一方 Cmd+↑(上矢印)は現状 .upArrow の case(→ selectPrevious())にそのままマッチしてしまい、Finder のような「上のフォルダーへ移動」動作にはならない。修飾キーなしの ↑ / k との衝突を避けるため、handleKey に修飾キーの判定を加え、Cmd+↑ のときだけ navigateToParent() を呼ぶ必要がある。

navigateToParent()(:372-378)は model.visibleEntries の .parentNavigation エントリの有無で境界(ホームディレクトリ直下など、親へ移動できない場合)を扱っており、Cmd+← 同様にこの関数をそのまま再利用すれば境界条件は自然に揃う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーにフォーカスがある状態で Cmd+↑ を押すと、現在のディレクトリの親フォルダーへ移動する(navigateToParent 相当の挙動)
- [x] #2 修飾キーなしの ↑ / k は従来どおり選択を1つ上へ移動する(回帰しない)
- [x] #3 Cmd+← は従来どおり navigateToParent として動作し続ける(重複は許容、変更しない)
- [x] #4 親フォルダーが無い(ホームディレクトリ境界など)場合、Cmd+↑ は navigateToParent の既存の境界条件と同じ挙動になる(何も起きない)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileListViewTests に修飾キー経路のテストを先に追加する（Cmd+↑→親へ移動 / ↑単独→selectPrevious 維持 / Cmd+←→親へ移動 維持 / 親エントリ無しなら .ignored）。makeView に onNavigate を渡せるようにする
2. handleKey に modifiers: EventModifiers = [] を追加し、handleKeyPress から keyPress.modifiers を渡す
3. switch の .upArrow より前に 'case .upArrow where modifiers.contains(.command)' を置き navigateToParent() を呼ぶ（境界条件は navigateToParent の既存実装をそのまま再利用）
4. swift test / swiftformat --lint / swiftlint 差分ゼロを確認
5. 実機で Cmd+↑ / ↑ / Cmd+← の 3 経路を手動確認（KeyPress の modifiers 伝搬は自動テストでは確認できないため）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: handleKey に modifiers: EventModifiers = [] を追加し、handleKeyPress から keyPress.modifiers を渡す。switch の .upArrow より前に 'case .upArrow where modifiers.contains(.command)' を置いて navigateToParent() を呼ぶ。境界条件は navigateToParent の既存実装をそのまま再利用したため Cmd+← と自動的に揃う。

検証 1: ユニットテスト 4 件を追加(Cmd+↑→親へ移動 / ↑単独→selectPrevious 維持 / Cmd+←→親へ移動 維持 / 親エントリ無し→.ignored)。修正を戻すと Cmd+↑ の 2 件が落ちることを確認済み(空振りテストでないことの確認)。全体 1109 tests passed。

検証 2: **実機で確認した**。handleKey のユニットテストは SwiftUI の onKeyPress が Cmd 付きのキーを配送するかを検証できない(Cmd 付きはメニューの key equivalent に吸われうる)ため、Debug ビルドに一時 NSLog を入れて System Events でキーを送り、実測した。
- Cmd+↑: onKeyPress に modifiers rawValue=112(=96+command の 16)で届き、navigateToParent が発火
- 修飾なし ↑: rawValue=96 で届き、navigateToParent は発火しない(選択移動のまま)
- Cmd+←: rawValue=112 で届き、navigateToParent が発火(従来どおり)
NSLog は検証後に除去済み。

AC #4(境界)は、navigateToParent を変更せず再利用しているため境界の挙動は Cmd+← と同一であり、.ignored になる経路はユニットテストで固定した。

注: xcodebuild は QuickLook 拡張の署名(embedded binary の証明書不一致)で失敗するが、アプリ本体はビルドされるため直接起動して検証した。この署名エラーは本タスクとは無関係の既存の環境問題。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの Cmd+↑ を Finder 準拠の「上位フォルダーへ移動」に割り当てた。handleKey が修飾キーを見ていなかったため、modifiers を受け取るようにし、.upArrow の分岐より前に Cmd 判定を置いて navigateToParent() を呼ぶ。境界条件は既存の navigateToParent をそのまま再利用したので Cmd+← と自動的に揃う。ユニットテスト 4 件(修正を戻すと落ちることを確認済み)に加え、SwiftUI の onKeyPress が Cmd 付きキーを配送するかは自動テストで確かめられないため、Debug ビルドに一時 NSLog を入れて System Events でキーを送り実機で 3 経路を実測した。
<!-- SECTION:FINAL_SUMMARY:END -->
