---
id: TASK-462
title: >-
  nightly / main の thread-sanitizer が libgit2 のグローバル config 検索パスで data race
  を報告して落ちる
status: Done
assignee: []
created_date: '2026-08-12 03:48'
updated_date: '2026-08-12 06:30'
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
- [x] #1 thread-sanitizer が報告していた git_sysdir__dirs の data race が解消している
- [x] #2 レベルの選択ではなく構造で排他が担保されている（doc コメントの『macOS では読まれない』という誤った前提が残っていない）
- [ ] #3 main で CI が緑（thread-sanitizer を含む）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitLibraryTests.configSearchPathRoundTripsThroughShim を削除する（libgit2 のプロセスグローバル git_sysdir__dirs を bootstrap 後に書き換える唯一の箇所。レベル選択では並行安全にならないという誤った前提ごと撤去する）。未使用になる import CGitShim も外す。
2. .swiftlint.yml に custom rule befold_git_opts_set_outside_git_library を追加し、befold_git_opts_set_search_path の参照を GitLibrary.swift 以外（テストを含む BefoldApp 配下の全 Swift）で error にする。既存の git_repository_open_outside_git_library と同型。
3. GitLibrary.bootstrap の doc に「初期化後に検索パスを書き換えない」理由（swift_once の happens-before が唯一の排他）を書き、lint rule と対応付ける。
4. シムの set/get の担保は disablesSystemAndXdgConfigSearchPaths（set→get で空文字）と keepsGlobalConfigSearchPathEnabled（get で HOME）に委ねる。production が set へ渡す値は "" のみなので測る値と守る値が一致する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
レビュー(/review-design)で該当した項目: 7(測るものと守るものの一致) / 9(決めた判断を守らせるもの) / 5(ライフサイクル・順序)。

対応:
- GitLibraryTests.configSearchPathRoundTripsThroughShim を削除。bootstrap 後に libgit2 のプロセスグローバル git_sysdir__dirs を書き換える唯一の箇所だった。doc の『macOS では PROGRAMDATA は読まれない』は誤り(実測: run 31560824308 のスタックで git_repository_open_ext → git_config__find_programdata が macOS 上で走る)ので、前提ごと撤去した。
- 書き手が bootstrap の static let(swift_once)だけになったことで、以降の読み手はすべて happens-before の後ろに並び、追加のロックなしで競合しない。
- 担保として GitLibraryTests.searchPathIsWrittenOnlyByGitLibrary を追加。BefoldApp 配下の .swift を走査し、検索パス set シムを書くファイルが GitLibrary.swift 以外に現れたら落ちる。探す識別子は連結で組み立てており、検査自身のファイルも対象に含まれる(今回の違反元がテストだったため、自ファイル除外の穴を開けていない)。
- シム set/get の担保は disablesSystemAndXdgConfigSearchPaths(bootstrap の set を get で読み戻す)と keepsGlobalConfigSearchPathEnabled(get で HOME)が兼ねる。production が set へ渡す値は空文字だけなので、測る値と守る値が一致する。

.swiftlint.yml の custom rule 案(befold_git_opts_set_search_path を GitLibrary.swift 以外で error)はユーザー判断で見送り、上記テストで代替した。

検証(実測):
- swift test --skip Integration --skip FileWatcherTests: 1336 tests 全 pass
- swift test --sanitize=thread --skip Integration --skip FileWatcherTests: 2 回実行。ThreadSanitizer: data race は 0 件。1 回目に ViewerStoreLoadRaceTests の 1 件が 60 秒の打ち切りに掛かったが、同 suite 単独の TSan 実行は 0.001 秒で pass、2 回目のフル実行は exit 0 で緑。負荷由来のフレークで本変更とは無関係。
- swiftformat: 差分なし。swiftlint: GitLibrary 関連の指摘なし。

AC #3(main の CI が緑)はマージ後の実測でのみ確認できる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
libgit2 の config 検索パス(プロセスグローバル git_sysdir__dirs)を書く箇所を GitLibrary.bootstrap の swift_once による一度きり初期化だけに閉じ、thread-sanitizer が報告していた data race を解消した。原因は、bootstrap 後に PROGRAMDATA レベルを書き換えていたシムの往復テスト。『macOS では PROGRAMDATA は読まれない』という前提が誤り(git_repository_open_ext は macOS でも git_config__find_programdata を通る)だったため、レベル選択ではなく書き込みそのものを撤去し、書き手が増えたら落ちるテスト(searchPathIsWrittenOnlyByGitLibrary)で担保した。検証: swift test 1336 件 pass、--sanitize=thread のフル実行 2 回で data race 0 件・2 回目は exit 0。AC #3 はマージ後の main の CI で確認する。
<!-- SECTION:FINAL_SUMMARY:END -->
