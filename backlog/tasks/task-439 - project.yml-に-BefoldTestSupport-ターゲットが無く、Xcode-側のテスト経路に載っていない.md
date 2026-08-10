---
id: TASK-439
title: project.yml に BefoldTestSupport ターゲットが無く、Xcode 側のテスト経路に載っていない
status: To Do
assignee: []
created_date: '2026-08-10 15:08'
labels:
  - ci
dependencies: []
priority: medium
type: task
ordinal: 672000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-435 の調査中に判明した既存のずれ。TASK-435 とは独立に存在する。

`BefoldApp/Package.swift` は `BefoldTestSupport` を独立ターゲットとして定義し、`befoldTests` / `befoldCLITests` の双方が dependencies に列挙している（Package.swift:91-107）。一方 `BefoldApp/project.yml` には **`BefoldTestSupport` の記述が 1 件も無い**（`grep -n BefoldTestSupport BefoldApp/project.yml` が 0 件）。`befoldTests` ターゲットの dependencies も `befold` / `BefoldKit` / `BefoldRenderKit` の 3 つだけ（project.yml:159-171）。

## 影響（未確認を含む）

`BefoldTestSupport/GitTestRepo.swift` を使うテスト（`GitCommandRunnerTests` / `GitStatusReaderIntegrationTests` / `GitDiffReaderIntegrationTests` / `GitRepositoryIntegrationTests` の計 43 本）が、`swift test` では実行される一方、Xcode 側（`xcodebuild test`）でどう扱われているかが未確認。次のいずれかのはず。

- そもそも `.xcodeproj` の befoldTests にソースが含まれずビルドから落ちている
- 何らかの経路で拾われている

**着手時にまず `xcodegen generate` した `.xcodeproj` の befoldTests のソース一覧を実測して、どちらかを確定させること。**

## なぜ今起票するか

TASK-435.1 の設計レビューで、新しいテストフィクスチャを `BefoldTestSupport` に置くと同じずれに載ってしまうことが分かった。435.1 側は `befoldTests` へ置いて回避するが、ずれ自体は残るため独立して扱う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 xcodegen が生成する .xcodeproj で befoldTests が BefoldTestSupport のソースをどう扱っているかが実測で確定している
- [ ] #2 Package.swift と project.yml のターゲット構成のずれが解消されている（project.yml へ追加するか、ずれてよい理由が記録されている）
- [ ] #3 CI で実際に走るテスト集合が swift test と xcodebuild test で一致することが確認されている
<!-- AC:END -->
