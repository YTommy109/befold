---
id: TASK-36
title: 8KB超のレガシーエンコーディング(SJIS等)ファイルが拒否・文字化けする(判定が先頭8192バイトのみ)
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-17 02:06'
updated_date: '2026-07-17 03:10'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TextEncoding.swift:63 でレガシーエンコーディング判定が `data.prefix(sniffLength)`(8192バイト)に対して実行されるが、検出したエンコーディングは全データのデコードに適用される(:86)。フォールバックはない。v1.7.1-dev.5 以前は全データで判定していたため回帰。

失敗モード1: 先頭8KBが純ASCIIで後半に日本語があるSJISファイル → プレフィックスからASCII/UTF-8と誤判定 → 全データデコードがnil → NormalizedTextCache が decodeFailed を throw → 「未対応フォーマット」として拒否される。
失敗モード2: 2バイト文字がオフセット8192をまたぐ → 切断されたプレフィックスが不正SJISとなり判定が失敗/lossy → 拒否または文字化け。

修正方向: プレフィックス判定を維持しつつ (a) 不完全なマルチバイト末尾のトリム、(b) 全データデコード失敗時に全データで再判定するフォールバック、の少なくとも一方を入れる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ASCIIヘッダー8KB超+後半日本語のSJISファイルが正しくデコード・表示される(回帰テストあり)
- [x] #2 2バイト文字が8192バイト境界をまたぐSJISファイルが正しくデコードされる(回帰テストあり)
- [x] #3 判定の高速化(全文走査回避)の性能特性は維持される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. TextEncoding.swift の detectEncodingAndDecode に sniffWindow パラメータ(既定は data.prefix(sniffLength))を追加し、NUL判定・NSString.stringEncoding判定にプレフィックスの代わりにこのウィンドウを使う(looksLittleEndianUTF16 もウィンドウを受け取る形に変更)。
2. detectAndDecodeText を、まずプレフィックスウィンドウで判定・復号を試み、失敗した場合のみ全データをウィンドウとして再判定・復号するフォールバックを行う構造にリファクタリングする(通常系はプレフィックスのみ走査、失敗系のみ全文走査というAC#3の性能特性を維持)。
3. 失敗モード1(ASCIIヘッダー8KB超+後半SJIS)・失敗モード2(2バイト文字が8192バイト境界をまたぐSJIS)の回帰テストを TextEncodingTests.swift に追加する。
4. 既存の高速性テスト(task-31)が悪化しないことを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: TextEncoding.detectAndDecodeText を、先頭 sniffLength(8192)バイトでの判定・復号→失敗時のみ全データを判定窓として再試行、というフォールバック構造にリファクタリング(detectEncodingAndDecode に sniffWindow パラメータを追加)。looksLittleEndianUTF16 は呼び出し元が渡した窓をそのまま使うよう変更。
検証: TextEncodingTests.swift に失敗モード1(ASCIIヘッダー8KB超+後半SJIS)・失敗モード2(2バイト文字が8192境界をまたぐSJIS)の回帰テストを追加、両方 pass。既存の task-31 高速性テスト(5MB超SJIS、prefixのみで判定成功する経路)も 0.248s で pass、フォールバックが通常系の性能に影響しないことを確認。swift test 全体(342 tests, 44 suites)も pass。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TextEncoding.detectAndDecodeText にフォールバック機構を追加。先頭8192バイト(sniffLength)での判定・復号がまず試行され、それが失敗した場合(ASCIIヘッダーが8KBを超え後半にSJIS本文があるケース、あるいは2バイト文字が8192境界をまたいでプレフィックスが不正になるケース)のみ、全データを判定窓として再試行する。detectEncodingAndDecode に sniffWindow パラメータを追加し、通常系は従来通りプレフィックスのみを走査するため性能特性は変わらない。TextEncodingTests.swift に両失敗モードの回帰テストを追加し pass を確認、既存の task-31 高速性テストと swift test 全体(342 tests)も pass。
<!-- SECTION:FINAL_SUMMARY:END -->
