---
id: TASK-144
title: resolveReferences ブリッジを async 化してメインスレッドの git 実行をなくす
status: To Do
assignee: []
created_date: '2026-07-25 10:10'
updated_date: '2026-07-25 10:20'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## ブランチ feat/document_path 最終再レビューからの追加事項（TASK-144 に畳む）

- GitCommandFileIndex をウィンドウ間で共有した結果、単一 NSLock が全ウィンドウを直列化する。同一リポジトリのウィンドウ間では悪化しないが、**別リポジトリのウィンドウ間では悪化する**: リポジトリ A のバックグラウンド warm() が ls-files 中に共有ロックを保持し、リポジトリ B の MainActor 側 trackedFiles がその完了を待つ。共有前は独立した索引で並行実行できていた。GitCommandFileIndex の doc コメントにある「全体では悪化しない」は同一リポジトリの場合に限る旨へ要修正。
- 共有によりキャッシュがアプリ寿命になり eviction が無くなった。entryByRoot は開いたことのある全リポジトリの追跡ファイル一覧 [URL] を保持し続ける（10 万ファイルのモノレポで数十 MB）。rootByDir の staleness 受け入れもウィンドウ寿命からアプリ寿命に延びた。async 化にあわせて eviction 方針を決めること。
- GitCommandRunner.run にタイムアウトが無い。git がハングすると呼び出し側が無期限にブロックし、ロック共有により他ウィンドウの索引呼び出しも巻き込む。
<!-- SECTION:NOTES:END -->
