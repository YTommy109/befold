---
id: TASK-484.3
title: Markdown を読む立場の人にとっての利点を整理する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-14 13:06'
updated_date: '2026-08-16 01:03'
labels: []
milestone: m-1
dependencies: []
parent_task_id: TASK-484
priority: high
type: task
ordinal: 708000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイトのコピーを書き直す前に、材料を確定させる棚卸しタスク。成果物は文章そのものではなく、訴求に使える利点の一覧。

befold は設計レビュー・コードレビューの多いエンジニア向けに開発しているが、エンジニアでなくても Markdown を読む立場の人（ライター・企画・レビュアーなど）にとっての利点がある。現在のサイトはこの層に向けた入口を持たない。

実装済みで、この層に効くと考えられるもの（このタスクで取捨選択する）:

- 保存すると 0.2 秒で描画が更新される。エディタの atomic save やリネームにも追従する
- mermaid のコードブロックがそのまま図として描かれる。構文エラーは詳細付きで表示される
- GitHub と同じ見た目（github-markdown-css + markdown-it）。URL の自動リンク化とコードのハイライト付き
- 見出しに GitHub 互換の ID が付き、文書内のアンカーリンクが動く
- 本文中のファイルパスが、実在するものだけリンクになりクリックで開ける
- ローカル画像が表示される
- 本文内検索（`⌘F`、大文字小文字・単語一致・正規表現）
- Finder で Space を押すだけのプレビュー（QuickLook 拡張）
- 印刷・PDF 書き出し（File > Print…）
- 100MB までの Markdown が段階描画で開ける
- スクロール位置・ズーム倍率をファイル単位で記憶し、タブ構成も復元される
- Shift_JIS / EUC-JP の自動判別

**書いてはいけないもの（未実装）**: 目次・アウトライン表示は存在しない。編集機能・エクスポート（SVG/PNG）はスコープ外。

各項目について、実装の裏付け（`file:line` または `docs/dev/native-app-design.md` の該当箇所）を添えること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 この層に向けて訴求する利点が、優先順位を付けた一覧として整理されている
- [x] #2 各項目に実装の裏付けが添えられている
- [x] #3 未実装・スコープ外のものが混入していない
- [x] #4 整理結果が docs/superpowers/specs/ に日付付きのスナップショットとして残り、冒頭バナーが付いている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 既存 specs の命名・バナー形式を確認する
2. Description の 12 項目の実装裏付け（file:line / native-app-design.md 該当箇所）を Explore サブエージェントで並列収集する
3. 裏付けの取れた項目だけを、非エンジニア読者への効き方で優先順位付けする
4. docs/superpowers/specs/2026-08-16-markdown-reader-benefits-design.md としてバナー付きで保存する
5. markdownlint を通し、AC を検証して完了処理・コミットする
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
裏付け収集は Explore サブエージェント 2 本（レンダリング系 6 項目 / アプリ挙動系 6 項目）で並列実施し、報告された file:line のうち主要 8 箇所を sed -n で実測して一致を確認した。12 項目すべて実装あり。判明した制約（コピー確定時の言い過ぎ防止として文書の各「注意」に記載）: (1) URL 自動リンクは scheme 付きのみ（markdown.js:125 fuzzyLink:false）、(2) PDF は印刷パネルの「PDF として保存」経由で専用エクスポートではない、(3) 100MB 上限は Markdown 等チャンク可能種別のみで mmd/svg/html は 50MB、(4) QuickLook は quickLookRestricted プリセットで検索・パスリンク・画像埋め込みが無効。目次・アウトライン機能の不在は rg で確認（ヒットは SwiftUI OutlineGroup へのコメント言及のみ）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
非エンジニアの Markdown 読者（ライター・企画・レビュアー）向けの利点 12 項目を優先度 A（入口: QuickLook・GitHub の見た目・0.2 秒更新・mermaid）/ B（作業支援: 検索・アンカー・ローカル画像・印刷/PDF）/ C（困らない系: 復元・100MB・文字コード・パスリンク）に整理し、docs/superpowers/specs/2026-08-16-markdown-reader-benefits-design.md にバナー付きスナップショットとして保存した。全項目に file:line の裏付けを付け、主要 8 箇所は実測で一致確認。未実装（目次・編集・SVG/PNG エクスポート）は「書いてはいけないもの」節に分離し、TASK-484.4 への申し送り（新規材料 6 項目と言い過ぎ防止の制約）を末尾に記載した。
<!-- SECTION:FINAL_SUMMARY:END -->
