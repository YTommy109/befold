---
id: TASK-315.1
title: ソース表示中のファイルの git 差分本文を取得する経路を作る
status: To Do
assignee: []
created_date: '2026-08-05 14:46'
labels: []
dependencies: []
parent_task_id: TASK-315
priority: medium
type: task
ordinal: 514000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 の 1 段目。差分の描画には手を付けず、Swift 側で「表示中のファイルの unified diff を取得して WebView 層まで届ける」経路だけを作る。

現状、差分本文を取る実装は無い。git 実行は `GitCommandRunner`（`BefoldApp/befold/App/GitCommandRunner.swift:105`）に一元化されており任意の引数を渡せるため、コマンド追加自体は容易。既存 8 コマンドはすべてメタデータのみで、`git diff` も `--name-status` でパス名しか取っていない（`GitStatusReader.swift:100-102`）。

制約:

- git 実行はメインアクター外が契約（`GitStatusReader.swift:26-29`）。既存の `GitStatusStore` は detached + inFlight 畳み込み + `.git/index` fingerprint キャッシュ（`GitStatusStore.swift:39-121`）で、同じ枠組みに乗せるか、乗せない理由を残す
- `GitCommandOutcome` は `.output` / `.rejected`（確定した答え）/ `.unavailable`（不明、キャッシュ禁止）の三値
- QuickLook 拡張（appex）では git を叩かない
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 表示中のファイルの unified diff を取得できる（比較対象の決定と、その根拠が実装ノートに記録されている）
- [ ] #2 未追跡・バイナリ・差分なし・git 管理外のそれぞれで、呼び出し側が区別できる結果が返る
- [ ] #3 git 実行がメインアクター外で行われ、タイムアウト・.unavailable がキャッシュされない
- [ ] #4 QuickLook 拡張の描画経路では差分取得が行われない
- [ ] #5 上記がユニットテストで検証されている（実 git リポジトリを使うテストを含む）
<!-- AC:END -->
