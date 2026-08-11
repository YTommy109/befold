---
id: TASK-442.6
title: SidebarNavigator の git 依存クロージャをプロトコルへ置き換える
status: To Do
assignee: []
created_date: '2026-08-11 11:41'
labels: []
dependencies:
  - TASK-442.4
parent_task_id: TASK-442
priority: medium
type: chore
ordinal: 678000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-442.4 の設計レビュー（responsibility-reviewer）で、親 TASK-442 の AC#4「注入クロージャ 3 個以下」を 442.4 の中で満たそうとするのは数合わせになると判明したため切り出した。

現状 SidebarNavigator.init の注入クロージャは 5 本（directoryLister / childrenLister / resolveGitRoot / loadGitStatuses / makeGitIndexWatcher）。このうちプロダクトが実際に渡すのは resolveGitRoot / loadGitStatuses の 2 本だけで（ViewerWindowAssembler.swift:48,51）、残り 3 本はテスト専用の既定値。

却下した案: resolveGitRoot / loadGitStatuses / makeGitIndexWatcher を 1 つの struct へ束ねる。本数は変わらず保持先が移るだけで、442.4 が「書き込み先も用途も別」として 2 型へ分けた関心が依存値の側で 1 つに戻る。makeGitIndexWatcher の既定は FileWatcher であって git ではないため GitAccess 等の名前も嘘になる。

採る案: git アクセスをプロトコル 1 個へ置き換える。

    protocol SidebarGitReading {
        func repositoryRoot(forDirectoryAt url: URL) async -> URL?
        func statuses(forDirectoryAt url: URL, policy: GitStatusRefreshPolicy) async -> GitStatusResult
    }

クロージャは git 型を SidebarNavigator から隠すためだけに存在する（SidebarNavigator.swift の doc がそう記録している）。assembler は既に gitFileIndex: any GitFileIndexing と gitStatusStore: GitStatusStore を持っているため、プロトコルなら隠蔽を保ったまま依存が 1 個になり、既定は空実装の型で与えられる。

makeGitIndexWatcher はファイル監視でありこのプロトコルには入れない（init 引数として別枠で残る）。したがって init 引数は 5 → 4 になり、親 AC#4 の「3 個以下」には届かない。3 個以下を目標にするなら、directoryLister / childrenLister を同様に 1 つのプロトコル（ディレクトリ列挙）へ束ねる案を別途検討すること。

波及範囲: ViewerWindowAssembler.swift と SidebarNavigator を生成するテスト 10 ファイル。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 git ルート解決と git status 取得が 1 つのプロトコルへまとまり、SidebarNavigator.init のクロージャ引数から resolveGitRoot / loadGitStatuses が消えている
- [ ] #2 テスト用の既定実装が型として与えられ、各テストがクロージャ 2 本を個別に渡す形になっていない
- [ ] #3 makeGitIndexWatcher をこのプロトコルへ含めていない（ファイル監視であり git アクセスではない）
- [ ] #4 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->
