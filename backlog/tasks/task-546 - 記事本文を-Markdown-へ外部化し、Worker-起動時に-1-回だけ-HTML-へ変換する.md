---
id: TASK-546
title: 記事本文を Markdown へ外部化し、Worker 起動時に 1 回だけ HTML へ変換する
status: To Do
assignee: []
created_date: '2026-08-23 08:32'
updated_date: '2026-08-23 08:33'
labels: []
milestone: m-10
dependencies: []
type: enhancement
ordinal: 795000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 動機

記事本文が TSX に埋め込まれており、文章として読み返せない。`<T lang={lang} ja="…" en="…" />` が 1 段落ごとに入れ子で並ぶため、校正するにはブラウザで開くしかない。実測: `site/src/views/article-medical-expenses.tsx` は本文 1 本で 300 行超、うち大半が JSX の入れ子。

## 決定済みの方針（B: 起動時に 1 回変換）

本文を `.md` として外に出し、**Worker のモジュール読み込み時に 1 回だけ** HTML へ変換する。リクエストごとの変換は行わない。

TASK-538.1 の設計レビュー項目 6「記事本文を Markdown からパースして描く形にしない。リクエストごとにパースが走る」は**この形なら満たされる**（パースはコールドスタート時の 1 回で、リクエスト経路に乗らない）。当時の決定を覆すものではない。

ビルド時変換（生成物を `.ts` として吐く案）は採らない。生成物とビルド手順が増え、走らせ忘れると古い記事が黙って配信されるため。代償として Markdown パーサが Worker のバンドルに乗ることを受け入れる。

**「原稿置き場を作って、レビュー後に TSX へ取り込む」形は採らない。** 取り込みが手作業のコピーになり、同じ文章が .md と .tsx の 2 箇所に残る。`.md` が唯一の正で、TSX 側に本文を持たない形にする。

## 決めること

- **本文ファイルの置き場と命名**（`site/content/<slug>.<lang>.md` を想定）。`lib/articles.ts` の `slug` と対応させる
- **`.md` の読み込み方**。wrangler / esbuild の text モジュール（`wrangler.toml` の `rules`）で import するか、他の手段か
- **パーサの選定**。befold 本体は markdown-it を同梱している（`BefoldApp/BefoldKit/Resources/`）。同じものを使えば「befold で読んだ原稿と、サイトで公開される記事が同じ見た目になる」性質が付く。バンドルサイズと合わせて判断する
- **素の Markdown で書けない部品の扱い**。現在の記事は次を使っている。生の HTML を書くか、短い記法を用意するかを決める
  - 言語ごとに別画像（`usecase-medical-scan-{ja,en}.png`）
  - `figure class="article-shots"` / `.portrait`
  - ダウンロードボタン（`DOWNLOAD_PATH` と `REQUIRED_OS` を参照する。URL をベタ書きさせない方法が要る）
  - `p class="listing-note"` の注記
- **生の HTML を通すかどうか**。本文は自分たちが書くもので外部入力ではないため通してよいが、その前提を doc コメントに明記する
- **ja / en が揃っていることの担保**。現在は `<T ja= en=>` が構造的に両方を強制しているが、ファイルを分けると片方だけ更新できてしまう。テストで落とす（最低でも「公開記事は両言語のファイルが存在する」）

## 残す部分

記事の枠（見出し・日付・パンくず・ドラフトの断り）と `ARTICLES` のメタデータは TSX のまま。外部化するのは本文だけ。

## 移行対象

既存の 2 記事（`article-ai-code-review.tsx` / `article-medical-expenses.tsx`）を同じタスクで移行し、`ARTICLE_BODIES` の対応表が要らなくなるならそれも畳む。片方だけ移行して 2 つの方式が並ぶ状態を残さない。

## 着手前

**`/review-design` を 1 回通してから実装に入る**（本文の持ち方を変え、記事追加の経路を変える変更のため。CLAUDE.md「実装着手前の設計レビュー」に該当）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 記事本文が .md ファイルにあり、TSX 側に本文の文章が残っていない
- [ ] #2 Markdown から HTML への変換がリクエストごとに走らない（モジュールスコープで 1 回だけ実行されることをテストまたはコードで示す）
- [ ] #3 既存 2 記事が両方とも新しい方式へ移行され、TSX 直書きの記事が残っていない
- [ ] #4 言語ごとに別の画像・ダウンロードボタン・注記が、移行前と同じ HTML で出る（ja / en とも）
- [ ] #5 公開記事が両言語の本文ファイルを持つことをテストが担保する
- [ ] #6 記事を 1 本足す手順が README なり doc コメントなりに書かれている
- [ ] #7 site のテスト・lint・整形チェックが通り、記事ページのレスポンスが移行前と同じ内容を返す
<!-- AC:END -->
