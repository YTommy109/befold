---
id: TASK-432.3
title: viewer-main を責務ごとのモジュールへ分割する
status: To Do
assignee: []
created_date: '2026-08-10 12:57'
updated_date: '2026-08-10 12:58'
labels: []
dependencies:
  - TASK-432.2
parent_task_id: TASK-432
priority: medium
type: chore
ordinal: 112300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-420 を引き継ぐサブタスク（TASK-420 はこちらへ統合してアーカイブ済み）。モジュール境界を得た後に、責務単位でファイルを分ける。

## TASK-420 から引き継ぐ内容

`viewer-main.js`（1,873 行）はモジュール境界を持たないまま次をすべて所有している: ズーム、キーボードスクロール、参照クリック、パス参照の注釈と非同期解決、ダイアグラム単位のズーム、mermaid のロード、markdown-it の設定、検索コントローラ一式、document / scroll / doc-path / chunk-tail / pdf-blob の各状態、7 つの型別レンダラ、チャンク追記、初期化。

ファイル内のセクション区切りコメントが現状の関心の一覧になっている: `:22` Zoom、`:215` リンク・パス参照クリック、`:302` 表示時のパス参照解決、`:450` Diagram Zoom、`:568` Mermaid、`:640` Markdown-it、`:685` Find、`:1102` Render、`:1538` 型別 DOM ビルダー、`:1800` 初期化。

## TASK-420 から変わった点

TASK-420 の受け入れ条件 #3 は「viewer.html からの読み込み順が壊れず」だった。TASK-432.2 の完了後は読み込み順という暗黙の契約自体が消えているため、この条件は不要になる。代わりに、依存が import で表現され循環していないことを見る。

## 分割の判断基準

`viewer.js` と `viewer-main.js` の現在の境界（純粋ロジック / DOM）は**責務ではなくテスト可能性**で引かれており、同じ関心の 2 つの枝が離れて置かれて実際に乖離した（TASK-414）。分割後は関心ごとに 1 モジュールとし、その中で純粋な部分と DOM に触る部分が同居してよい。テスト可能性はモジュール境界ではなく import で担保する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 viewer-main が責務単位のモジュールへ分割されている（少なくとも 検索 / 参照解決 / ズーム / レンダラ群 / 初期化 が分かれる）
- [ ] #2 同じ関心の判定が 2 箇所に残っていない
- [ ] #3 モジュール間の依存が import で表現され、循環が無い
- [ ] #4 各モジュールが何を担うかを 1 行で言える
- [ ] #5 既存テストが通り、ケース数が減っていない
- [ ] #6 本体アプリと QuickLook 拡張の双方で表示が変わらないことを確認する
<!-- AC:END -->
