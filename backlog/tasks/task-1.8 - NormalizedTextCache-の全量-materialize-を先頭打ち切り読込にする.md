---
id: TASK-1.8
title: NormalizedTextCache の全量 materialize を先頭打ち切り読込にする
status: To Do
assignee: []
created_date: '2026-07-18 13:41'
labels: []
dependencies: []
parent_task_id: TASK-1
priority: high
type: enhancement
ordinal: 6120
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
パフォーマンスレビュー（2026-07-18）で発見（必須）。StringChunkReader は先頭チャンク（1000行 or 1MiB）だけ WebView に渡す設計だが、手前の NormalizedTextCache(data:)（NormalizedTextCache.swift:25-52）がファイル全体を多重に materialize する: (1) TextEncoding.detectAndDecodeText で全量デコード String、(2) normalizeAndFindLineStarts で正規化済み全バイトを [UInt8] 蓄積、(3) String(decoding:) で text に再変換、(4) 全行分の lineStartIndices=[String.Index]（:51,118-130）を構築。行指向上限は 100MB（ViewerLoadPipeline.swift:44-52 で数百MBは fileTooLarge 早期棄却）だが、上限ぎりぎりのファイルを QuickLook でプレビューすると先頭1000行の描画のために実効3〜4倍（数百MB）のピークメモリと全量デコード・全行インデックス化 CPU を払い、appex のメモリ予算を超えて kill されるリスクが高い。readNextChunk が cache.text/lineStartIndices の全量確定に依存し「先頭だけで打ち切る」経路が存在しない。QuickLook 前に必須。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 先頭チャンク描画に必要な範囲だけをデコード/正規化/インデックス化する読込経路がある（ファイル全量を materialize しない）
- [ ] #2 100MB 級ファイルのプレビューでピークメモリがファイルサイズの数倍にならないことを確認している
- [ ] #3 既存のチャンク読込・追記・検索の挙動に回帰がない
<!-- AC:END -->
