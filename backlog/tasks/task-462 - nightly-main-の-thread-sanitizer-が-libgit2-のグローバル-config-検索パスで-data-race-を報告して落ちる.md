---
id: TASK-462
title: >-
  nightly / main の thread-sanitizer が libgit2 のグローバル config 検索パスで data race
  を報告して落ちる
status: To Do
assignee: []
created_date: '2026-08-12 03:48'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 686000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
main への push で走る CI の thread-sanitizer ジョブが 2026-08-11 21:44 以降ずっと赤い（実測: gh run list --workflow CI --branch main で 31539279171 / 31543419487 / 31550549474 / 31552807815 / 31560824308 の 5 本すべて失敗ジョブは thread-sanitizer のみ。テスト自体は全件 pass しており、TSan のレポートで signal 6 になっている）。

## レース内容（実測: run 31560824308 のログ）

    WARNING: ThreadSanitizer: data race
      Write of size 8 by thread T1:
        git_str_set / git_sysdir_set / git_libgit2_opts
        befold_git_opts_set_search_path (CGitShim.c:4)
        GitLibraryTests.configSearchPathRoundTripsThroughShim() (GitLibraryTests.swift:100)
      Previous read of size 8 by thread T3:
        git_sysdir_find_programdata_file / git_config__find_programdata
        git_repository_config__weakptr / git_repository_open_ext
        GitLibrary.withRepository(at:_:) (GitLibrary.swift:94)
        GitLibraryTests.repeatedOpenOfUnopenableRepositoryIsSafe() (GitLibraryTests.swift:145)
      Location is global 'git_sysdir__dirs'

つまり、シムの往復テストが libgit2 のプロセスグローバルな PROGRAMDATA 検索パスを書き換えている最中に、並行実行中の別テストがリポジトリを開いて同じグローバルを読んでいる。

## 前提の誤り

configSearchPathRoundTripsThroughShim の doc コメントは「macOS では読まれない PROGRAMDATA レベルを使い、他テストが依存するレベルへ触れないようにする」と書いているが、上のスタックのとおり git_repository_open_ext は macOS でも git_config__find_programdata を通って PROGRAMDATA の dirlist を読む。レベルの選択では並行安全にならない。

## 検討すべき方向

- Swift Testing の .serialized は suite 内のみの直列化で、別 suite と並行に走るため単独では効かない
- libgit2 のグローバルを書き換えるテストを、libgit2 を使う全テストに対して排他にする仕組みが要る（共有ロック経由の入口へ一本化する等）か、書き換えを伴う往復検証そのものをやめる
- 着手前に /review-design を回すこと（既存の共通経路に触る変更のため）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 thread-sanitizer が報告していた git_sysdir__dirs の data race が解消している
- [ ] #2 レベルの選択ではなく構造で排他が担保されている（doc コメントの『macOS では読まれない』という誤った前提が残っていない）
- [ ] #3 main で CI が緑（thread-sanitizer を含む）
<!-- AC:END -->
