---
id: TASK-21
title: 「さらに読み込む」後に世代カウンタ未同期で全文 render が毎回走る（追記最適化が無効化）
status: To Do
assignee: []
created_date: '2026-07-16 10:54'
labels: []
dependencies: []
references:
  - BefoldApp/befold/Viewer/ViewerWebView.swift
  - BefoldApp/befold/Viewer/ViewerStore.swift
priority: high
type: bug
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コミット 8ef7703 で content 比較を contentRevision 世代カウンタに置き換えた際、handleLoadMoreLines（ViewerWebView.swift:440-465）が appendChunk 送信後に lastRenderedContentRevision を更新しなくなった（v1.7.0 では lastRenderedContent?.append(result.chunk) でキャッシュ整合を保っていた）。ViewerStore.loadMoreLines は contentRevision += 1 するため（ViewerStore.swift:155-156）、直後の SwiftUI 更新で needsRender が必ず true になり、追記済み全コンテンツの完全 render() が毎クリック走る。追記パス最適化（TASK-8 の趣旨）が事実上無効。onLoadMoreLines の戻り値に新 revision を含める、または store.contentRevision を読んで recordRendered する等で追記後にカウンタを同期する。副次論点: SwiftUI コミットが appendChunk より先に走った場合はチャンクが二重表示されるレース（PLAUSIBLE、タイミング依存）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 「さらに読み込む」1 クリックにつき JS 側の描画は appendChunk 1 回のみで、全文 render() が走らない
- [ ] #2 検索用の untilFullyLoaded ループ中も同様に全文 render が発生しない
- [ ] #3 チャンク二重表示レースの可能性が排除されている（追記後に revision 同期）
<!-- AC:END -->
