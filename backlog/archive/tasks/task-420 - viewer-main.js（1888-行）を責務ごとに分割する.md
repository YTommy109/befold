---
id: TASK-420
title: 'viewer-main.js（1,888 行）を責務ごとに分割する'
status: To Do
assignee: []
created_date: '2026-08-10 07:28'
updated_date: '2026-08-10 12:58'
labels: []
dependencies:
  - TASK-414
priority: medium
type: chore
ordinal: 507600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/BefoldKit/Resources/viewer-main.js は 1,888 行の単一スクリプトで、モジュール境界を持たないまま次をすべて所有している: ズーム、キーボードスクロール、参照クリック、パス参照の注釈と非同期解決、ダイアグラム単位のズーム、mermaid のロード、markdown-it の設定、検索コントローラ一式、document / scroll / doc-path / chunk-tail / pdf-blob の各状態、7 つの型別レンダラ、チャンク追記、初期化。

対になる viewer.js は既に「純粋ロジック」側として切り出されているが、分割軸が責務ではなくテスト可能性で引かれている。その結果、同じ関心の 2 つの枝が 300 行離れて置かれ、実際に乖離した（TASK-414 の appendChunk と render のモード判定、_renderSource の注釈呼び出し漏れ）。

TASK-414 で表示モード判定の一本化を済ませてから、残りを責務単位へ分ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 viewer-main.js が責務単位のファイルへ分割される（少なくとも 検索 / 参照解決 / ズーム / レンダラ群 / 初期化 が分かれる）
- [ ] #2 同じ関心の判定が 2 箇所に残っていない
- [ ] #3 分割後も viewer.html からの読み込み順が壊れず、既存の Node テストが通る
- [ ] #4 QuickLook 拡張と本体アプリの双方で表示が変わらないことを確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-432.3 へ統合したためアーカイブする。

理由: 本タスクの受け入れ条件 #3 は「viewer.html からの読み込み順が壊れず」であり、古典的グローバルスクリプトの暗黙の読み込み順契約を保ったままの分割を前提にしていた。ADR 0005（docs/adr/0005-bundle-viewer-js-with-esbuild.md, decision-5）で esbuild によるバンドル方式を採ることを決めたため、この前提のままの分割はバンドル導入後にやり直しになる。分割そのものは TASK-432.3 が引き継ぐ（Description に本タスクの内容を転記済み）。
<!-- SECTION:NOTES:END -->
