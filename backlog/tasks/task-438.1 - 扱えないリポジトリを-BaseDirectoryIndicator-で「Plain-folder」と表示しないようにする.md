---
id: TASK-438.1
title: 扱えないリポジトリを BaseDirectoryIndicator で「Plain folder」と表示しないようにする
status: To Do
assignee: []
created_date: '2026-08-13 13:59'
updated_date: '2026-08-14 05:49'
labels:
  - ux
  - git
dependencies: []
parent_task_id: TASK-438
priority: medium
type: bug
ordinal: 110100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-438 の決定（論点 1: 区別する。ただし BaseDirectoryIndicator の 1 箇所のみ）の実装。

## 現状の問題

BaseDirectoryIndicator.swift:12,26-27 はアイコンとツールチップを kind == .gitRoot の二値で決めている。kind は SidebarBaseDirectoryResolver.swift:48 の repositoryRoot(forDirectoryAt:) -> URL? 由来で、libgit2 が開けないリポジトリ（partial clone / reftable / 未知の extensions.*）はここが nil になる。結果、**git リポジトリなのに folder アイコン + 「Plain folder」と表示される**。これは静かな縮退ではなく事実と異なる表示。

BaseDirectoryIndicator は FeatureGate 配下ではないため stable のユーザーに見える。ADR の縮退 3 点のうちサイドバーのバッジ（FeatureGate.isSidebarGitStatusEnabled）と差分（isSourceDiffEnabled）は dev 限定なので、stable での実害はこの 1 箇所に集中している。

## 方針

- 表示を 3 状態にする。git ルート / ただのフォルダ / **git リポジトリだが扱えない**
- 扱えない場合のアイコンは arrow.triangle.branch のままにし、ツールチップで「befold では扱えないため git 機能は無効」であることを伝える
- **バナー・注記行は足さない。モーダルも取らない**（ADR の「静かに落とす」方針は維持する）
- **失敗理由の種別は出さない**。GitLibrary.OpenFailure（GitLibrary.swift:30-38）は partial clone / reftable / 未知拡張を .unusable の 1 値へ意図的に畳んでおり（エラーメッセージは版差のため見ない = GitLibrary.swift:116-117）、理由別の文言は型が持たない情報を騙ることになる

## 配線

新しい状態は増やさない。GitRootLookup（GitRepository.swift:7-17）は既に .root / .notARepository / .undetermined を区別しており、SidebarGitReading.repositoryRoot(forDirectoryAt:) -> URL?（SidebarGitReading.swift:26）が URL? へ潰す時点で情報が捨てられている。**捨てている情報を UI まで通すだけ**。戻り型の変更が起点になる。

Localizable.xcstrings へキーを追加する際は、キー順にソートし直さず近縁キー（sidebar.baseDirectory.*）の直後に挿入すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 libgit2 が開けないリポジトリを開いたとき、BaseDirectoryIndicator が「Plain folder」と表示しない
- [ ] #2 その状態で git リポジトリではあるが befold では扱えないことがツールチップから分かる
- [ ] #3 失敗理由の種別（partial clone / reftable / 未知拡張）を文言に出していない
- [ ] #4 git ルート / ただのフォルダ / 扱えないリポジトリの 3 状態が、扱えないリポジトリのフィクスチャを使ったテストで固定されている（GitUnusableRepositoryTests のフィクスチャが流用できる）
<!-- AC:END -->
