---
id: TASK-243
title: FileWatcher/ViewerStore 統合テストの固定待ちと直列化を見直し数秒短縮する
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-01 10:44'
updated_date: '2026-08-01 12:13'
labels: []
dependencies: []
priority: high
type: task
ordinal: 201000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CI レビューで、FileWatcher/ViewerStore 統合テストに規約(発火しない検証は時限+0.3s)を超える固定待ちと無根拠な直列化があり、合計 4〜6 秒級の壁時計を浪費していると判明した。
- FileWatcherIntegrationTests.swift:282 stopPreventsCallback の固定 1s(テスト注入 debounce 0.05s なら 0.35s で十分)
- ViewerStoreIntegrationTests.swift:98 closeStopsWatching の固定 1s(同上)
- ViewerStoreIntegrationTests.swift:22-51 onFileGone 検証が fileGoneGracePeriod = 1.0s を実時間で待つ。ViewerStore.swift:387 のグレース期間が static でプロダクト debounce 既定に固定されているのが原因で、watcherFactory に注入した debounce から導出すればテストでは自動的に 0.25s になる(仮想時刻でのロジック検証は ViewerStoreFileGoneTests が既に担っている)
- TestSupport.swift:37 confirmWatcherArmed の quiescePeriod 0.3s(debounce の 6 倍)は DebouncerTests の 3 倍基準と不整合。0.15s へ短縮すると .serialized スイート内 5 呼び出しで合計 ~1s 短縮
- FileWatcherIntegrationTests.swift:12 の @Suite(.serialized) に根拠コメントがない(ViewerStoreIntegrationTests.swift:6-8 は根拠明記済み)。各テストは独立 TempDir + watcher で共有状態がなく、解除できれば直列 5〜8s が最長テスト長(~1.5s)まで縮む
- FileWatcherIntegrationTests.swift:95 の根拠なし固定 0.2s
- 同 :255-258 の TempDir 未使用の手組み一時パス、watcher+LockedBox セットアップの 7 回反復(3 回以上でファクトリ抽出の規約に該当)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 発火しない検証の待機が規約の時限+0.3s に短縮され、待機時間の根拠コメントが付く
- [x] #2 fileGoneGracePeriod が注入 debounce から導出され、統合テストの実待ちが短縮される
- [ ] #3 FileWatcherIntegrationTests の .serialized を解除して CI で実測し、フレークする場合のみ根拠コメント付きで復活させる
- [x] #4 手組み一時パスと反復セットアップが TempDir / private ファクトリへ統一される
- [x] #5 swift test が全てグリーン
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerStore.fileGoneGracePeriod を static 定数からインスタンス導出へ変更(watcherFactory に注入された debounce 間隔 x5 で算出。プロダクト既定 0.2s では従来どおり 1.0s で挙動不変、テスト注入 0.05s では 0.25s)。/// と近接コメントの読み合わせ更新
2. TestSupport.swift confirmWatcherArmed の quiescePeriod 既定 0.3s→0.15s(テスト用 debounce 0.05s の 3 倍。DebouncerTests の settlePeriod 基準と整合)。根拠コメント更新、ピン留めテスト(QuiesceCutoffTests 等)があれば同期
3. FileWatcherIntegrationTests: stopPreventsCallback の固定 1s→debounce+0.3s(根拠コメント付き)、:95 の固定 0.2s→静穏 0.15s+根拠、:255-258 の手組み一時パス→TempDir、watcher+LockedBox セットアップ 7 回反復→private ファクトリ抽出、@Suite(.serialized) を解除
4. ViewerStoreIntegrationTests: closeStopsWatching の固定 1s→0.35s(根拠コメント)、onFileGone テストがグレース導出変更で自動短縮されることを確認。.serialized は根拠明記済みのため維持
5. swift test 全体グリーン確認 + 対象スイートのローカル実行時間を before/after 計測。CI 実測(.serialized 解除のフレーク判定)は PR の CI で行い、結果を notes に記録
スコープ外: rename/move ペアのパラメタライズ(TASK-250)、busy-yield 置換(TASK-247)
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
コミット: a4747da(本体) / 7a998a0(レビュー修正1) / 4afc8dd(ドキュメント整合)。
主な設計判断:
- fileGoneGracePeriod を static から導出値へ。当初は watcherDebounceDelay を別パラメータで自己申告する形にしたが、レビューで「MockFileWatcher 注入時に申告が省略され既定 1.0s に暗黙依存する箇所がある(実際に守られていない契約)」と判明。ユーザー判断により watcherFactory のシグネチャに debounceDelay を含める型担保方式へ変更し、呼び出し側 10 箇所を機械的置換。同一変数から grace と factory 引数の両方が導出されるため申告ズレが原理的に起きない
- confirmWatcherArmed の quiescePeriod は当初 0.15s(DebouncerTests の 3 倍基準)にしたが、待つ経路が kevent 配送→監視キュー→デバウンス→@MainActor ホップを含み前提が異なること、テスト側 sleep は global pool で時間どおり起きるため MainActor 混雑時に静穏を誤判定して検証が静かに弱体化するリスクが指摘され、ユーザー判断で 0.35s(N+0.3s)に。時間短縮の利得は元々小さい(臨界パスへの寄与 0.3s 程度)
- 「発火しない」検証の待機は debounce 単独でなく rename 経路(renameSettleDelay + debounceDelay = 0.1s)+0.3s = 0.4s へ修正
- ViewerStoreIntegrationTests の .serialized は維持。FileWatcherIntegrationTests と構造的な区別理由は見つからなかったが、解除検証をしていないため予防的に維持する旨をコメントと調査ドキュメント双方に明記
検証: ローカル swift test フル実行を実装者3回+レビュー担当3回+最終1回の計7回実施し全てグリーン(1006 tests/134 suites)。swiftformat 差分なし、swift build 警告なし、markdownlint-cli2 0 issues。
AC #3 の CI 実測は未実施(未 push のため)。PR 作成後に build-and-test と thread-sanitizer の結果を確認し、フレークする場合は根拠コメント付きで .serialized を復活させる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FileWatcher/ViewerStore 統合テストの固定待ちと直列化を見直し、ローカル実測で FileWatcherIntegrationTests を 14.2s→約 10s に短縮した(全体 14.2s→13.4s。全体はスコープ外の GitCommandRunnerTests が新たな律速)。
変更点: (1) ViewerStore の fileGoneGracePeriod を static 定数から watcherFactory に渡す debounce の導出値へ変更し、シグネチャに debounceDelay を含めることで申告ズレを型で防止 (2) confirmWatcherArmed の静穏待ちを経路根拠(kevent 配送〜MainActor ホップ)に基づく 0.35s へ (3) 「発火しない」検証の待機を rename 経路を数えた N+0.3s へ修正 (4) 手組み一時パスを TempDir へ、watcher セットアップ 6 回反復を private ファクトリへ (5) FileWatcherIntegrationTests の .serialized を解除。
検証: ローカル swift test フル実行 7 回すべてグリーン(1006 tests)、swiftformat/SwiftLint/markdownlint クリーン。CI 実測(AC #3)は PR 作成後に確認する。
<!-- SECTION:FINAL_SUMMARY:END -->
