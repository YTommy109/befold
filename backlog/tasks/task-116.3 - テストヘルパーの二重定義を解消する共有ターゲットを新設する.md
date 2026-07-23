---
id: TASK-116.3
title: テストヘルパーの二重定義を解消する共有ターゲットを新設する
status: To Do
assignee: []
created_date: '2026-07-23 23:18'
labels:
  - test
  - cleanup
dependencies: []
parent_task_id: TASK-116
priority: medium
ordinal: 30300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befoldCLITests/TestSupport.swift`(本ブランチ新規 +49 行)が `BefoldApp/befoldTests/TestSupport.swift` の一部をソースコピーしており、単一情報源の原則に反している。

## 複製されている実体

- `makeIsolatedDefaults(prefix:)` — CLI 側 L44-49 と GUI 側 L4-9 が**バイト一致**
- `TempDir` — CLI 側 L9-39 と GUI 側 L14-66。init / deinit / `file(named:contents:)` は同一

## 既に発生している乖離と実害

- `symlinkedFile` の既定名が CLI 側 L31 は `"real.md"/"link.md"`、GUI 側 L58 は `"real.mmd"/"link.mmd"`。同名メソッドが片方は Markdown、片方は Mermaid を作る
- CLI 側には `LockedBox` / `waitUntil` / `waitUntilWithRetry` / `file(atPath:)` / `file(named:data:)` が無い
- **その結果として `befoldCLITests/CLIAppLauncherTests.swift:18-23` が `LockedBox` 相当を `nonisolated(unsafe) var` + `DispatchSemaphore` で手組みし、coding_rule.md の「`Sendable` クロージャからの記録・カウントは `LockedBox` を使う。自作は違反」に真正面から抵触している**

複製のコストが仮定ではなく既に実害として現れている。

## 複製理由の再評価

CLI 側 L7-8 は「befoldTests -> befold(GUI 本体) -> BefoldRenderKit の依存グラフを引き込まないため」と説明する。動機自体は正当だが、ソースコピー以外の選択肢が検討された形跡が無い。`TempDir` / `LockedBox` / `makeIsolatedDefaults` / `waitUntil` はいずれも Foundation のみに依存するため、依存ゼロの第 3 ターゲットを立てれば GUI への依存を 1 本も増やさずに単一情報源を保てる。

coding_rule.md の「『現状維持でよい』は代替実装を実際に試して比較した後にのみ許される結論」に従い、この案を実際に試してから複製維持の可否を判断すること。

## ドキュメントのドリフト

`docs/dev/coding_rule.md:79` は `befoldTests/TestSupport.swift = 共有ヘルパー` とだけ書き、L80 の befoldCLITests の説明に 2 つ目の TestSupport の存在が記載されていない。`.claude/CLAUDE.md` のプロジェクト構成ツリーも同様。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TempDir / LockedBox / makeIsolatedDefaults / waitUntil 系の実体が 1 箇所にのみ存在する
- [ ] #2 共有ヘルパーが GUI 本体(befold ターゲット)への依存を持ち込まない
- [ ] #3 befoldCLITests から LockedBox が使え、CLIAppLauncherTests の手組みボックスが除去されている
- [ ] #4 symlinkedFile の既定拡張子の食い違いが解消されている
- [ ] #5 coding_rule.md と .claude/CLAUDE.md のプロジェクト構成が実態と一致している
<!-- AC:END -->
