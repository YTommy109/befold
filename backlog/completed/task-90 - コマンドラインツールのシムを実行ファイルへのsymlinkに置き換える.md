---
id: TASK-90
title: コマンドラインツールのシムを実行ファイルへのsymlinkに置き換える
status: Done
assignee:
  - '@claude'
created_date: '2026-07-21 10:26'
updated_date: '2026-07-21 10:32'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在 /usr/local/bin/befold は CLIInstaller.shimScriptContents(bundlePath:) が生成する固定内容のシムスクリプト(exec <bundle>/Contents/MacOS/befold "$@")をファイルとしてコピー設置している。このため befold.app がアップデートされてシムの実装方針が変わっても、既にインストール済みの /usr/local/bin/befold の中身は追随せず古いロジックのまま残り続ける。実例として、旧バージョンでは exec open -a "<bundle>" "$@" という別方式のシムが使われており、これがインストールされたままの環境では befold --help がbefold自身のヘルプではなく macOS 標準の open コマンドのヘルプを表示してしまう不具合が発生した。

対応方針: /usr/local/bin/befold を、バンドル内の実行ファイル(Contents/MacOS/befold)への symlink として設置する方式に変更する。現行シムは引数を透過して exec するだけの役割しか持たないため、symlink化により中間スクリプトファイルという概念自体が不要になる。symlinkはパスベースで解決されるため、Sparkleによるアプリの同一パスへの上書き更新後も自動的に最新の実行ファイルを指すようになり、ユーザーが再インストールを実行し直さなくても常に最新のロジックで動作する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLIInstaller.install が /usr/local/bin/befold(または指定installPath)にシムスクリプトファイルではなくsymlinkを作成する
- [x] #2 symlinkの参照先が <bundlePath>/Contents/MacOS/befold である
- [x] #3 既存の実体ファイル(旧バージョンの静的シムスクリプト)や既存のsymlinkが残っている状態でinstallを実行すると、新しいsymlinkに置き換わる(削除してから作成)
- [x] #4 管理者権限フォールバック経路(writeWithAdministratorPrivileges)でも同様にsymlinkが設置される
- [x] #5 CLIInstallerTests.swift に、旧形式(実体ファイル)からの移行・既存symlinkの上書き・新規インストールの3パターンのテストがある
- [x] #6 README/ヘルプに、アプリを /Applications から移動した場合は再度「コマンドラインツールをインストール」の実行が必要である旨の記載がある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLIInstaller.swift を symlink 方式に書き換え(targetExecutablePath/administratorInstallShellCommand を追加、shimScriptContents を削除)。CLIInstallerTests.swift に新規/旧実体ファイル移行/既存symlink上書き/管理者権限コマンド組み立ての4テストを追加。BefoldRootCommand.swift の discussion と README.md にアプリ移動時の再インストール案内を追記。swift test (Integration/FileWatcherTests除く)550件全て成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
/usr/local/bin/befold の設置方式をシムスクリプトのファイルコピーから、バンドル内実行ファイル(Contents/MacOS/befold)へのsymlinkに変更。CLIInstaller.install/writeDirectly/writeWithAdministratorPrivilegesを書き換え、既存の実体ファイル・symlinkは削除してから新規symlinkを作成するようにした。CLIInstallerTests.swiftの5テスト(新規作成・旧形式移行・既存symlink上書き・管理者権限コマンド組み立て・targetExecutablePath)で検証。BefoldRootCommand.swiftのヘルプ本文とREADME.mdに、アプリを/Applications以外へ移動した場合は再インストールが必要である旨を追記。swift test全550件成功(Integration/FileWatcherTests除く)。
<!-- SECTION:FINAL_SUMMARY:END -->
