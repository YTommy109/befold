---
id: TASK-627
title: ローカル Xcode 27.0 で swift build が main() must be '@MainActor' で落ちる
status: To Do
assignee: []
created_date: '2026-09-16 00:36'
labels:
  - build
dependencies: []
priority: high
type: bug
ordinal: 824000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
clean な作業ツリー（HEAD c2bea481）で `swift build` が次のエラーで落ちる。

```
BefoldApp/befold/App/AppDelegate.swift:73:29: error: main() must be '@MainActor'
    nonisolated static func main() {
```

実測（2026-09-16）:
- ローカル: Xcode 27.0（27A266a）/ Apple Swift 6.4
- CI ピン: 26.6（`.github/workflows/ci.yml` と `release.yml`）
- ローカルには Xcode 27.0 しか無く、`xcode-select` で古い方へ戻せない

Swift 6.4 が `nonisolated static func main()` を許さなくなったことによるツールチェーンずれ。TASK-619 と同型（Xcode の自動アップデートでローカルが CI ピンより先に進む）。

`@MainActor` を付ける 1 行修正で通る見込みだが、CI ピン（26.6）側でも通ることを確認してから入れること。あわせて CI ピンを 27.0 へ上げるかどうかも決める。

編集ごとの PostToolUse フックが `swift build` / `swift test` を回すため、この状態では Swift ファイルの編集が全てフック失敗になる（実害あり）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ローカル（Xcode 27.0 / Swift 6.4）で swift build と swift test が通る
- [ ] #2 CI ピン（Xcode 26.6）でもビルドが通り、CI が緑のままである
- [ ] #3 CI ピンを 27.0 へ上げるか据え置くかを決め、決めた理由を Notes に残す
<!-- AC:END -->
