---
id: TASK-92
title: CLIInstaller.install の symlink 設置がアトミックでなく失敗時にコマンドが消える
status: Done
assignee:
  - '@claude'
created_date: '2026-07-21 10:49'
updated_date: '2026-07-21 11:02'
labels: []
dependencies:
  - TASK-90
priority: high
type: bug
ordinal: 77000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-90 で /usr/local/bin/befold のシム設置をファイルコピーからsymlink方式に変更した際、CLIInstaller.writeDirectly(target:to:) が「既存アイテムを削除 → 新規symlinkを作成」という非アトミックな2ステップ処理になった(CLIInstaller.swift:36)。

旧実装(TASK-90以前)は一時ファイルへの書き込み+atomically:trueによるアトミックな置き換えだったため、書き込みが失敗しても旧シムはそのまま残っていた。現行実装では、削除後のcreateSymbolicLink(atPath:withDestinationPath:)が何らかの理由(権限・ディスク状態など)で失敗した場合、writeDirectlyはfalseを返してwriteWithAdministratorPrivilegesにフォールバックするが、そちらも失敗する(例: ユーザーが管理者権限プロンプトをキャンセルする)と、CLIInstaller.installは.failureを返す一方で、既に動いていた旧シムは削除済みで復元されない。

再インストールを試みたユーザーが「動いていたbefoldコマンドが完全になくなる」という、再インストール前より悪化した状態に陥りうる。TASK-91で追加した起動時の自動再インストール推奨フローにより、この失敗パスに到達するユーザーが増える可能性がある点も踏まえ優先度を高くする。

対応方針: 一時パスにsymlinkを作成してから、既存の設置先へアトミックに置き換える(例: FileManager.replaceItem(at:withItemAt:)や rename(2) 相当の操作)方式に変更し、作成失敗時は既存の設置内容を変更しないようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 symlink作成に失敗した場合、installPathの既存の内容(旧シムファイル・旧symlinkなど)が変更されずに残る
- [x] #2 symlink作成に成功した場合のみ、installPathの内容が新しいsymlinkに置き換わる
- [x] #3 既存の3パターン(旧実体ファイル/既存symlink/未設置)からの正常インストールが引き続き成功する
- [x] #4 CLIInstallerTests.swiftに、symlink作成失敗時に既存の設置内容が保持されることを検証するテストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
writeDirectly(target:to:)を、既存を先に削除する方式から「同一ディレクトリの一時パスへsymlink作成→rename(2)でアトミックに置換」方式に変更(privateからstaticに変更しテスト可能にした)。FileManager.replaceItemAt/moveItemはドキュメント向けのメタデータ保持処理を伴いsymlink(特にダングリング)に対して極端に遅い(実測100秒超)/参照先が更新されないという不正動作を示したため不採用とし、Darwinのrename(2)を直接使用した。同じ非アトミック性の問題が管理者権限フォールバック側のシェルコマンド(administratorInstallShellCommand: rm -f && ln -s)にもあったため、同様に一時パスへln -sしてからmv -fでアトミックに置き換える方式に修正した(既存テストadministratorInstallShellCommandCreatesSymlinkもパターンに合わせて更新)。CLIInstallerTests.swiftに、書き込み先ディレクトリを読み取り専用にしてsymlink作成自体を失敗させ、既存の実体ファイルシムが変更されずに残ることを検証するテストを追加。swift test(Integration/FileWatcherTests除く)556件全て成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLIInstaller.writeDirectly()が「既存削除→symlink作成」の非アトミック処理だったため、作成失敗時にコマンドが完全に消えうる問題を修正。同一ディレクトリの一時パスへsymlinkを作成し、rename(2)でアトミックに置換する方式に変更(FileManager.replaceItemAt/moveItemはsymlinkに対して不正動作・大幅な遅延を示したため不採用)。同種の問題があった管理者権限フォールバックのシェルコマンドも一時パス+mv -fのアトミック方式に修正。新規テストで、書き込み失敗時に既存シムが保持されることを検証。swift test全556件成功。
<!-- SECTION:FINAL_SUMMARY:END -->
