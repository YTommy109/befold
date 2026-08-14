---
id: TASK-479
title: Help メニューに GitHub Issues への導線を追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-14 00:43'
updated_date: '2026-08-14 08:15'
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
- [x] #1 Help メニューに GitHub Issues を開く項目が追加されている
- [x] #2 選択すると既定ブラウザで befold リポジトリの Issues ページが開く
- [x] #3 表示文字列が Localizable.xcstrings に追加され、日英ともに翻訳されている（既存の並び順を保ったまま近縁キーの直後に挿入する）
- [x] #4 Help > キーボードショートカット一覧の表示が壊れていない（ショートカットは割り当てない）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. AppLinks に issues URL を追加（GitHub 側なので ref パラメータは付けない。理由を doc コメントに残す）
2. MainMenuHelpActions に githubIssues セレクタを追加し、MainMenuBuilder の Help メニューへ visitWebsite の直後に項目を追加（keyEquivalent なし）
3. AppDelegate.openGitHubIssues を openHelp と同型で追加、MainMenuCoordinator と MainMenuFixture を配線
4. Localizable.xcstrings に menu.help.githubIssues を visitWebsite の直後へ挿入（日英）
5. テスト: AppLinksTests に issues の検証、MainMenuBuilderTests に項目存在＋ショートカット非割当の検証
6. swift build / swift test / swiftformat / swiftlint 差分確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: AppLinks.issues を追加し、MainMenuHelpActions.githubIssues → AppDelegate.openGitHubIssues(NSWorkspace.shared.open)で配線。Help メニューでは Visit Website の直後に置いた。

ref パラメータの判断: 付けない。ref は配布サイト Worker が自前で集計するための印で、遷移先が GitHub だと内訳を読めない。読めない印を残すと「付いているから数えられている」と誤解される。AppLinks.issues の doc コメントに理由を残し、AppLinksTests でクエリが nil であることを固定した。

ショートカットは割り当てない。MenuShortcutCatalog.groups は keyEquivalent が空でない項目だけを抽出するため、割り当てなければ Help > キーボードショートカット一覧に載らない（MainMenuBuilderTests で keyEquivalent.isEmpty を固定）。

docs/dev/native-app-design.md は Help メニュー構成・AppLinks に言及がないため更新不要（grep で 0 件）。

検証: swift build 成功。swift test 1507 tests / 238 suites 全通過（MenuShortcutCatalogTests・MainMenuBuilderTests 含む）。swiftformat 実行後、変更 7 ファイルに対する swiftlint は 0 件。issues URL は curl で HTTP 200、open -g で既定ブラウザが受理（exit 0）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Help メニューに GitHub Issues 項目を追加し、既定ブラウザで https://github.com/YTommy109/befold/issues を開くようにした。ref パラメータは GitHub 側で集計できないため付けず、理由を doc コメントとテストで固定。ショートカットは割り当てないためキーボードショートカット一覧は不変。swift test 1507 件全通過、変更ファイルの swiftlint 0 件、URL は curl HTTP 200 / open -g exit 0 で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
