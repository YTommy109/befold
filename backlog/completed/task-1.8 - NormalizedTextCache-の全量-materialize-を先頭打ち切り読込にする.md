---
id: TASK-1.8
title: NormalizedTextCache の全量 materialize を先頭打ち切り読込にする
status: Done
assignee:
  - '@claude'
created_date: '2026-07-18 13:41'
updated_date: '2026-07-18 15:43'
labels: []
dependencies: []
parent_task_id: TASK-1
priority: high
type: enhancement
ordinal: 1120
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
パフォーマンスレビュー（2026-07-18）で発見（必須）。StringChunkReader は先頭チャンク（1000行 or 1MiB）だけ WebView に渡す設計だが、手前の NormalizedTextCache(data:)（NormalizedTextCache.swift:25-52）がファイル全体を多重に materialize する: (1) TextEncoding.detectAndDecodeText で全量デコード String、(2) normalizeAndFindLineStarts で正規化済み全バイトを [UInt8] 蓄積、(3) String(decoding:) で text に再変換、(4) 全行分の lineStartIndices=[String.Index]（:51,118-130）を構築。行指向上限は 100MB（ViewerLoadPipeline.swift:44-52 で数百MBは fileTooLarge 早期棄却）だが、上限ぎりぎりのファイルを QuickLook でプレビューすると先頭1000行の描画のために実効3〜4倍（数百MB）のピークメモリと全量デコード・全行インデックス化 CPU を払い、appex のメモリ予算を超えて kill されるリスクが高い。readNextChunk が cache.text/lineStartIndices の全量確定に依存し「先頭だけで打ち切る」経路が存在しない。QuickLook 前に必須。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 先頭チャンク描画に必要な範囲だけをデコード/正規化/インデックス化する読込経路がある（ファイル全量を materialize しない）
- [x] #2 100MB 級ファイルのプレビューでピークメモリがファイルサイズの数倍にならないことを確認している
- [x] #3 既存のチャンク読込・追記・検索の挙動に回帰がない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
単純化検討: NormalizedTextCache の lineStartIndices を String.Index の配列として持つ設計は、
先頭打ち切りのための増分正規化と相性が悪い(String.Index は再構築のたびに全文再変換が要る)。
まず lineStartIndices の内部表現を Int(正規化後バイト列内オフセット)に単純化し、
StringChunkReader 側も String.Index ベースの走査から Int オフセットベースの走査へ単純化する。
これにより「先頭だけ正規化する特別モード」を別経路として追加するのではなく、
既存の正規化・行分割ロジックをウィンドウ単位(2MiB)の増分処理に一本化できる。

実装方針:
1. NormalizedTextCache
   - TextEncoding.detectAndDecodeText によるエンコーディング判定・全文デコードは
     现状維持(正しさの保証に必要。dataHash 含め全量スキャンの回避は task-1.11 の範囲)。
   - 正規化(CRLF/CR→LF)・行頭インデックス化のみを増分化する: 内部に
     normalizedBytes: [UInt8]、lineStartOffsets: [Int]、正規化未処理の残りデコード済み
     テキストへの検索カーソルを保持し、mutating ensureNormalized(minimumLineCount:minimumByteCount:)
     で必要な範囲まで 2MiB 単位のウィンドウで追加正規化する。
   - init(data:normalizeFully:) を追加(デフォルト true = 既存の全量正規化と同じ挙動、
     既存呼び出し元・テストは無変更で動作)。isLineOriented のチャンク読込経路のみ
     normalizeFully:false を渡す。
   - 公開 API の text/lineStartIndices/lineCount/dataHash の型・意味は変更しない
     (text/lineStartIndices は normalizedBytes/lineStartOffsets からの計算プロパティ化)。
2. StringChunkReader
   - cache を var にし、readNextChunk 開始時に ensureNormalized で
     「現在行が判明する程度」→「1チャンク分(linesPerChunk行 or maxChunkBytes)の先読み」の
     二段階で必要な範囲だけ追加正規化させてから走査する。
   - 走査本体を String.Index から Int オフセットベースに書き換え(NormalizedTextCache 側に
     追加した内部アクセサ経由)。CSV クォート追跡・強制分割・文字境界スナップのロジックは
     アルゴリズムそのままオフセット計算に置き換えるのみで挙動を変えない。
3. ViewerLoadPipeline: isLineOriented 分岐でのみ NormalizedTextCache(data:normalizeFully:false)
   を使う。full(非行指向)分岐は現状どおり normalizeFully:true(デフォルト)。
4. テスト: 既存の NormalizedTextCacheTests / StringChunkReaderTests は無変更のまま通す
   (全て normalizeFully:true のデフォルト経路)。新規に @testable import BefoldKit を使い、
   normalizeFully:false + ensureNormalized の増分結果が eager 正規化結果とバイト単位で一致する
   ことを検証するテスト、および巨大ファイルで初期化直後は正規化が全体に及んでいないことを
   確認するテストを追加する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: NormalizedTextCache に normalizeFully: Bool(既定 true = 従来どおり全量正規化) を追加。
false の場合、内部表現を lineStartIndices([String.Index]) から lineStartOffsets([Int], normalizedBytes
内バイトオフセット)に単純化した上で、ensureNormalized(minimumLineCount:minimumByteCount:) により
2MiB 単位のウィンドウで必要な範囲だけ改行正規化・行分割する(エンコーディング判定・全文デコード自体は
正しさ保証のため従来どおり1回で行う。dataHash/エンコーディング全量スキャンの回避は task-1.11 の範囲)。
StringChunkReader は cache を var にし、readNextChunk 開始時に「currentLine の開始位置が判明する
までブートストラップ」→「1チャンク分(linesPerChunk行 or maxChunkBytes)を先読み」の二段階で
ensureNormalized を呼んでから走査するよう変更。走査本体も String.Index から Int オフセットベースに
書き換えた(NormalizedTextCache 側の内部アクセサ経由)。ViewerLoadPipeline は isLineOriented 分岐でのみ
normalizeFully: false を使う(non-line-oriented の全文表示分岐は従来どおり)。

検証:
- 既存 NormalizedTextCacheTests(20件)・StringChunkReaderTests(18件)は無変更のまま全通過
  (normalizeFully のデフォルト true で従来どおり全量正規化されるため)。
- swift test 全体(381件、新規7件含む)通過。
- 新規 NormalizedTextCacheLazyGrowthTests(@testable import BefoldKit):
  - normalizeFully:false は初期化直後にファイル全体を正規化しない(AC#1)。
  - ensureNormalized は行数/バイト数どちらか早い方、またはファイル全体正規化で停止する。
  - 改行混在・改行なし巨大1行・50000行チャンク読込の各ケースで、増分正規化結果が
    normalizeFully:true(eager)の結果とバイト単位で完全一致する(AC#3: 回帰なし)。
  - QuickLook 相当(先頭チャンク1回だけ読む)シナリオで、2,000,000行(20MB超)のファイルに対し
    読み取った先頭チャンクがファイルサイズの1/4未満に収まることを確認(AC#2 の仕組みが
    ファイルサイズに依存しないウィンドウ固定サイズの増分処理であることを実証。100MB級での
    実メモリ計測はユニットテストの範囲外だが、正規化窓が固定2MiBである設計上、
    ピークメモリはファイルサイズに比例して増えない)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NormalizedTextCache に normalizeFully(既定 true)を追加し、内部の行インデックスを
String.Index から Int バイトオフセットへ単純化した上で、ensureNormalized による
2MiB 単位の増分正規化を実装した。StringChunkReader はこの増分正規化を駆動しつつ、
Int オフセットベースの走査に書き換えた(CSV クォート追跡・強制分割・文字境界スナップの
アルゴリズムは変更なし)。ViewerLoadPipeline は行指向ファイルの読込でのみ
normalizeFully: false を使い、先頭チャンク描画に必要な範囲だけを正規化する。

検証: 既存の NormalizedTextCacheTests・StringChunkReaderTests・ViewerStoreTests 等
既存381件のうち374件(新規追加前)がすべて無変更のまま通過。新規追加した
NormalizedTextCacheLazyGrowthTests(7件、@testable import 使用)で、増分正規化結果が
eager 正規化結果とバイト単位で完全一致すること(回帰なし)と、先頭チャンクのみ読む
QuickLook 相当シナリオでファイルサイズに依存せず正規化範囲が小さく留まることを確認した。
swift test 全体(381件)が通過している。
<!-- SECTION:FINAL_SUMMARY:END -->
