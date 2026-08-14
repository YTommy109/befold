---
id: TASK-479
title: Help メニューに GitHub Issues への導線を追加する
status: To Do
assignee: []
created_date: '2026-08-14 00:43'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 697000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Help メニューから不具合報告・要望を出せる導線がない。現状の Help 配下は機能説明・キーボードショートカット・AI 連携・Visit Website・OSS 謝辞のみで、利用者が問題に遭遇しても報告先が分からない。Help メニューに "GitHub Issues..." を追加し、ブラウザで https://github.com/YTommy109/befold/issues を開く。

実装の当たり: リンク定義は BefoldKit/AppLinks.swift、メニュー項目は MainMenuBuilder.makeHelpMenuItem と MainMenuHelpActions、アクションは AppDelegate の openHelp と同型（NSWorkspace.shared.open）、表示文字列は Localizable.xcstrings に menu.help.* のキーを追加する。既存の visitWebsite が ?ref=help で流入元を数えているため、issues 側も ref パラメータを付けるかどうかを判断すること（GitHub 側なので集計はできない点に注意）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Help メニューに GitHub Issues を開く項目が追加されている
- [ ] #2 選択すると既定ブラウザで befold リポジトリの Issues ページが開く
- [ ] #3 表示文字列が Localizable.xcstrings に追加され、日英ともに翻訳されている（既存の並び順を保ったまま近縁キーの直後に挿入する）
- [ ] #4 Help > キーボードショートカット一覧の表示が壊れていない（ショートカットは割り当てない）
<!-- AC:END -->
