---
id: TASK-292
title: About ダイアログのテキストを選択・コピーできるようにする
status: Done
assignee: []
created_date: '2026-08-04 12:17'
updated_date: '2026-08-04 12:37'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 491000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
About ダイアログに表示しているバージョン番号などのテキストを、マウスで選択してコピーすることができない。不具合報告やリリースの確認でバージョン文字列を手で書き写す必要があり、打ち間違いのもとになる。

AboutView は SwiftUI の Text で表示しており、既定では選択できない（`BefoldApp/befold/App/AboutView.swift`。バージョンは AppVersion.resolvedWithBuild 由来）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 About ダイアログのバージョン文字列をマウスで選択してコピーできる
- [x] #2 コピーした内容が画面表示と同じ文字列になる（余計な装飾やラベルが混ざらない）
- [x] #3 ダイアログの他のテキスト（著作権表記など）についても、選択可否の方針が統一されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. AboutView の情報テキスト（バージョン・著作権表記）に .textSelection(.enabled) を付ける\n2. Link は従来どおりクリック可能なまま、方針として「情報テキストは選択可、リンクはリンク」に統一\n3. ビルド + テストで回帰なしを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AboutView の情報テキスト用 VStack（バージョン + Copyright 行）に .textSelection(.enabled) を付けた。Link はそのままリンクとして残し、方針は「情報テキストは選択可・リンクはリンク」で統一。

検証: swift build / swift test（1074 tests 全通過）/ swiftformat 差分なし / swiftlint 該当ファイル 0 件。xcodebuild で .app を作り実機起動して About を開き、AX 上で表示文字列が '1.11.7-dev.4 (1176)' のみであること（余計なラベルが混ざらないこと）を確認。

未検証: 実際のドラッグ選択そのもの。CGEvent の合成ドラッグでは選択できず、対照として既に選択可能な WKWebView 本文でも同じ手順で選択・コピーできなかったため、合成イベント側の制約と判断した（この否定結果は実装の反証にならない）。ドラッグ選択の可否は手動確認が必要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AboutView の情報テキスト（バージョン・著作権表記）をまとめた VStack に .textSelection(.enabled) を付け、選択・コピーできるようにした。Link はリンクのまま残し、「情報テキストは選択可・リンクはリンク」で方針を統一。検証は swift build / swift test（1074 tests 通過）/ swiftformat 差分なし / swiftlint 0 件に加え、xcodebuild した .app を起動して About を開き、AX 上の表示文字列が '1.11.7-dev.4 (1176)' のみであることを確認。ドラッグ選択と Cmd+C はユーザーによる手動確認で成功。
<!-- SECTION:FINAL_SUMMARY:END -->
