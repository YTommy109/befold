---
id: TASK-26
title: decodeText が detectEncoding 委譲で全文を二重デコードしている（最大 10MB × 2 パス）
status: To Do
assignee: []
created_date: '2026-07-16 10:55'
updated_date: '2026-07-16 12:11'
labels: []
dependencies:
  - TASK-29
references:
  - BefoldApp/BefoldKit/TextEncoding.swift
  - BefoldApp/BefoldKit/FileReading.swift
priority: medium
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コミット 996742f の単一情報源化で TextEncoding.decodeText（TextEncoding.swift:88-91）が detectEncoding を呼んでから同じ Data を再デコードする構造になった。detectEncoding は BOM なし UTF-8 で String(data:encoding:.utf8) を全文実行して捨て、レガシーエンコーディングでは NSString.stringEncoding の変換結果 convertedString を捨てる。非チャンクパス（DefaultFileReader.readString、上限 10MB）のファイルオープン・再読込ごとに全文デコードが 2 回走る（v1.7.0 は各分岐で変換結果を直接返していた）。BOM あり・UTF-16 ヒューリスティック経路は影響なし。チャンクパスは 8KB プローブのみで軽微。正確性への影響はなし（検証済み）。修正案: detectEncoding が変換済み文字列も返せるようにする、または decodeText 側に直接デコード分岐を残す。単一情報源の設計意図と両立させること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 BOM なし UTF-8 とレガシーエンコーディングのファイルでデコードが 1 パスになっている
- [ ] #2 エンコーディング検出ロジックの単一情報源化（996742f の意図）が維持されている
- [ ] #3 既存の TextEncoding テストがすべて通る
<!-- AC:END -->
