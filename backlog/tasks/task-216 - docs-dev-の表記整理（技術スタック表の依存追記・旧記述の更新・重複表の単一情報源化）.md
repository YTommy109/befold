---
id: TASK-216
title: docs/dev の表記整理（技術スタック表の依存追記・旧記述の更新・重複表の単一情報源化）
status: To Do
assignee: []
created_date: '2026-07-31 03:13'
labels: []
dependencies: []
priority: low
ordinal: 296000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コミット 9a555c9 のコードレビュー指摘（CONFIRMED）のうち、実害は小さいが一貫性を損なうクリーンアップ 3 件。

1. docs/dev/native-app-design.md:196 — 自動アップデート節は Sparkle 2 前提に書き換えられたのに、技術スタック表に Sparkle 2 が載っていない（DOMPurify も同様）。依存棚卸しやセキュリティレビューでこの表を情報源にすると実際にリンクされている外部フレームワークを見落とす。
2. docs/dev/native-app-design.md:215 — テスト方針節の「Updates/ 配下の各コンポーネント…を befoldTests/ で網羅する」が自前アップデータ時代の記述のまま。実態は Updates/ は UpdateChannel.swift 1 ファイル、テストも UpdateChannelTests.swift のみ。
3. docs/dev/viewer-rendering-dataflow.md:66 — 「viewer.html の JS 分岐」の type→ビルダー表が、14-31 行の FileType 表の「JS 描画関数」列とほぼ同一のマッピングを二重記載している。リネームや種別追加時に片方だけ更新されると矛盾するため、片方から描画関数列を落として相互参照にし単一情報源化する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 native-app-design.md の技術スタック表に Sparkle 2 と DOMPurify が記載されている
- [ ] #2 native-app-design.md のテスト方針節が Updates/ の現状（UpdateChannel のみ）と一致している
- [ ] #3 viewer-rendering-dataflow.md の type→描画関数マッピングが単一情報源になっている（もう一方は相互参照）
<!-- AC:END -->
