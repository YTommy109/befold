---
id: TASK-538.4
title: 記事本文を書いて公開する
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-22 13:06'
updated_date: '2026-08-23 07:40'
labels: []
milestone: m-10
dependencies:
  - TASK-538.1
  - TASK-538.2
  - TASK-538.3
parent_task_id: TASK-538
priority: medium
ordinal: 786000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-538.1 の器に、TASK-538.2 のテンプレートと TASK-538.3 の素材を使って記事本文を載せる。

## 記事の骨子（案）

1. **掴み**: 家族に渡す説明が 3 行で済む。『領収書をもらったら iPhone のファイルアプリでスキャン。名前も日付も気にしなくていい』
2. **困りごと**: 医療費控除は 1 年分の領収書が貯まるが、集計は年に 1 回しかやらない。溜めると読めない、都度やると続かない
3. **仕組み**: Inbox に投げるだけ → 月末に Claude へ依頼 → TSV に追記され receipts/ へリネーム移動される。プログラムは 1 行も書いていない
4. **befold が効くところ**: (a) TSV を Numbers で開かずに表で見る——開いて保存し直すと先頭ゼロや日付形式が変わる問題を避ける (b) 集計表の receipt 列から領収書 PDF をすぐ確かめる (c) LLM 向けの規約文書（CLAUDE.md / README.md）を人が読む
5. **持ち帰り**: テンプレートと、領収書の 5 年保存義務の注意
6. **導線**: befold のダウンロード

## 免責・注意の表現

税務の手続きに関わる内容なので、『最終的な判断は国税庁の情報と税務署に確認すること』の旨を入れる。国税庁ページへの出典リンクは TASK-538.2 のテンプレート側にもあるが、記事本文にも置く。

## 触れないこと

- 差分表示（題材が git 管理外なので使えない）
- 実在の家族構成・医療機関
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 記事が公開され、紹介サイトから到達できる
- [x] #2 befold の見せ場 3 つが、それぞれスクリーンショット付きで記事に登場する
- [x] #3 テンプレート（CLAUDE.md / README.md）を読者が持ち帰れる導線がある
- [x] #4 税務判断についての注意書きと国税庁への出典リンクがある
- [x] #5 記事末尾に befold のダウンロード導線がある
- [ ] #6 公開後、befold analytics のダッシュボードで記事のアクセス数が実際に計上されていることを確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-541（記事のドラフト管理）が入れば、本文を書きかけでコミットしてレビューを受けられる。着手時に 541 の状態を確認すること。

## 実装（2026-08-23）

`site/src/views/article-medical-expenses.tsx` の骨子を本文に置き換え、`ARTICLES` から `draft: true` を消して公開した。構成は Description の骨子どおり——掴み（家族に渡す 3 行）→ 困りごと（溜めると読めない／都度は続かない）→ 仕組み（月末の依頼 1 行と、その結果起きる 4 手順）→ befold の見せ場 3 つ（TSV を表計算ソフトで開かずに読む／集計表から領収書 PDF へ／規約文書を人が読む。それぞれスクリーンショット付き）→ 持ち帰り（テンプレート 2 本）→ 注意（5 年保存・区分・befold は読む専用）→ 免責と国税庁リンク 2 本 → ダウンロード導線。

数字・氏名・医療機関名はすべて TASK-538.3 の架空データ（北原家）由来で、実在のものは無い。差分表示には触れていない（題材が git 管理外）。

### 判断

- **見せ場 3 つは h4 にした。** 「読み違いに気づけるのは人だけ」という h3 の下にぶら下がる 3 つの手段であって、並列の節ではないため。`.article-body h4` と `.article-body blockquote` の CSS を `style.css` に追加した（どちらも既存記事が使っていなかった要素）
- **ダウンロード導線は `DOWNLOAD_PATH` / `REQUIRED_OS` を再利用**（`views/shared.tsx`）。LP と同じ相対パスなので、配布サイトのオリジンでもそのまま動く。共有コンポーネント化はしていない（既存記事に導線が無く、全記事へ入れるかは別の判断）
- 免責は本文の `.listing-note` に置き、国税庁 2 本のリンクをテンプレート側と同じものにした

### 検証（2026-08-23）

- `npm test`（site/）: 13 ファイル / 386 件すべて成功
- `npm run lint`（oxlint --type-aware）: 指摘 0 件。`npm run format:check`: 整形ずれ 0 件（1 回 `npm run format` を通した後）
- 受入条件の確認は使い捨てのテスト（`test/tmp-verify-538-4.test.ts`、確認後に削除）で Worker のレスポンスを実際に取って行った。5 件すべて成功:
  - `/usecases/medical-expenses` と `/en/usecases/medical-expenses` が 200 で、`draft-notice` と `noindex` を含まず、スクリーンショット 3 枚・テンプレート 2 本・国税庁リンク 2 本・`href="/download"` をすべて含む（AC #1・#2・#3・#4・#5）
  - 記事一覧（`/usecases` と `/en/usecases`）に記事へのリンクが出る（AC #1）
  - ドラフト URL `/drafts/medical-expenses` は 404 になり、`sitemap.xml` に公開 URL が載る
  - `/templates/medical-expenses/{README,CLAUDE}.md` が 200 で配信される（AC #3）

### AC #6 は未達（デプロイ待ち）

公開後の analytics 計上確認は、この変更が本番へデプロイされてからでないと実施できない。マージ後に befold analytics のダッシュボードで `/usecases/medical-expenses` のアクセスが計上されていることを確認する。**このタスクはそれまで完了にしない。**
<!-- SECTION:NOTES:END -->
