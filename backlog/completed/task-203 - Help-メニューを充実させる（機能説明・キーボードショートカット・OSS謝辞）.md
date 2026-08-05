---
id: TASK-203
title: Help メニューを充実させる（機能説明・キーボードショートカット・OSS謝辞）
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 02:02'
updated_date: '2026-07-31 05:17'
labels: []
dependencies: []
ordinal: 286000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在の Help メニューは最低限の項目しかなく、ユーザーがアプリの機能やショートカットを自分で把握する手段がない。機能説明、キーボードショートカット一覧、利用しているオープンソースソフトウェアへの謝辞（ライセンス表記含む）を Help メニュー配下に追加し、ユーザーが迷わずアプリを使いこなせるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Help メニューから主要機能の説明を閲覧できる
- [x] #2 Help メニューからキーボードショートカット一覧を閲覧できる
- [x] #3 Help メニューから利用しているオープンソースソフトウェアの一覧とライセンス表記を閲覧できる
- [x] #4 各項目はウィンドウとして開くか、既存の About/Help 導線と一貫した UI で提供される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. HelpOverviewWindowController / KeyboardShortcutsWindowController / OSSLicensesWindowController の3つを CodeFontSettingsWindowController と同じ単一インスタンス toggle() パターンで新設する(SwiftUI View を NSHostingController でラップ)。
2. HelpOverviewView: 主要機能(ファイル監視プレビュー、タブ、ブックマーク、隠しファイル表示切替、Quick Open 等)の説明を静的コンテンツとして箇条書き表示する。
3. KeyboardShortcutsView: MainMenuBuilder.swift に実装済みのショートカット(App/File/Edit/View/Window/Help 各メニュー)をメニューごとにグループ化した一覧としてハードコードし、Table/List で表示する(メニュー定義から動的抽出はスコープ外、既存の実装済みショートカットの静的一覧化に留める)。
4. OSSLicensesView: BefoldKit/Resources/THIRD_PARTY_LICENSES.md をバンドルリソースとして読み込み、AttributedString(markdown:) または ScrollView+Text でスクロール表示する。
5. MainMenuBuilder.makeHelpMenuItem に3項目(機能説明/キーボードショートカット/OSS謝辞)を既存の befold Help の下に追加し、AppDelegate に対応する @objc アクション(showHelpOverview/showKeyboardShortcuts/showOSSLicenses)を showSettings と同様のキャッシュ+toggle 方式で実装する。
6. befold/Resources/Localizable.xcstrings に新規メニュー項目・ウィンドウタイトルのローカライズキーを追加する。
7. GUI手動確認(ビルド後に3つのウィンドウをそれぞれ開き、内容とライト/ダーク表示を確認)。自動テストは非GUI部分(THIRD_PARTY_LICENSES.md 読み込みロジックなど切り出せるものがあれば)に限定する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CodeFontSettingsWindowController と同じ単一インスタンス toggle パターンで FeatureOverviewWindowController / KeyboardShortcutsWindowController / OSSLicensesWindowController の3つを新設し、Help メニュー(MainMenuBuilder)に「Feature Overview」「Keyboard Shortcuts」「Open Source Acknowledgements」を追加。機能説明にはユーザー要望で AI コーディングエージェント(Claude Code 等)向けに ~/.claude/skills/befold-review/SKILL.md のような skill を用意する Tips を追記。ショートカット一覧は MainMenuBuilder に実装済みの内容をメニューごとにグループ化してハードコード表示(グループタイトルはローカライズキーを String(localized:) で解決)。OSS謝辞は BefoldKit 同梱の THIRD_PARTY_LICENSES.md をそのまま ScrollView+Text で表示。Localizable.xcstrings にメニュー項目・ウィンドウタイトル・機能説明本文のキーを追加。検証: swift build / swift test(847件 全 pass)。GUI手動確認: xcodebuild でビルドし、Help メニューから3ウィンドウをそれぞれ開きスクリーンショットで内容とグループ見出しの正しいローカライズを確認(初回実装でグループ見出しがローカライズキーのまま表示されるバグを発見し修正)。

ユーザーレビューで3点指摘: (1) Feature Overview 本文がテキスト選択/コピー不可 → 全 Text に .textSelection(.enabled) を付与して解消。(2) AI連携の説明が ~/.claude/skills/befold-review/SKILL.md というパスの言及のみで中身が分からない → 新規 featureOverview.aiIntegration 項目として独立させ、SKILL.md に書く具体的な frontmatter+コマンド例をコードブロックで提示するよう変更。(3) Help が英語表示になる件はバグではなく、実行環境の言語設定(defaults read -g AppleLanguages が en-JP 優先)による正常な多言語切替と回答。再検証: swift build / swift test(847件 pass)、GUI手動確認でコード例の表示を確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Help メニューに機能説明・キーボードショートカット一覧・OSS謝辞の3ウィンドウを追加。Settings/About と同じ単一インスタンスウィンドウパターンで実装し、機能説明には AI コーディングエージェント連携の Tips を含めた。swift test 847件全て pass、GUI手動確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
