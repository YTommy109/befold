---
id: TASK-322
title: refreshDiff がメインスレッドで git rev-parse を実行し UI をブロックし得る問題を修正する
status: Done
assignee: []
created_date: '2026-08-05 16:08'
updated_date: '2026-08-05 18:41'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: medium
type: bug
ordinal: 506000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

ViewerWindowController+Diff.swift:24 の refreshDiff は、コンテンツリロードのたびに gitFileIndex.repositoryRoot(forDirectoryAt:) を MainActor 上で同期呼び出しする。rootByDir キャッシュにない ディレクトリでは GitCommandFileIndex が git rev-parse サブプロセスを実行し、GitCommandRunner のタイムアウトは 10 秒 + terminationGrace 5 秒。GitDiffReading 自身の契約（「必ずメインアクターの外で呼ぶこと」）が diff 本体を Task.detached に逃がしているのと同種のブロッキングが、root 解決だけメインスレッドに残っている。

症状: ネットワークボリュームや応答の遅い git など、コールドな環境でルート未キャッシュのファイルを開く/切り替えるたびに、rev-parse が返るまで最大タイムアウト分メインスレッドが停止しアプリ全体がビーチボールになる。

修正: root 解決も含めて非同期経路（Task 内・detached）へ移す。TASK-226（GitCommandRunner async 化・GitCommandFileIndex actor 化）と関連するため、先行着手する場合は重複しない範囲で直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ルート未キャッシュのディレクトリのファイルを開いても、git 応答待ちでメインスレッドがブロックしない
- [x] #2 root 解決失敗時（リポジトリ外）の挙動は従来どおり差分なし表示になる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 単純化の検討（実装前）

同じ問題（git のサブプロセスをメインアクターから追い出す）は既に ViewerWindowController.swift:196 が `await Task.detached { gitFileIndex.repositoryRoot(forDirectoryAt:) }.value` の形で解いている。新しい仕組みは足さず、その前例へ合わせた。TASK-226（GitCommandFileIndex の actor 化）を待つ必要はなく、待つと当面 UI が止まり続ける。

## 修正

refreshDiff のルート解決を差分取得と同じ Task の中へ入れ、`Task.detached(priority: .utility)` で行う。ルートが取れなかった場合の `store.diffText = nil` も、着地時と同じく URL 一致を確認してから行う（非同期になったため、遅れて届いた失敗が新しいファイルの差分を消さないように）。

## 検証

- `swift test` 1151 green（新規 1 件: 差分の取り直しはリポジトリルート解決でメインアクターを止めない）
- **テストが空振りしていないことを確認**: ルート解決を同期呼び出しへ戻すと当該テストだけが落ちる（`(elapsed → 0.5001910924911499) < (delay / 2 → 0.25)`）。戻して再度 green
- **空振りを 2 回踏んで直した**（記録）:
  1. 最初は `preference.isEnabled = true` だけで測ったが、ゲート無効ビルドでは `diffLoader` が nil のため refreshDiff がルート解決へ到達せず、修正の有無に関わらず通っていた → `controller.diffLoader` へスタブ取得器を注入
  2. 次にスタブ索引で `repositoryRoot(forDirectoryAt:)` を上書きしたが、これは**プロトコル要件ではなく拡張だけの実装**で静的ディスパッチのため `any GitFileIndexing` 越しには呼ばれず、やはり通っていた → プロトコル要件である `repositoryRoot(forFileAt:)` 側を遅くする形へ変更
- swiftformat --lint: 0 件 / swiftlint: 変更 3 ファイルとも main とのベースライン差分ゼロ
- テスト用に ViewerWindowControllerFixture へ gitFileIndex の注入口を追加した
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
コンテンツ再読込のたびにメインアクター上で同期実行されていたリポジトリルート解決（キャッシュミス時は git rev-parse のサブプロセス）を、差分取得と同じ detached タスクへ移した。同種の問題を既に解いている ViewerWindowController.swift:196 の形に合わせ、新しい仕組みは足していない。ルート解決に失敗した場合の差分クリアも、非同期化に伴い URL 一致確認の内側へ移した。検証は swift test 1151 green と、同期呼び出しへ戻すと当該テストが 0.50 秒ブロックして落ちることの実測。テスト自体が 2 度空振りしていた（ゲート無効で早期 return、プロトコル拡張の静的ディスパッチ）ため、両方を潰してから確定させた。
<!-- SECTION:FINAL_SUMMARY:END -->
