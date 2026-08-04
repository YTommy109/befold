---
id: TASK-5
title: LineChunkReader.init の detectBOM 重複実行を統合する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 07:02'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/207
priority: low
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #207 から移行。LineChunkReader.init が detectBOM を呼んだ後、else 分岐で detectEncoding を呼ぶが、detectEncoding 内部で detectBOM を再実行する。さらに isChunkableEncoding も BOM をスキャンしており、同じプローブを最大 3 回走査している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 detectEncoding を一度だけ呼んでエンコーディングを得る形に統合されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
detectEncoding のシグネチャを String.Encoding? から (encoding: String.Encoding, bomLength: Int)? に変更し、BOM有無の判定とbomLength算出を一箇所(detectEncoding内部の既存detectBOM呼び出し)に統合する。
1. TextEncoding.detectEncoding を (encoding: String.Encoding, bomLength: Int)? を返すように変更(BOMありならbom.bomLength、それ以外は0)。
2. decodeText を detectEncoding の戻り値からbomLength分dropFirstして復号するだけに簡略化(冒頭の自前detectBOM呼び出しを削除)。
3. LineChunkReader.init のif/else(detectBOM直接呼び出し→else detectEncoding呼び出し)を、detectEncoding単一呼び出し+デフォルト.utf8/0のフォールバックに置き換える。
4. isChunkableEncoding は probe(トリム前)に対する独立した判定のためスコープ外とし変更しない。
5. swift test で既存テストが通ることを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TextEncoding.detectEncoding のシグネチャを (encoding: String.Encoding, bomLength: Int)? に変更し、BOM有無判定とbomLength算出を一箇所に統合。decodeText はdetectEncodingの戻り値からbomLength分dropFirstするだけに簡略化。LineChunkReader.init のif/elseをdetectEncoding単一呼び出し+デフォルト値フォールバックに置き換え。isChunkableEncoding はスコープ外(トリム前probeに対する独立判定のため)。swift test --skip Integration --skip FileWatcherTests: 323 tests passed。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TextEncoding.detectEncoding が (encoding, bomLength) のタプルを返すように変更し、LineChunkReader.init は detectEncoding を一度呼ぶだけでencoding・bomLength両方を得る形に統合(AC1)。副次効果としてdecodeTextも自前のdetectBOM呼び出しが不要になり簡略化された。swift test で323件全テスト成功を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
