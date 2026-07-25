---
id: TASK-144
title: resolveReferences ブリッジを async 化してメインスレッドの git 実行をなくす
status: Done
assignee:
  - '@claude'
created_date: '2026-07-25 10:10'
updated_date: '2026-07-25 10:57'
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
- [x] #1 resolveReferences の解決が MainActor をブロックせずに実行される
- [x] #2 JS 側の FIFO 契約 (未応答バッチを順に取り出す) が壊れず、応答が要求と同じ順序で返る
- [x] #3 解決が非同期になっても、表示時にリンク化した参照とクリック時の遷移先が一致する不変条件が保たれる
- [x] #4 既存の swift / jest テストが全通過し、非同期化による順序保証の回帰テストが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerRenderer.onResolveReferences を async シグネチャへ変更し、handleResolveReferences を Task 直列チェーン化して応答順を要求順に固定する (FIFO 契約維持)
2. ViewerWebView / ViewerContentView のクロージャ型を async へ追随
3. ViewerWindowController.resolveReferences を async 化し、resolveAll を Task.detached で MainActor 外実行 (baseURL は要求時点の fileURL を捕捉)
4. GitCommandFileIndex: doc コメントを実態(同一リポジトリ限定の効能 / MainActor は待たない)へ修正し、entryByRoot に LRU 上限を入れて無制限保持をやめる
5. GitCommandRunner.run にタイムアウトを入れ、git ハング時に呼び出し側が無期限ブロックしないようにする
6. テスト: 応答順序の回帰テスト(遅い解決が先行しても要求順に評価される)、LRU eviction、タイムアウト。既存 swift/jest テスト全通過を確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## ブランチ feat/document_path 最終再レビューからの追加事項（TASK-144 に畳む）

- GitCommandFileIndex をウィンドウ間で共有した結果、単一 NSLock が全ウィンドウを直列化する。同一リポジトリのウィンドウ間では悪化しないが、**別リポジトリのウィンドウ間では悪化する**: リポジトリ A のバックグラウンド warm() が ls-files 中に共有ロックを保持し、リポジトリ B の MainActor 側 trackedFiles がその完了を待つ。共有前は独立した索引で並行実行できていた。GitCommandFileIndex の doc コメントにある「全体では悪化しない」は同一リポジトリの場合に限る旨へ要修正。
- 共有によりキャッシュがアプリ寿命になり eviction が無くなった。entryByRoot は開いたことのある全リポジトリの追跡ファイル一覧 [URL] を保持し続ける（10 万ファイルのモノレポで数十 MB）。rootByDir の staleness 受け入れもウィンドウ寿命からアプリ寿命に延びた。async 化にあわせて eviction 方針を決めること。
- GitCommandRunner.run にタイムアウトが無い。git がハングすると呼び出し側が無期限にブロックし、ロック共有により他ウィンドウの索引呼び出しも巻き込む。

## 実装 (2026-07-25)

- ViewerRenderer.onResolveReferences を async 化。応答は resolveResponseChain (Task の直列チェーン) で「直前の要求の完了を待ってから解決・評価」する形にし、要求順 = 評価順を保証した。JS 側の FIFO 契約 (_mmdPendingRefBatches) は変更なし。
- ViewerWindowController.resolveReferences は要求時点の pathResolver / fileURL を捕捉して Task.detached で解決する。baseURL を捕捉するため、解決中のファイル切替でリンク先がずれることはない (切替時は JS が未応答バッチを空にする)。
- GitCommandFileIndex: doc コメントを実態へ修正 (別リポジトリ間では共有前より悪化する / ただし待つのはバックグラウンドの解決だけで UI は止まらない)。entryByRoot に LRU 上限 (maxCachedRoots = 4) を導入し、アプリ寿命での無制限保持をやめた。
- GitCommandRunner: timeout (既定 10 秒) を追加。読み取りを別スレッドで行いセマフォで待つ形にした。呼び出しスレッドで readDataToEndOfFile して watchdog から terminate() する実装だと、git が孫プロセスへ標準出力を渡していた場合に pipe が閉じず timeout が効かないため。標準入力も nullDevice で塞いだ。
- テストファイル分割: 表示時解決のブリッジテストを ViewerRendererResolveReferencesTests.swift へ切り出し (元ファイルが file_length 400 行を超えたため)。共有スタブは ViewerRendererMessageStubs.swift へ。

## 検証

- swift test: 684 tests / 99 suites 全通過 (Integration・FileWatcher 含む)
- npm test (jest): 295 tests 全通過
- swiftformat --lint: クリア / swiftlint: 変更ファイルに新規違反なし
- 新規テストの反証確認: 直列チェーンを外すと順序テストが失敗、Task.detached を MainActor.run に替えるとスレッドテストが失敗することを実際に確認した
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
表示時のパス解決をメインスレッドから外した。ViewerRenderer.onResolveReferences を async 化し、応答は Task の直列チェーンで要求順に評価することで JS 側の FIFO 契約を保ったまま非同期化。実解決は ViewerWindowController が要求時点の pathResolver/fileURL を捕捉して Task.detached で行う。あわせて GitCommandFileIndex に LRU 上限 (4 リポジトリ) を入れてアプリ寿命の無制限キャッシュをやめ、doc コメントを実態 (別リポジトリ間の直列化) へ修正し、GitCommandRunner に 10 秒のタイムアウトを追加した。swift test 684 件・jest 295 件全通過。順序保証とメインスレッド非ブロックの新規テストは、それぞれ直列チェーン除去・MainActor.run 置換で落ちることを確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
