---
id: TASK-116.11
title: MarkdownImageEmbedder にファイル読み込みの依存注入を導入する
status: To Do
assignee: []
created_date: '2026-07-24 00:59'
labels:
  - test
  - cleanup
dependencies: []
parent_task_id: TASK-116
priority: low
ordinal: 31100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-116.8 から分離（ユーザー判断により別タスク化）。`FileReading` プロトコルの拡張というプロダクト API の変更を伴うため。

## 現状

`BefoldApp/BefoldKit/MarkdownImageEmbedder.swift` の `embedLocalImages(in:baseURL:maxImageSizeBytes:)` は `FileReading` を受け取らず、内部で直接ファイルシステムを読む。`coding_rule.md` の「外部依存はプロトコル + デフォルト引数付きイニシャライザ注入」に反しており、その結果 `MarkdownImageEmbedderTests`（実 FS I/O 13 箇所）がモックへ置換できない。

## 着手前に解決が必要な設計上の論点

単純に `fileReader: any FileReading = DefaultFileReader()` を足すだけでは済まない。

`MarkdownImageEmbedder.dataURI(forPath:baseURL:maxImageSizeBytes:)` は `url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])` でサイズと**更新日時**を取り、内部 `DataURICache` がその 2 つでキャッシュの有効性を判定している（ライブリロードで markdown が変わるたびに未変更画像まで再読込・base64 化してメインスレッドを塞ぐのを避けるため）。

一方 `BefoldApp/BefoldKit/FileReading.swift` のプロトコルには `fileSize(at:)` はあるが**更新日時を取る手段が無い**。

選択肢:

1. `FileReading` に `modificationDate(at:) -> Date?` を追加する。`DefaultFileReader` と `InMemoryFileReader` を含む全準拠型に波及する。
2. キャッシュのキーをサイズのみに弱める。実装は小さいが、サイズが同じで内容が変わった画像を検出できなくなり、キャッシュ無効化の精度が落ちる。

1 が筋だが影響範囲があるため、着手時に両案を比較して判断すること。

## 補足: 静的共有キャッシュについて

`MarkdownImageEmbedder.swift` の `private static let cache = DataURICache()` はプロセス全体で共有される静的可変状態だが、テスト順依存は**現状では起きない**ことを TASK-116.8 で実測確認済み。`ViewerLoadPipelineTests` の warm/cold 2 テストはそれぞれ別の `TempDir`（UUID 付き）配下にファイルを作るため、キャッシュのキーである URL が衝突しない。単独実行・3 回連続実行のいずれも安定して pass する。したがって本タスクで対処が必須な項目ではないが、依存注入を入れる際にキャッシュも注入可能にできるなら併せて検討してよい。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 MarkdownImageEmbedder がファイル読み込み依存を注入で受け取れる
- [ ] #2 キャッシュの有効性判定に必要な情報を注入経由で取得できる（更新日時の扱いをどう解決したかが記録されている）
- [ ] #3 MarkdownImageEmbedderTests が実ファイルシステムに依存せず実行できる
<!-- AC:END -->
