---
id: TASK-53
title: 強制分割後に inQuotes がリセットされず CSV チャンクサイズが永続的に異常化する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-17 11:50'
updated_date: '2026-07-18 06:49'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 3750
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビューで発見。CSV ファイルの最初のフィールドに閉じられない二重引用符がある場合、強制分割後に inQuotes=false へのリセットがないため以降のすべてのチャンクが 1000 行ではなく maxChunkBytes (~1MB) 単位になり復帰しない。行数表示も不正確になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 強制分割後に inQuotes 状態が適切にリセットされる
- [x] #2 不均衡な引用符を含む CSV で後続チャンクが通常の行数ベース分割に復帰する
- [x] #3 不均衡クォートからの復帰をテストするケースがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 経緯整理: 元々(b11c9b9)は強制分割のたびに inQuotes をリセットしていたが、
   64f6e13 で「正当な複数行クォートフィールドの状態が失われる」バグを修正するため
   リセットを削除した。結果、対のない引用符があると以降ファイル末尾までずっと
   inQuotes=true のままになり、強制分割(maxChunkBytes単位)が延々続く
   (task-53 が指摘する問題)。
2. 単純化検討・設計方針(ユーザーと合意): 「強制分割(チャンク境界、maxChunkBytes=1MiB)」と
   「クォート境界(CSVセルの実長)」は本来無関係な概念であり、チャンク境界の
   またぎ回数でクォート異常を判定するのは単位が粗すぎる。
   代わりに、クォートが開いてから閉じずに経過したバイト数を独立に追跡し、
   500 バイトを超えたら不均衡クォートとみなして inQuotes を強制的に false へ戻す
   方式にする。これによりチャンク分割の都合と完全に切り離せ、新しい「強制分割回数」
   のような状態を増やさずに済む(quotedRunLength という単一カウンタのみ追加)。
   500 バイト以内の正当な複数行クォートフィールドはこれまでどおり正しく扱われる。
3. 実装: StringChunkReader に quotedRunLength: Int アクター状態と
   maxQuotedFieldBytes = 500 定数を追加。advanceRespectingQuotes 内で
   `"` によるトグル時に quotedRunLength をリセットし、inQuotes 中はバイトごとに
   加算、閾値超過で inQuotes を強制的に false にしてリセットする。
4. テスト: forcedSplitPreservesQuoteState (旧: 永久にプリザーブされることを検証)を
   新しい仕様(500バイト超で打ち切り→通常の行ベース分割に復帰)に更新する。
   AC#3 に対応する不均衡クォートからの復帰テストを追加/更新する。
5. docs/superpowers/specs/2026-07-14-line-chunked-loading-design.md の
   既知の制限セクション(現状は無条件リセットという古い記述のまま)を
   新しい 500 バイト閾値方式の説明に更新する。
6. swift test で確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
経緯調査の結果、64f6e13 で inQuotes の強制分割ごとのリセットを削除したことで task-53 の問題(対のない引用符が永久に inQuotes=true のままになる)が生じていたと判明。ユーザーと協議し、チャンク境界(maxChunkBytes=1MiB)ではなくクォートの実長で判定する方式を採用: quotedRunLength でクォート開放後の経過バイト数を追跡し、500バイト(maxQuotedFieldBytes)を超えたら不均衡クォートとみなして inQuotes を強制的に false に戻す。forcedSplitPreservesQuoteState テストは旧仕様(永久プリザーブ)を検証していたため、新仕様(500バイト超で打ち切り→行ベース分割に復帰)を検証するテストに置き換えた。design doc(2026-07-14-line-chunked-loading-design.md)の既知の制限セクションも新方式に更新。swift test --skip Integration --skip FileWatcherTests で352件全てpass。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
対のない引用符が閉じないまま inQuotes=true が永続しファイル末尾までバイト上限分割が続く問題を修正。クォートが開いてから閉じずに経過したバイト数(quotedRunLength)を追跡し、500バイト(maxQuotedFieldBytes、チャンク境界とは独立した閾値)を超えたら不均衡クォートとみなして inQuotes を強制リセットし、通常の1000行ベース分割に復帰するようにした。StringChunkReaderTests に復帰を検証するテストを追加(旧: forcedSplitPreservesQuoteStateを置き換え)。design docの既知の制限セクションも更新。swift test --skip Integration --skip FileWatcherTests で352件全てpass。
<!-- SECTION:FINAL_SUMMARY:END -->
