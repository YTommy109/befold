---
id: TASK-125
title: CLI インストールが App Translocation 下で消滅する symlink を作る
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:22'
updated_date: '2026-07-25 01:30'
labels:
  - cli
  - bug
dependencies: []
priority: high
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で確認(CONFIRMED)。CLIInstaller.install(CLIInstaller.swift:27)は呼び出し元(AppDelegate.swift:262 の Bundle.main.bundlePath)が渡すバンドルパスをそのまま /usr/local/bin/befold の symlink 先にし、macOS App Translocation のガードがない。
quarantine 属性付きで Downloads から起動された(translocated な)アプリから CLI をインストールすると、symlink はランダム化された /private/var/.../AppTranslocation/ マウントを指し、次回起動や再起動で消滅する。インストールは成功と報告されるのに、その後 `befold` は "no such file or directory" で失敗する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 translocated なパス配下からのインストールを検出し、適切に対処する(拒否+案内、または実体パスの解決)
- [x] #2 translocation 検出ロジックのテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLIInstaller に純粋関数 isTranslocated(bundlePath:) を追加する(パス要素の完全一致で AppTranslocation マウントを判定)。
2. CLIInstallError に translocatedBundle を追加し、install の先頭で拒否して一切書き込まない。
3. AppDelegate.installCLI で失敗理由を分岐し、translocation 専用の案内を出す。
4. 起動時の staleSymlink 案内も translocated 時は抑止する(案内しても再インストールが断られるだけのため)。
5. 検出ロジックと install の拒否のテストを先に書いて赤を確認してから実装する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: AC#1 が許す 2 案のうち『拒否+案内』を採用(ユーザー判断)。実体パス解決(SecTranslocateCreateOriginalPathForURL)は symlink 先が ~/Downloads になり、アプリを後で移動・削除すれば同じく壊れるため、問題を先送りするだけと判断した。

実装:
- CLIInstaller.isTranslocated(bundlePath:) を追加。URL(fileURLWithPath:).pathComponents.contains("AppTranslocation") で判定する。部分文字列一致にしないのは AppTranslocationNotes/ のような通常のディレクトリ名を誤検出しないため(テストで固定)。
- SecTranslocateIsTranslocatedURL を使わなかった理由: 実在する URL を要求するためテストから任意のパスを与えて検証できず(AC#2 が満たせない)、得られる情報もマウントパスの形と同じであるため。この判断はコード側のドキュメントコメントにも残した。
- CLIInstallError に translocatedBundle を追加。install は先頭で拒否し、symlink を一切書き込まない。
- AppDelegate.installCLI を .success / .failure(.translocatedBundle) / .failure(.writeFailed) の 3 分岐にし、translocation 時は専用案内(cli.install.translocated, en/ja)を出す。書き込み権限の問題ではないため、再試行を促す汎用文言では解決に導けない。
- notifyIfCLIShimIsStale も translocated 時は抑止した。translocated では bundlePath が一時マウントを指すため、正しく設置済みの symlink でも staleSymlink に見え、案内に従って再インストールしても translocatedBundle で断られるだけの堂々巡りになる(調査中に判明した二次的な不整合)。

検証:
- 実装前に検出・拒否のテストを書き、API 未存在で赤になることを確認(TDD)。
- CLIInstallerTranslocationTests(新規, unit): translocated パスの検出、通常パス 5 種(/Applications・~/Applications・~/Downloads・/Volumes・AppTranslocationNotes)を誤検出しないこと、install が書き込まずに専用エラーを返すこと(installPath にファイルが作られていないことも確認)。
- swift test: 615 tests / 86 suites pass。swiftformat --lint: 0/184 files require formatting。既存の LocalizationTests『全キーに en / ja 両方の訳がある』が新キーもカバーしている。

実機での translocation 再現(quarantine 付きで Downloads から起動)は行っていない。判定はパス文字列のみに依存する純粋関数で、実際の translocated パス形状をテストで固定しているため、実機確認はリリース前手動チェックに委ねる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
App Translocation 下からの CLI インストールを検出して拒否し、アプリを移動してもらう案内を出すようにした。従来は一時マウントを指す symlink を作って『成功』と報告し、次回起動後に befold コマンドが no such file or directory で失敗していた。判定は CLIInstaller.isTranslocated(bundlePath:) というパス要素の完全一致による純粋関数で、install の先頭で拒否するため symlink は一切作られない。起動時の staleSymlink 案内も translocated 時は抑止した(案内に従っても再インストールが断られる堂々巡りになるため)。検証は TDD の赤を確認したうえで新規 unit テスト(検出・通常パスの非誤検出 5 種・install の非書き込み)を追加し、swift test 615 tests / 86 suites pass。
<!-- SECTION:FINAL_SUMMARY:END -->
