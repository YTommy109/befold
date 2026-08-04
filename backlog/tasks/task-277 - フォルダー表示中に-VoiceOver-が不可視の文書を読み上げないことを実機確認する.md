---
id: TASK-277
title: フォルダー表示中に VoiceOver が不可視の文書を読み上げないことを実機確認する
status: To Do
assignee: []
created_date: '2026-08-04 01:32'
labels:
  - accessibility
  - bug
dependencies: []
priority: medium
ordinal: 467000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-271（ADR 0002 段 2）の受け入れ条件 #3 を分離したもの。実装・テストは TASK-271 で完了済みで、残るのは VoiceOver を実際に有効化しての確認だけ。

## 背景
WKWebView は AppKit/WebKit 側で独自のアクセシビリティ木を公開するため、SwiftUI の accessibilityHidden(true) が必ずしも刈り取らない。フォルダー一覧の表示中に VO カーソルが一覧を通り越して不可視の文書を読み上げる懸念がある。

## 実測済みの事実（TASK-271）
AX ツリー上はフォルダー提示中に web area が現れない（webAreas=0）。VoiceOver はこの木を辿るため到達しない見込み。ただし VoiceOver を実際に ON にしての確認は未実施（読み上げが始まり環境を占有するため）。

## 手順
1. dev ビルドを起動し、フォルダーを開く
2. Cmd+F5 で VoiceOver を有効化
3. VO カーソル（Ctrl+Option+矢印）でフォルダー一覧を端まで辿る
4. 不可視の文書の内容が読み上げられないことを確認

読み上げが起きた場合は、WebView 側の accessibilityElement 制御（NSView.setAccessibilityElement(false) 等）を検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 VoiceOver を有効にした実機で、フォルダー表示中に VO カーソルが不可視の文書へ到達せず、その内容が読み上げられない
<!-- AC:END -->
