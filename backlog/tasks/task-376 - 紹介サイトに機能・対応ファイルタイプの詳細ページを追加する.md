---
id: TASK-376
title: 紹介サイトに機能・対応ファイルタイプの詳細ページを追加する
status: To Do
assignee: []
created_date: '2026-08-08 11:47'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 615750
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在の紹介サイト（site/）は `/` の 1 ページのみで、機能の記述も LP 内の「機能」セクションに要約が並ぶだけになっている。そのため「Mermaid ビューア mac」「.mmd プレビュー」のような具体的なロングテール検索や、LLM 経由での参照に対して、拾われる語が不足している。

対応ファイルタイプ・機能・キーボードショートカット・FAQ を網羅した詳細ページを 1 枚追加し、検索と AI 双方からの入口を増やす。

方針:
- AI 専用ページ（llm.txt 等）ではなく、人間が読んで有用な通常ページとして作る。薄いコンテンツ扱いを避けるため。
- 既存の LP（`site/src/views/landing.tsx`）はコンバージョン用としてそのまま残し、詳細は新ページへ内部リンクする。
- LP と同じく日英併記とする。
- 対応ファイルタイプ表は BefoldKit の `FileType` が単一の情報源。ページに手書きした一覧は実装とずれるため、生成するか、ずれたら落ちるテストで担保する。

参考: TASK-360 で JSON-LD / robots.txt / sitemap.xml を導入済み。新ページもその仕組みに載せる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 詳細ページが公開ルートとして配信される（機能一覧・対応ファイルタイプ表・キーボードショートカット・FAQ を含む）
- [ ] #2 ページの本文が LP と同じく日英併記になっている
- [ ] #3 対応ファイルタイプ表が BefoldKit の FileType 定義とずれた場合に落ちるテストがある（または表が FileType から生成されている）
- [ ] #4 FAQ セクションに FAQPage の JSON-LD が出力される
- [ ] #5 sitemap.xml に新ページの URL が含まれる
- [ ] #6 LP から詳細ページへの内部リンクがある
<!-- AC:END -->
