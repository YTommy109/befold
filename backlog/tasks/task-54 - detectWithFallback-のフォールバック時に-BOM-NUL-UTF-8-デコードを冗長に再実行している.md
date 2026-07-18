---
id: TASK-54
title: detectWithFallback のフォールバック時に BOM/NUL/UTF-8 デコードを冗長に再実行している
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-17 11:50'
updated_date: '2026-07-18 11:58'
labels: []
dependencies: []
priority: low
type: enhancement
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビューで発見。detectWithFallback がフォールバック呼び出し時に detectEncodingAndDecode を再度呼ぶが、BOM チェック・NUL スキャン・UTF-8 全ファイルデコードは同じ data に対して同一結果を返す。実際に異なるのは NSString.stringEncoding のステップだけ。50MB の Shift_JIS ファイル等で O(file_size) の無駄な再スキャンが発生する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フォールバック時に BOM チェック・NUL スキャン・UTF-8 デコードが重複実行されない
- [x] #2 既存の TextEncoding テストがすべてパスする
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
detectWithFallback/detectAndDecodeText を単純化・統合。BOM/NUL/UTF-8全文デコードは判定窓に依存せず結果が一定であるため detectFixedEncoding として一度だけ実行し、sniffWindow に依存する NSString.stringEncoding(レガシーエンコーディング判定)のみを先頭sniffLength→全データの2段階でリトライする形に再構成。detectAndDecodeText 側は判定成功だけでなく復号成功も再試行条件に含める必要があった(ASCII header部分だけで判定するとASCII/UTF-8と誤判定され、後続のShift_JIS本文の復号に失敗するケースがあるため)。swift test --filter TextEncodingTests で10件全てpass、swift test --skip Integration --skip FileWatcherTests で358件全てpassを確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TextEncoding.swift の detectWithFallback/detectEncodingAndDecode を再構成し、フォールバック時のBOMチェック・NULスキャン・UTF-8全文デコードの重複実行を解消した。これらは判定窓(sniffWindow)によらず data 全体から一意に決まるため detectFixedEncoding として一度だけ実行し、実際にsniffWindowで結果が変わるNSString.stringEncodingによるレガシーエンコーディング判定のみを先頭sniffLength→全データの2段階でリトライする構成に変更。あわせて detectAndDecodeText 側の重複した2段階フォールバック実装(decodeUsingDetection)も統合し、判定失敗だけでなく復号失敗時も全データでの再試行を行う挙動を維持した。swift test --filter TextEncodingTests (10 tests) 、swift test --skip Integration --skip FileWatcherTests (358 tests) いずれも全てpassすることを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
