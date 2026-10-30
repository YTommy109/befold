---
id: TASK-902
title: 検索ハイライトを Custom Highlight API に一本化し、`<mark>` 挿入経路を削除する
status: To Do
assignee: []
created_date: '2026-10-30T10:20:00Z'
updated_date: '2026-10-30T10:32:00Z'
labels: []
dependencies:
  - TASK-903
priority: low
ordinal: 862000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #741（外部コントリビュータ、大きな CSV の描画・検索の高速化）は、検索ハイライトを CSS Custom Highlight API（`StaticRange` + `::highlight`）で描く経路を追加したが、適用対象を CSV の表・ソースに限定している（`find-scan.ts` の `walk` が `root.matches(".csv-body, .code-body:has(code.csv-source)")` で判定）。そのため Markdown・ソースコード・差分は従来の `<mark>` を DOM へ挿入する経路を通り、二つの経路が日常的に並走する。片方にしか無い不具合（現在位置の付け替え・スクロール・再描画後の索引破棄など）が出やすい形である。

最低対応 OS を macOS 14.2 へ上げれば（TASK-903）API が常に使えるため、形式による分岐だけでなく `<mark>` 経路そのもの（`clearMarks` の unwrap / normalize、`matchScope` の `extractContents` / `insertNode`、`pruneEmptyAncestors`、`supportsHighlights` による判定、`mark.mmd-find-match` の CSS）を削除でき、検索は 1 本の経路になる。大きなソースコード・差分でも DOM 書き換えが消えて速くなる。また `<mark>` を差し込めないため検索対象外にしている mermaid の SVG（`find-scan.ts` の `skipTags`）を対象にできる可能性がある（WebKit が SVG テキストに `::highlight` を描くかは未確認）。

注意点: PR #741 の `find-highlight.ts` の `updateNativeHighlights` は、画面付近のヒットだけを登録するために「文書順のヒットは画面上でも上から下へ並ぶ」前提で二分探索する。CSV・code-table では成り立つが、Markdown では閉じた `<details>` の中身の矩形が 0 になるなどで崩れ、見えているヒットが塗られない恐れがある。

現在位置の印付けはジャンプバーと共通の `navigation.ts` の `moveCurrentHighlight`（要素へ class を付ける方式）を使っている。検索側だけが Highlight API に移ると、この共通経路から外れる点も設計時に扱う。

着手条件: PR #741 がマージされていること（未マージなら、この経路自体が main に無い）と、TASK-903 の完了。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 全形式（CSV・Markdown・ソースコード・差分）の検索が `<mark>` を DOM に挿入せず、`<mark>` 挿入経路のコードと CSS が削除されている
- [ ] #2 経路の選択が形式（クラス名・要素の一致）にも API の有無にも依存しない
- [ ] #3 Markdown で閉じた `<details>` など画面上の並びが文書順と一致しない内容でも、表示されているヒットがすべてハイライトされる（回帰テストあり）
- [ ] #4 大量ヒット（数万件以上）のソースコードで、1 打鍵の検索時間が PR #741 の CSV と同程度に収まることを実測で確認し、数値を Notes に残す
- [ ] #5 mermaid の SVG テキストを検索対象に含めるかを実測のうえ決め、結果を Notes に残す
- [ ] #6 `docs/dev/` の検索の仕様記述を新しい経路に合わせて更新する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-30: PR #741 は main へ squash マージ済み（637e6faf）。残る着手条件は TASK-903 の完了のみ。
<!-- SECTION:NOTES:END -->
