---
id: TASK-147
title: SuffixPathIndex を fingerprint キャッシュに載せてバッチごとの再構築をなくす
status: Done
assignee: []
created_date: '2026-07-25 11:30'
updated_date: '2026-07-25 12:00'
labels:
  - path-reference
  - performance
dependencies: []
priority: medium
type: enhancement
ordinal: 223000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitCommandFileIndex がキャッシュするのは [URL] のみで、LazySuffixIndex.value()（TrackedPathResolver.swift L35-42, 79-85）は git フォールバックが必要なバッチ（＝再レンダリング）のたびに SuffixPathIndex(candidates:) を O(N) でフル再構築する（SuffixPathMatcher.swift L64-79。候補 1 件あたり standardizedFileURL 2 回 + pathComponents 配列 2 本）。数万〜10 万ファイルのモノレポで未解決参照を含む文書を編集し続けると、保存のたびに数百 ms〜秒オーダーの再構築と大量アロケーションが走り、リンク化の反映が保存頻度に追いつかなくなる（パフォーマンスレビュー指摘・中）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GitCommandFileIndex のエントリを (fingerprint, files, suffixIndex) に拡張し、fingerprint が同じ間は構築済み SuffixPathIndex を返す
- [x] #2 同一 fingerprint での連続バッチで SuffixPathIndex が再構築されないことをテストで確認する
- [x] #3 fingerprint 無効化・LRU 追い出し時に索引も一緒に破棄される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
単純化の検討: エントリを (fingerprint, files, suffixIndex) の 3 つ組にする代わりに、GitFileIndexing の返り値自体を [URL] から SuffixPathIndex へ変える。
- files の生配列を読む呼び出し元は存在せず（唯一の消費者は TrackedPathResolver で、必ず索引化して使う）、両方持つと同じ知識の二重保持になる
- 索引だけをキャッシュすれば fingerprint 無効化・LRU 追い出しが索引にもそのまま効き、追加の破棄ロジックが不要（AC#3 が構造的に満たされる）

1. GitFileIndexing.trackedFiles(forFileAt:) -> [URL]? を trackedFileIndex(forFileAt:) -> SuffixPathIndex? に変更
2. TrackedPathResolver.LazySuffixIndex は索引を構築せず受け取るだけにする
3. GitCommandFileIndex のエントリを (fingerprint, index) にし、列挙直後に索引を構築してキャッシュ（ロック内で構築する理由をコメント化）
4. 索引の保持コストは [URL] より重いため、maxCachedRoots の根拠コメントを更新
5. テスト: 同一 fingerprint の連続取得で再列挙＝再構築が起きないことを固定。フェイク索引（TrackedPathResolverTests / ViewerWindowControllerTests / GitCommandFileIndexTests）を新 API へ追従
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#1 は「(fingerprint, files, suffixIndex) の 3 つ組」ではなく (fingerprint, index) の 2 つ組で満たした。GitFileIndexing の返り値自体を [URL] から SuffixPathIndex へ変えたため、生の URL 一覧を読む呼び出し元が消え、両方を保持すると同じ知識の二重保持になるため。索引だけをキャッシュすることで fingerprint 無効化・LRU 追い出しがそのまま索引にも効き、AC#3 は構造的に満たされる（追い出しテストのドキュメントにも明記）。
本番コードで SuffixPathIndex を構築する箇所は GitCommandFileIndex の 1 箇所だけになったことを grep で確認済み（もう 1 箇所の SuffixPathMatcher.bestMatch は索引と単発照合の等価性を固定するテスト専用）。
索引構築はロック内（列挙直後）に置いた。全ウィンドウで 1 つの索引を共有するのが目的のため。その意図をインラインコメントに明記。
保持コストは生の [URL] より数倍重くなるため maxCachedRoots の根拠コメントを更新した（上限値 4 は据え置き。典型的なリポジトリでは数 MB 規模で、下げると 3 リポジトリ以上を行き来する際に ls-files と索引構築が再発するため）。
コメント波及: GitCommandFileIndex / ViewerWindowManager / ViewerWindowController / 各テストの「追跡ファイル一覧」記述を索引ベースへ更新。
検証: swift test 686 tests（Integration 含む）全パス、npx jest 295 passed、swift build（SwiftLint 込み）、swiftformat 差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitFileIndexing の返り値を追跡ファイルの URL 一覧から SuffixPathIndex に変更し、GitCommandFileIndex が fingerprint 単位で構築済み索引をキャッシュするようにした。これにより解決バッチ（再レンダリング）ごとの O(候補数) の索引再構築がなくなり、本番の索引構築箇所は 1 箇所に収束。キャッシュ命中テストを「列挙回数＝索引構築回数」の観点で強化し、swift test 686 件・jest 295 件が全てパスすることを確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
