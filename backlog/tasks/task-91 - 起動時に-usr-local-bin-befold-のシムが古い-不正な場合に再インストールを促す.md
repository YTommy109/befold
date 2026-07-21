---
id: TASK-91
title: 起動時に /usr/local/bin/befold のシムが古い/不正な場合に再インストールを促す
status: Done
assignee:
  - '@claude'
created_date: '2026-07-21 10:26'
updated_date: '2026-07-21 10:38'
labels: []
dependencies:
  - TASK-90
priority: medium
type: enhancement
ordinal: 76000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
symlink化(TASK-90)により今後のアプリ更新には自動追随するが、symlink化そのものが適用されるのは既存ユーザーが一度「コマンドラインツールをインストール」を再実行した後に限られる。それまでの間、旧バージョンの実体ファイルシムや、古いバンドルパスを指すダングリングsymlinkが残ったままになるユーザーが一定数存在する見込みである。

対応方針: アプリ起動時に /usr/local/bin/befold の状態を読み取り専用でチェックし、(a) 存在するが symlink でない(旧形式の実体ファイル)、(b) symlink だが参照先が現在のバンドル実行ファイルと一致しない、のいずれかに該当する場合、ユーザーに「コマンドラインツールを再インストールしてください」という軽量な通知(バナー等)を表示する。sudo昇格を伴う書き込みは行わず、検知と案内のみに留める(自動修復はスコープ外)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 アプリ起動時に /usr/local/bin/befold の状態(未インストール/実体ファイル/symlinkかつ参照先一致/symlinkかつ参照先不一致)を判定するロジックがある
- [x] #2 実体ファイルまたは参照先不一致のsymlinkが検出された場合のみ、再インストールを促す通知が表示される
- [x] #3 未インストール、または既に正しいsymlinkの場合は通知が表示されない
- [x] #4 通知の書き込み処理(sudo昇格)は行わず、検知・案内のみである
- [x] #5 同一セッション/同一起動で通知が繰り返し表示されない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLIShimInspector.swift を新規追加(status(bundlePath:installPath:)で notInstalled/upToDate/legacyFile/staleSymlinkを読み取り専用判定、書き込みなし)。CLIShimInspectorTests.swiftに5テスト(未設置/最新symlink/旧実体ファイル/参照先不一致symlink/ダングリングsymlink)を追加、TDDで実装。AppDelegate.applicationDidFinishLaunchingの末尾でnotifyIfCLIShimIsStale()を1回だけ呼び、legacyFile/staleSymlinkの場合のみCLIInstallUI.presentReinstallRecommended()(新規NSAlert、書き込み処理なし)を表示するよう配線。CLIInstaller.defaultInstallPathを新設しinstallCLIアクションと共有。Localizable.xcstringsにcli.install.reinstallRecommended(ja/en)を追加。swift test(Integration/FileWatcherTests除く)555件全て成功。AppDelegateの起動フロー自体はプロジェクト規約によりGUI層で自動テスト対象外のため、実機でのアラート表示は手動確認を推奨(コードレビューでは判定ロジック・呼び出し箇所とも意図通り)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
起動時に/usr/local/bin/befoldの状態を読み取り専用でチェックするCLIShimInspectorを追加し、AppDelegate.applicationDidFinishLaunchingから1回だけ呼び出すよう配線。旧実体ファイル(legacyFile)または参照先不一致のsymlink(staleSymlink)を検出した場合のみ、CLIInstallUI.presentReinstallRecommended()でメニューからの再インストールを促すアラートを表示する(書き込み処理は一切行わない)。未インストール・最新symlinkの場合は何も表示しない。CLIShimInspectorTests.swiftの5テストで判定ロジックを検証、swift test全555件成功。GUI層(NSAlert表示自体)はプロジェクト規約により自動テスト対象外のため、リリース前に実機での手動確認を推奨。
<!-- SECTION:FINAL_SUMMARY:END -->
