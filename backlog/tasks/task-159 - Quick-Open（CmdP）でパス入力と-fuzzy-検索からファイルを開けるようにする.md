---
id: TASK-159
title: Quick Open（Cmd+P）でパス入力と fuzzy 検索からファイルを開けるようにする
status: To Do
assignee: []
created_date: '2026-07-26 06:03'
labels: []
dependencies: []
ordinal: 234000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
VSCode の Cmd+P に相当する Quick Open を導入する。Spotlight 風のフローティングパネルにパスまたはファイル名の断片を打ち込み、現在のウィンドウを目的のファイルへ切り替えられるようにする。設計は docs/superpowers/specs/2026-07-26-quick-open-design.md を参照。判断ロジックは BefoldKit の純粋ロジックに置き、AppKit/SwiftUI 層は表示とキー配線のみを担う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cmd+P で Spotlight 風パネルが開き、Esc とフォーカス喪失で閉じる
- [ ] #2 入力が / ~ . で始まる場合はパスモードとして解決し、親ディレクトリの中身を末尾断片で前方一致絞り込みして表示する
- [ ] #3 Tab で候補の共通接頭辞まで補完し、候補が1件のディレクトリなら次の階層へ進む
- [ ] #4 上記以外の入力では候補を fuzzy 検索し、スコア降順・同点はパス昇順で決定論的に最大50件表示する
- [ ] #5 fuzzy 検索の候補は Git 管理下なら GitCommandFileIndex、非 Git なら DirectoryFileScanner（深さ上限8・件数上限10000・.git/node_modules/.build 除外）から集める
- [ ] #6 候補を拡張子で区別せず全ファイルを対象とし、隠しファイルの扱いは HiddenFilesPreference.showHiddenFiles に従う
- [ ] #7 空入力時に最近開いたファイルとブックマークを合計20件まで表示し、fuzzy 検索時もそれらを normalizedPathKey で重複除去して候補に混ぜる
- [ ] #8 Enter で現在のウィンドウが switchFile(to:) で切り替わり、ウィンドウが無い場合のみ新規ウィンドウを開く
- [ ] #9 決定対象がディレクトリの場合は SupportedFileResolver 経由で中の1ファイルを開く
- [ ] #10 候補の上限に達して打ち切った場合はリスト末尾にその旨を表示する
- [ ] #11 候補ゼロは一致なし表示のみでアラートを出さない
- [ ] #12 Print のショートカットが Shift+Cmd+P に移り、Cmd+P が Quick Open に割り当てられる
- [ ] #13 QuickOpenQuery / FuzzyMatcher / DirectoryFileScanner / QuickOpenCandidates / QuickOpenModel に自動テストがあり swift test が通る
<!-- AC:END -->
