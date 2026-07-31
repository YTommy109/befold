---
id: TASK-237
title: バージョン文字列取得を共通化し About 画面の表示不備を修正する
status: To Do
assignee: []
created_date: '2026-07-31 09:16'
labels:
  - refactor
dependencies: []
priority: low
type: task
ordinal: 440000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Info.plist からのバージョン読み取りが 3 実装ある: AboutView.swift:43-48（取れないと空文字表示になる不整合あり）/ BefoldKit/AppLinks.swift:34-40 / BefoldCLI/AppVersion.swift:34-51（$( プレースホルダ判定つき）。CFBundleShortVersionString 等のキーリテラルと hasPrefix("$(") 判定が散在している。BefoldKit/VersionFormatting に infoDictionary → 整形済み文字列（取れなければ nil）の共通実装を置き、フォールバックの決定は呼び出し側に残す。副産物として About パネルが空文字になる現在の不整合を是正する。併せて AboutView.swift:9 の body 内 NSImage(contentsOfFile:) 評価（body ごとにディスク読み直し）を init/State への退避で解消する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 バージョン文字列の取得・整形が 1 実装に集約され、3 箇所の表示が従来の意図どおり（About は空文字にならない）
- [ ] #2 AboutView の画像読み込みが body 評価ごとに走らない
<!-- AC:END -->
