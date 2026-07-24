---
id: TASK-116.11
title: MarkdownImageEmbedder にファイル読み込みの依存注入を導入する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 00:59'
updated_date: '2026-07-24 01:42'
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
- [x] #1 MarkdownImageEmbedder がファイル読み込み依存を注入で受け取れる
- [x] #2 キャッシュの有効性判定に必要な情報を注入経由で取得できる（更新日時の扱いをどう解決したかが記録されている）
- [x] #3 MarkdownImageEmbedderTests が実ファイルシステムに依存せず実行できる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 設計判断: 更新日時の扱いは選択肢 1(FileReading に modificationDate(at:) を追加)を採る。選択肢 2(サイズのみキー)はキャッシュ無効化の精度を落とし、同サイズで内容が変わった画像を検出できなくなるため退ける。準拠型は DefaultFileReader / InMemoryFileReader / ExclusionFileReader(テスト内) の 3 つのみで波及が小さい。
2. FileReading に modificationDate(at:) -> Date? を追加し、3 準拠型に実装する(InMemoryFileReader は setModificationDate(_:at:) で制御可能にする)。デフォルト実装は置かない(silent に nil へ縮退させない)。
3. MarkdownImageEmbedder を enum から struct へ変更し、fileReader を デフォルト引数付きイニシャライザ注入で受け取る。DataURICache はプロセス共有の可変状態なので static 共有をやめ、インスタンス所有にする。本番の共有経路(ViewerLoadPipeline のウォームアップ / ViewerRenderer+RenderHelpers の render 直前)は MarkdownImageEmbedder.shared を明示的に使い、キャッシュ共有の不変条件を保つ。テストは自前インスタンスを作るためテスト間のキャッシュ汚染も同時に解消する。
4. dataURI 内の url.resourceValues / Data(contentsOf:) を fileReader 経由(fileSize / modificationDate / readData)へ置換する。
5. MarkdownImageEmbedderTests を InMemoryFileReader ベースへ移行し、実 FS(TempDir/FileManager)依存を除去する。
6. swift test と swiftlint で検証する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
設計判断: 更新日時は選択肢 1(FileReading に modificationDate(at:) -> Date? を追加)を採用した。選択肢 2(キャッシュキーをサイズのみに弱める)は「同サイズで内容が変わった画像」を検出できなくなりライブリロードで古い画像を表示しうるため退けた。準拠型は DefaultFileReader / InMemoryFileReader / ExclusionFileReader(DirectoryListerTests 内) の 3 つだけで、波及は各 1 メソッドの追加に収まった。プロトコル拡張のデフォルト実装は置いていない(nil へ silent に縮退させると、新しい準拠型でキャッシュ無効化が黙って壊れるため)。

キャッシュの扱い: MarkdownImageEmbedder を enum から struct へ変え、private static let cache をインスタンス所有に移した。本番の 2 経路(ViewerLoadPipeline のウォームアップ / ViewerRenderer+RenderHelpers の render 直前)は MarkdownImageEmbedder.shared を明示的に経由し、キャッシュ共有の不変条件を保つ(coding_rule の「共有が不変条件の依存に生成デフォルトを付けない」に沿い、共有経路を呼び出し側で固定した)。テストは自前インスタンスを作るためキャッシュが隔離され、TASK-116.8 で懸念されたテスト順依存の余地も同時に消えた。

副次的な変更: dataURI 内の 1 回の resourceValues([.fileSizeKey, .contentModificationDateKey]) が fileReader.fileSize + fileReader.modificationDate の 2 回の stat になった。画像 1 枚あたりの base64 化コストに対して無視できる差であり、キャッシュヒット時も stat 2 回で済む。

検証: swift test で 597 tests / 77 suites が 14.211 秒で pass。MarkdownImageEmbedderTests 単独では 16 tests が 0.002 秒で pass(実 FS を触らないため)。TempDir / FileManager.default の出現数は 13 → 0。swiftlint --strict の違反数は変更前後とも 65 で、新規違反なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FileReading に modificationDate(at:) を追加し、MarkdownImageEmbedder を enum から struct へ変更して fileReader をデフォルト引数付きイニシャライザ注入で受け取るようにした。data URI キャッシュは static からインスタンス所有へ移し、本番の 2 経路は MarkdownImageEmbedder.shared を経由してキャッシュ共有を保つ。MarkdownImageEmbedderTests は InMemoryFileReader ベースへ移行し、実 FS 依存(TempDir / FileManager)13 箇所を 0 にした。swift test 597 tests pass、当該スイート単独 16 tests が 0.002 秒で pass、swiftlint --strict の違反数は前後とも 65 で新規なし。
<!-- SECTION:FINAL_SUMMARY:END -->
