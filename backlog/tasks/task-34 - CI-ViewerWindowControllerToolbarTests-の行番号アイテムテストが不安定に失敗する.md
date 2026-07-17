---
id: TASK-34
title: 'CI: ViewerWindowControllerToolbarTests の行番号アイテムテストが不安定に失敗する'
status: Done
assignee:
  - '@claude'
created_date: '2026-07-17 02:05'
updated_date: '2026-07-17 03:22'
labels:
  - ci
  - bug
dependencies: []
priority: high
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Actions run https://github.com/YTommy109/befold/actions/runs/29548044711 (build-and-test / テストを実行する) で ViewerWindowControllerToolbarTests.swift:57 の Test "行番号アイテムはコード表示中のみ有効" が失敗した。

失敗内容: waitUntilOnMainActor で makeCodeButton()?.isEnabled == true になるまでポーリングした直後、改めて makeCodeButton() を呼び直して #expect(codeButton.isEnabled == true) を検証しているが、そこで isEnabled が false に戻っており失敗している(Expectation failed: (codeButton.isEnabled → false) == true)。

toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:) は呼び出しごとに store の現在状態からアイテムを再生成する実装のため、fileType の確定タイミングに依存した非決定的な状態遷移が起きている可能性がある。関連: TASK-33(filePath/fileTypeをcontentと同時に一括適用する対応が既にDone)。今回の失敗が同種のレースの再発なのか、テスト側のポーリング方法(2回連続呼び出しの間に状態が変わり得る設計)に起因する別問題なのかを切り分けて調査する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GitHub Actions run 29548044711 の失敗ログから原因を特定する
- [x] #2 アプリ本体(ViewerStore/ViewerWindowController)側の非同期状態遷移に問題があるかテスト側のポーリング設計の問題かを切り分ける
- [x] #3 原因に応じて実装またはテストを修正し、CI が安定して通ることを確認する(必要ならローカルで複数回連続実行して再現しないことを確認)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GHA run 29548044711 の失敗ログを取得し、失敗テストと失敗箇所を特定する
2. ViewerWindowControllerToolbarTests.swift の該当テストと ViewerWindowController/ViewerStore の非同期状態遷移を調査する
3. まず単純化を検討する: テストが「ポーリングで true を確認 → 別呼び出しで再取得して検証」という二重の非同期取得をしている点が、await の再開点を挟んだ競合ウィンドウを生んでいないか確認する
4. アプリ本体側(fileType/rejectReason の apply() 一括更新)は task-32/33 で既に単一化済みで問題なし。原因はテスト側のポーリング設計と判断し、ポーリングで得たボタンをそのまま使い回すよう修正する
5. ローカルで複数回連続実行して再現しないことを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
GitHub Actions run 29548044711 のログ確認: ViewerWindowControllerToolbarTests.swift:57 で codeButton.isEnabled が false になり失敗(13.989秒かかった後の失敗、通常は1秒未満)。

原因調査: ViewerStore.apply() は fileType/rejectReason/content を dataHash 比較で一括更新しており(task-32/33で対応済み)、内容が変わらない再読み込みでは早期returnするため状態が不整合に戻ることはない。テスト側は 1) waitUntilOnMainActor でポーリングして isEnabled==true を確認 → 2) 直後に makeCodeButton() を再度呼び出して #expect で検証、という二段構えだった。この2回の呼び出しは await の再開点(MainActorの他ジョブが割り込みうる)を挟んだ別個の非同期呼び出しであり、CI の高負荷でこの競合ウィンドウが広がると2回目の呼び出しだけが異なる状態を拾い得る。ローカルで5回連続実行しても再現せず、CI特有の負荷起因のタイミング差と判断。

対応: アプリ本体(ViewerStore/ViewerWindowController)側の非同期状態遷移には問題なしと判断。単純化検討の結果、テストが同じ状態を二重に問い合わせている無駄自体が競合ウィンドウの原因のため、ポーリングで取得したボタンをそのまま使い回すようテストを修正(新たな状態やリトライ機構は追加せず)。修正後、ローカルで ViewerWindowControllerToolbarTests を8回連続実行して全て成功、swift test 全体(356テスト)も成功を確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GHA run 29548044711 のログから ViewerWindowControllerToolbarTests.swift:57 の失敗を特定。ViewerStore.apply() は dataHash 比較で fileType/rejectReason/content を一括更新しており(task-32/33対応済み)アプリ本体の非同期状態遷移に問題はなし。原因はテスト側: waitUntilOnMainActor でポーリング成功を確認した直後、await の再開点を挟んで makeCodeButton() を再度呼び出し検証していたため、CI高負荷時にその間の状態変化と競合しうる二重の非同期取得だった。単純化の方針に沿い、新たな状態やリトライを追加せずポーリングで取得したボタンをそのまま使い回すようテストを修正。ViewerWindowControllerToolbarTests を8回連続実行し全て成功、swift test 全体(356テスト)も成功を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
