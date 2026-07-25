---
id: TASK-125
title: CLI インストールが App Translocation 下で消滅する symlink を作る
status: To Do
assignee: []
created_date: '2026-07-24 22:22'
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
- [ ] #1 translocated なパス配下からのインストールを検出し、適切に対処する(拒否+案内、または実体パスの解決)
- [ ] #2 translocation 検出ロジックのテストがある
<!-- AC:END -->
