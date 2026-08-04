---
id: TASK-94.1
title: help のオプション部分と--version機能を実装する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-22 02:21'
updated_date: '2026-07-22 11:21'
labels: []
dependencies: []
parent_task_id: TASK-94
ordinal: 80000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`befold --help` に --version がない。CURRENT_PROJECT_VERSION 等、既存のバージョン管理の仕組みを調査し、`befold --version`(および慣例に合わせ `-v` も検討)でアプリのバージョン文字列を標準出力してプロセスを正常終了するようにする。
対象: BefoldApp/befold/App/BefoldRootCommand.swift (CommandConfiguration に version: を渡す、または独自実装)。
参考: swift-argument-parser は CommandConfiguration(version:) で --version を自動生成できる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold --version を実行するとアプリのバージョン文字列が標準出力に印字され、終了コード0で終了する
- [x] #2 バージョン文字列はアプリ本体(Info.plist の CFBundleShortVersionString 等)と一致し、二重管理にならない
- [x] #3 既存の CLI テスト(BefoldRootCommandTests 等)に --version の挙動を検証するテストが追加される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. (当初案) Package.swift に -sectcreate __TEXT __info_plist で befold/Info.plist を埋め込み、SPM ビルドでも Bundle.main から CFBundleShortVersionString を読む案を試したが、TDDのRED確認で判明: Info.plist の $(MARKETING_VERSION) はXcodeのInfoplist処理でのみ置換されるため、SPMの生埋め込みでは未置換のままになり成立しない。ユーザーに報告し方針変更。
2. (採用案) befold/App/AppVersion.swift に AppVersion.current = "1.7.2" を新設し、CLI --version の単一情報源とする。project.yml の MARKETING_VERSION(配布アプリのバンドルバージョン表示用)とは別管理のままとなり、リリース時に手動同期が必要(コメントで明記)。
3. TDD: BefoldRootCommand.configuration.version が AppVersion.current と一致するテストを先に書き、失敗確認後、CommandConfiguration に version: AppVersion.current を追加して実装。
4. TDD: 実際にビルドされた befold 実行ファイルをサブプロセスとして --version 付きで起動し、標準出力とexit code 0を検証するテストを先に書き、失敗確認後に実装(ArgumentParser内部のCommandError/MessageInfoがinternalで直接検証できないため、この経路が唯一の実挙動検証)。
5. 既存の BefoldRootCommandTests・swift test 全体(558件)が壊れていないことを確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。swift test --filter BefoldRootCommandTests で新規2テストが RED→GREEN を確認、swift test --skip Integration --skip FileWatcherTests で全558件成功。swift run befold --version の手動実行でも 1.7.2 / exit=0 を実機確認。AC#2は project.yml の MARKETING_VERSION とは別の Swift 定数(AppVersion.swift)を単一情報源とする方式に変更(Info.plist埋め込み案はTDDのRED確認中に $(MARKETING_VERSION) 未置換問題が発覚したため断念、ユーザー承認済み)。project.yml側は引き続き手動同期が必要である点をコメントに明記した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BefoldRootCommand の CommandConfiguration に version: AppVersion.current(新設した befold/App/AppVersion.swift の定数、現在"1.7.2")を追加し、befold --version でバージョン文字列を標準出力に印字し終了コード0で終了するようにした。TDDで先にRED(configuration.versionの一致テスト、実バイナリをサブプロセス起動しstdout/exit codeを検証するテスト)を確認してから実装。project.yml のInfo.plist埋め込み経由での自動一致案はSPMビルドで$(MARKETING_VERSION)が未置換になる問題が判明したため断念し、Swift定数を単一情報源とする方式に変更(project.yml側のMARKETING_VERSIONとは手動同期が必要、コメントで明記)。swift test(558件、Integration/FileWatcherTests除く)全て成功、swift run befold --version の実機確認も実施。
<!-- SECTION:FINAL_SUMMARY:END -->
