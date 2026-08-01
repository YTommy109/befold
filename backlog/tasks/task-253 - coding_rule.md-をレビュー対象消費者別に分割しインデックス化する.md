---
id: TASK-253
title: coding_rule.md をレビュー対象(消費者)別に分割しインデックス化する
status: To Do
assignee: []
created_date: '2026-08-01 11:10'
labels: []
dependencies:
  - TASK-252
priority: medium
type: docs
ordinal: 450200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
docs/dev/coding_rule.md(826 行/58KB)は主にサブエージェント(review-swift-code / review-swift-tests スキル、/quality-loop の 3 ラウンド)が全文読みしているが、テストレビューに必要なのは約 400 行で、毎回 2 倍のトークンを消費している。レビュー対象(消費者)別に分割する。
分割構成:
- docs/dev/rules/product-code.md: Swift コーディング規約 + AppKit/SwiftUI 混在 + WKWebView/JS ブリッジ + 共通化・単一情報源・DI + 責務分離 + エラーハンドリング(review-swift-code が読む)
- docs/dev/rules/testing.md: テスト規約全体(Swift Testing + Jest + 共有ヘルパー + Unit/Integration 分離 + TASK-252 の追記分)(review-swift-tests が読む)
- docs/dev/rules/comments.md: コメント・ドキュメンテーション規約(プロダクト/テスト共通なので独立させ、両スキルが読む)
- docs/dev/rules/workflow.md: コミット規約 + 品質チェック手順 + レビュー対応方針 + 応答言語(メインエージェント向け)
- docs/dev/coding_rule.md: 各ファイルへのリンク集(インデックス)として存置。既存参照パス(スキル・コマンド・歴史的 plans/specs・development.md)を壊さない
あわせて解消する二重管理: アーキテクチャ図・プロジェクト構成・技術スタックが coding_rule.md(権威元を自称)と native-app-design.md(.claude/CLAUDE.md が単一情報源と宣言)と CLAUDE.md の 3 箇所で矛盾した権威宣言になっている。概要系セクションは native-app-design.md への参照に一本化し、coding_rule.md 冒頭の「CLAUDE.md との関係」記述も更新する。
参照元の更新(同じ diff 内):
- .claude/skills/review-swift-code.md / review-swift-tests.md: 読み込み先を分割後ファイルへ(product-code.md + comments.md / testing.md + comments.md)
- .claude/commands/quality-loop.md: 全文投入を必要ファイルの組み合わせへ
- 分割後の各ファイルに Markdown 依存ディレクティブ(derived-from / supersedes)を付け、dagayn グラフで追跡可能にする
- coding_rule.md 内の相互参照(「前掲」「上の表」等の節間参照)が分割で壊れないよう読み合わせる
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 4 ファイルへの分割が完了し、coding_rule.md がインデックスとして全セクションへの到達性を保つ
- [ ] #2 review-swift-code / review-swift-tests / quality-loop が分割後の必要ファイルのみを読む構成になり、テストレビューの読み込み行数が概ね半減する
- [ ] #3 アーキテクチャ・構成・技術スタックの権威が native-app-design.md に一本化され、CLAUDE.md との同期規定が更新される
- [ ] #4 分割後ファイルに依存ディレクティブが付与され、節間参照の断絶がない
- [ ] #5 markdownlint-cli2 がパスする
<!-- AC:END -->
