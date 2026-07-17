---
id: TASK-34
title: 'CI: ViewerWindowControllerToolbarTests の行番号アイテムテストが不安定に失敗する'
status: To Do
assignee: []
created_date: '2026-07-17 02:05'
labels:
  - ci
  - bug
dependencies: []
priority: high
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Actions run https://github.com/YTommy109/befold/actions/runs/29548044711 (build-and-test / テストを実行する) で ViewerWindowControllerToolbarTests.swift:57 の Test "行番号アイテムはコード表示中のみ有効" が失敗した。

失敗内容: waitUntilOnMainActor で makeCodeButton()?.isEnabled == true になるまでポーリングした直後、改めて makeCodeButton() を呼び直して #expect(codeButton.isEnabled == true) を検証しているが、そこで isEnabled が false に戻っており失敗している(Expectation failed: (codeButton.isEnabled → false) == true)。

toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:) は呼び出しごとに store の現在状態からアイテムを再生成する実装のため、fileType の確定タイミングに依存した非決定的な状態遷移が起きている可能性がある。関連: TASK-33(filePath/fileTypeをcontentと同時に一括適用する対応が既にDone)。今回の失敗が同種のレースの再発なのか、テスト側のポーリング方法(2回連続呼び出しの間に状態が変わり得る設計)に起因する別問題なのかを切り分けて調査する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GitHub Actions run 29548044711 の失敗ログから原因を特定する
- [ ] #2 アプリ本体(ViewerStore/ViewerWindowController)側の非同期状態遷移に問題があるかテスト側のポーリング設計の問題かを切り分ける
- [ ] #3 原因に応じて実装またはテストを修正し、CI が安定して通ることを確認する(必要ならローカルで複数回連続実行して再現しないことを確認)
<!-- AC:END -->
