---
id: TASK-213
title: SessionRestorer の復元経路と CLI のパス走査ループを共通化する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 02:58'
updated_date: '2026-07-31 07:50'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/befold/App/SessionRestorer.swift
  - BefoldApp/befold-cli/BefoldCLICommand.swift
priority: low
ordinal: 293000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(2026-07-31)の小粒の共通化候補 2 件。(1) SessionRestorer の「保存パスを実在ファイルで絞ってから復元」が openRepository(SessionRestorer.swift:90-99)と restoreLastSession(同 130-147)で「filter(isExistingFile) → urlByPath 構築 → SessionLayout.filtered → restoreTabGroup」の同一シーケンスとして重複。差分は restoreLastSession のみ消えたファイルに noteClosed を打つ点で、onMissing クロージャとして外出しすれば実行タイミングも回数も変わらない。restoreLayout(_:urls:options:onMissing:) に抽出する。(2) BefoldCLICommand.execute の --check / --bookmark ループ(befold-cli/BefoldCLICommand.swift:66-79): 「paths 走査 → コマンド実行 → printResult → 失敗フラグ集約」が同順序で 2 回。runForEachPath に抽出し、全パス実行してから exit 1 という結果集約の一貫性を 1 箇所に固定する。TASK-206(タブグループスナップショット共通化)と SessionRestorer で触る範囲が重なるため、着手順に注意する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 SessionRestorer の 2 復元経路が共通ヘルパーを使い、noteClosed の実行タイミング・回数を含め既存挙動が変わらない
- [x] #2 CLI の check/bookmark ループが共通ヘルパーに統合され、終了コードの集約挙動が変わらない
- [x] #3 既存テストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SessionRestorer に restoreLayout(_:candidates:options:onMissing:) を抽出(実在フィルタ→urlByPath→SessionLayout.filtered→restoreTabGroup を 1 本化)。実在した候補列と復元済みパス集合を返し、openRepository はフォールバック判定に、restoreLastSession は残りファイルの追加オープンに使う。noteClosed は onMissing として渡し、呼ぶ位置(ウィンドウを開く前)と回数を維持する
2. BefoldCLICommand に runForEachPath(printResult:command:) を抽出し、--check / --bookmark の走査・出力・失敗集約を 1 本化(全パス実行後に exit 1 の集約挙動は不変)
3. swift build / swift test / swiftformat --lint
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装:
(1) SessionRestorer.restoreLayout(_:candidates:options:onMissing:) を追加。候補は (レイアウト上のパスキー, 開く URL) の組で受け、キーは呼び出し元が決める(保存済みレイアウトのパス文字列と一致させる必要があるため、ヘルパー内で正規化し直さない)。戻り値 LayoutRestoration は実在候補列(順序保持)と復元済みパスキー集合を持ち、openRepository はフォールバック判定(restoredPaths.isEmpty)に、restoreLastSession はレイアウト外ファイルの追加オープンに使う。noteClosed は onMissing として渡し、実在フィルタ中=ウィンドウを 1 つも開く前という位置と 1 候補 1 回という回数を維持。layoutToRestore が nil の場合は空 SessionLayout を渡すため、従来の「レイアウト無しなら開いた順に開くだけ」と一致する。
(2) BefoldCLICommand.runForEachPath(printResult:command:) を追加し、--check / --bookmark の走査・出力・失敗集約を共通化。短絡評価で実行が飛ばないよう戻り値を一旦 let に受けてから OR する。

テスト: 「復元時に消えていたファイルはウィンドウを開かずセッション記録からも取り除かれる」を SessionRestorerTests に追加(onMissing を落とすと落ちる assertion)。CLI 側の終了コード集約は既存の --check 複数パステスト / --check+--bookmark 併用テストが引き続き担保する。

検証: swift test 906 tests / 125 suites 全通過、swiftformat --lint 指摘なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SessionRestorer の 2 つの復元経路を restoreLayout ヘルパーへ、CLI の --check/--bookmark の走査ループを runForEachPath へ共通化した。noteClosed の実行位置・回数、フォールバック判定、終了コードの集約挙動はいずれも従来どおり。消えたファイルの記録掃除を守るテストを追加し、swift test 906 件全通過・swiftformat --lint 指摘なしで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
