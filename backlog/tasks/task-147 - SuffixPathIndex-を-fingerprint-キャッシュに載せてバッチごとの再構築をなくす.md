---
id: TASK-147
title: SuffixPathIndex を fingerprint キャッシュに載せてバッチごとの再構築をなくす
status: In Progress
assignee: []
created_date: '2026-07-25 11:30'
updated_date: '2026-07-25 11:48'
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
- [ ] #1 GitCommandFileIndex のエントリを (fingerprint, files, suffixIndex) に拡張し、fingerprint が同じ間は構築済み SuffixPathIndex を返す
- [ ] #2 同一 fingerprint での連続バッチで SuffixPathIndex が再構築されないことをテストで確認する
- [ ] #3 fingerprint 無効化・LRU 追い出し時に索引も一緒に破棄される
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
