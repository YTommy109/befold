---
id: TASK-484.3
title: Markdown を読む立場の人にとっての利点を整理する
status: To Do
assignee: []
created_date: '2026-08-14 13:06'
labels: []
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
- [ ] #1 この層に向けて訴求する利点が、優先順位を付けた一覧として整理されている
- [ ] #2 各項目に実装の裏付けが添えられている
- [ ] #3 未実装・スコープ外のものが混入していない
- [ ] #4 整理結果が docs/superpowers/specs/ に日付付きのスナップショットとして残り、冒頭バナーが付いている
<!-- AC:END -->
