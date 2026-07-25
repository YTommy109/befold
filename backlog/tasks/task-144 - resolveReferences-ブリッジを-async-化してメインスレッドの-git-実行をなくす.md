---
id: TASK-144
title: resolveReferences ブリッジを async 化してメインスレッドの git 実行をなくす
status: To Do
assignee: []
created_date: '2026-07-25 10:10'
labels: []
dependencies: []
priority: medium
ordinal: 220000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
表示時のパス解決 (ViewerRenderer の resolveReferences ハンドラ → ViewerWindowController.resolveReferences) は同期シグネチャ (_ paths: [String]) -> [String: String] を持つため、GitCommandFileIndex のキャッシュが cold または fingerprint 無効化された場合に git ls-files subprocess をメインスレッド上で同期実行する。warm() は open/switch をカバーするが、外部の git commit / add で .git/index の fingerprint が変わるため、ユーザーがコミットした直後の次の描画で大きなリポジトリでは 100〜300ms のメインスレッド停止が起きうる。さらに warm() のバックグラウンド実行中は NSLock 待ちでメインスレッドがブロックしうる。ブランチ feat/document_path の最終レビュー (Important 3) で指摘され、SuffixPathMatcher の索引化 (支配的コストの除去) を先に行ったうえで後続タスクへ送った項目。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 resolveReferences の解決が MainActor をブロックせずに実行される
- [ ] #2 JS 側の FIFO 契約 (未応答バッチを順に取り出す) が壊れず、応答が要求と同じ順序で返る
- [ ] #3 解決が非同期になっても、表示時にリンク化した参照とクリック時の遷移先が一致する不変条件が保たれる
- [ ] #4 既存の swift / jest テストが全通過し、非同期化による順序保証の回帰テストが追加されている
<!-- AC:END -->
