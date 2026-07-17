---
id: TASK-44
title: コーディング規約違反を解消する(タスク番号コメント6箇所と新規公開型の /// 欠落)
status: To Do
assignee: []
created_date: '2026-07-17 02:08'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 9200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
docs/dev/coding_rule.md の「書かなくてよいコメント: タスク番号や変更履歴の参照(コミットメッセージに書く)」(:406、JS/HTML にも適用 :447)に違反するコメントが本ブランチで6箇所追加された:
- LoadingIndicatorView.swift:5 (task-30)
- ViewerStore.swift:46, 54, 333 (task-32)
- ViewerWebView.swift:455 (TASK-25)
- viewer.html:856 (TASK-25)

また「/// ドキュメンテーションコメント: 公開クラス・公開メソッドに日本語で付ける」(:330)に対し、新規公開型に /// がない:
- NormalizedTextCache.swift: NormalizedTextCacheError(:4)、NormalizedTextCache(:8)、init(data:)(:19)
- StringChunkReader.swift: StringChunkReader(:10)、init(cache:respectsCSVQuotes:)(:18) — 削除された LineChunkReader の型概要 /// も引き継がれていない

タスク番号参照は削除(必要な設計理由はタスク番号なしの言葉で書き直す)し、公開型には日本語の /// を追加する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 プロダクトコード・JS/HTML から task-NN/TASK-NN 参照コメントがなくなる(意図説明は残す)
- [ ] #2 NormalizedTextCache/StringChunkReader の公開型・公開イニシャライザに日本語 /// が付く
<!-- AC:END -->
