---
id: TASK-253
title: coding_rule.md をレビュー対象(消費者)別に分割しインデックス化する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-01 11:10'
updated_date: '2026-08-02 00:00'
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
- [x] #1 4 ファイルへの分割が完了し、coding_rule.md がインデックスとして全セクションへの到達性を保つ
- [x] #2 review-swift-code / review-swift-tests / quality-loop が分割後の必要ファイルのみを読む構成になり、テストレビューの読み込み行数が概ね半減する
- [x] #3 アーキテクチャ・構成・技術スタックの権威が native-app-design.md に一本化され、CLAUDE.md との同期規定が更新される
- [x] #4 分割後ファイルに依存ディレクティブが付与され、節間参照の断絶がない
- [x] #5 markdownlint-cli2 がパスする
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. coding_rule.md(947行)を消費者別に4分割: docs/dev/rules/product-code.md(Swift規約+JS規約+エラーハンドリング+SwiftLint/SwiftFormatツール), testing.md(テスト規約全体), comments.md(コメント規約 プロダクト/テスト共通), workflow.md(コマンド+コミット+品質チェック+レビュー対応+応答言語)
2. coding_rule.md はインデックス化し、CLAUDE.mdとの関係記述をnative-app-design.md一本化に更新
3. 節間参照の断絶2箇所を修正: JS規約→コメント規約の参照をcomments.mdへのリンクに、コメント規約内のアーキ図/構成ツリー参照をnative-app-design.mdへの参照に変更
4. review-swift-code.md / review-swift-tests.md / quality-loop.md の参照先を分割後ファイルへ更新
5. markdownlint-cli2で検証、コミット
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
結果: 947 行 → インデックス 38 行 + 4 ファイル(product-code 307 / testing 385 / comments 127 / workflow 71)。テストレビュー時の読み込みは 947 行 → 512 行(testing + comments)で 46% 削減、プロダクトレビューは 434 行(product-code + comments)で 54% 削減。
レビューは分割前後の全行の差集合を機械的に取って検証し、内容の欠落は 1 行、重複はゼロと確認された。その 1 行が Important-1(下記)。
修正(aad6e6c):
- Important-1: 分割作業が見出し修正コミット(c4adbdd)より前のスナップショットから行われたため、否定検証節の見出しが修正前の文言に戻っていた(本文は最新のままで、見出しと本文の優先順位がまた食い違う状態)。復元した
- Important-2: product-code.md の「テスト容易性のための可視性」が、分割で testing.md へ移った「テスト対象外」節をベタ参照していた。しかも review-swift-code は product-code.md + comments.md しか読まないため、ルールを適用する側が判断基準に到達できない状態だった。リンク化に加えて判断基準の要約を併記した
- Minor-1: 「前掲」が実際には後方の節を指していた(分割前からの既存問題)。後述へのアンカーリンクに修正
実装者の独自判断 2 件(SwiftLint 閾値表を product-code.md へ / コマンド節を workflow.md へ)はレビューで妥当と確認。quality-loop を 4 ファイル全読みのままとした判断も、プロダクト・テスト双方をレビューし規約自体の改善提案まで行う性質上、対象を絞ると判断材料を失うため妥当と確認された。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
docs/dev/coding_rule.md(947 行)をレビュー対象(消費者)別に 4 分割し、coding_rule.md をインデックス(38 行)として存置した。product-code.md / testing.md / comments.md / workflow.md の構成で、review-swift-code は前 2 者、review-swift-tests は testing + comments を読む。テストレビューの読み込みは 46%、プロダクトレビューは 54% 削減。
あわせてアーキテクチャ図・技術スタック・プロジェクト構成の権威を native-app-design.md へ一本化し、coding_rule.md が自分を権威と宣言していた矛盾を解消した。
分割で壊れやすい節間参照は、レビューがアンカー・相対リンク全 15 本の解決を確認。分割元が見出し修正前のスナップショットだったことによる 1 行の回帰と、別ファイルへ移った節へのベタ参照 1 件を修正済み。
検証: markdownlint-cli2 0 issues、分割前後の全行差集合による内容の欠落・重複チェック。レビュー承認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
