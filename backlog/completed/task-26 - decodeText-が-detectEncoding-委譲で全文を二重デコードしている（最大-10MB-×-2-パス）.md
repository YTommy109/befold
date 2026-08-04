---
id: TASK-26
title: decodeText が detectEncoding 委譲で全文を二重デコードしている（最大 10MB × 2 パス）
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 10:55'
updated_date: '2026-07-17 01:27'
labels: []
dependencies:
  - TASK-29
references:
  - BefoldApp/BefoldKit/TextEncoding.swift
  - BefoldApp/BefoldKit/FileReading.swift
priority: medium
ordinal: 80
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コミット 996742f の単一情報源化で TextEncoding.decodeText（TextEncoding.swift:88-91）が detectEncoding を呼んでから同じ Data を再デコードする構造になった。detectEncoding は BOM なし UTF-8 で String(data:encoding:.utf8) を全文実行して捨て、レガシーエンコーディングでは NSString.stringEncoding の変換結果 convertedString を捨てる。非チャンクパス（DefaultFileReader.readString、上限 10MB）のファイルオープン・再読込ごとに全文デコードが 2 回走る（v1.7.0 は各分岐で変換結果を直接返していた）。BOM あり・UTF-16 ヒューリスティック経路は影響なし。チャンクパスは 8KB プローブのみで軽微。正確性への影響はなし（検証済み）。修正案: detectEncoding が変換済み文字列も返せるようにする、または decodeText 側に直接デコード分岐を残す。単一情報源の設計意図と両立させること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 BOM なし UTF-8 とレガシーエンコーディングのファイルでデコードが 1 パスになっている
- [x] #2 エンコーディング検出ロジックの単一情報源化（996742f の意図）が維持されている
- [x] #3 既存の TextEncoding テストがすべて通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. detectEncoding のロジックを private detectEncodingAndDecode に切り出し、BOM なし UTF-8 判定時の全文デコード結果(decodedText)を保持できるようにする
2. decodeText と NormalizedTextCache 用に detectAndDecodeText(internal) を追加し、判定時に得た decodedText があれば再利用、なければ1回だけデコードする
3. NormalizedTextCache.init を detectAndDecodeText 経由に変更し、detectEncoding→String(data:encoding:) の二重デコードを解消する
4. 公開 API(detectEncoding のタプル形状)は変更せず、既存呼び出し元・テストの互換性を保つ
5. swift test で TextEncoding/NormalizedTextCache/FileReading 系テストと全体テストを実行して回帰がないことを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TextEncoding.detectEncoding のロジックを private detectEncodingAndDecode(_:) に切り出し、BOM なし UTF-8 判定時に検証用に行っていた String(data:encoding:.utf8) の結果を decodedText として保持するよう変更。decodeText と新設の internal detectAndDecodeText(_:) はこの decodedText があれば再利用し、なければ1回だけデコードするため、UTF-8 判定パスの全文デコードは1回のみになった。NormalizedTextCache.init も detectEncoding+String(data:encoding:) の二重デコードから detectAndDecodeText 経由の1回デコードに変更(NormalizedTextCache 側にも同種の二重デコードがあったため合わせて解消)。公開 API である detectEncoding のタプル形状(encoding, bomLength)は変更なし。
レガシーエンコーディング(Shift_JIS/EUC-JP)分岐は元々 NSString.stringEncoding の変換対象が sniffLength(8KB)プレフィックスのみで全文の二重デコードではなかったため、decodeText 側の1回のフルデコードのみで従来から変わらず1パス。
検証: swift test (全351件) が全て通過。swiftformat --lint も差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TextEncoding.decodeText の BOM なし UTF-8 判定→再デコードによる二重フルデコードを解消。detectEncoding の判定ロジックを private detectEncodingAndDecode(_:) に切り出し、UTF-8 検証時に生成した文字列を decodedText として保持・再利用するようにし、decodeText と新設 internal detectAndDecodeText(_:) の両方が1回のデコードで済むようにした。NormalizedTextCache.init にも同種の二重デコードがあったため合わせて修正。detectEncoding の公開シグネチャ(タプル形状)は変更なし。swift test 全351件通過、swiftformat --lint 差分なしで検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
