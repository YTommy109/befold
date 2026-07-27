---
id: TASK-159
title: Quick Open（Cmd+P）でパス入力と fuzzy 検索からファイルを開けるようにする
status: In Progress
assignee:
  - '@claude'
created_date: '2026-07-26 06:03'
updated_date: '2026-07-27 01:16'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. QuickOpenQuery（BefoldKit）: 入力を .empty/.path/.fuzzy に分類する純粋ロジック＋テスト
2. FuzzyMatcher（BefoldKit）: 部分列 DP による順位付き照合。連続一致・単語境界・ファイル名一致を加点、同点は text 昇順＋テスト
3. SuffixPathIndex.allCandidates（BefoldKit）: 読み取り専用で候補 URL を読み出す口を追加。既存の格納をそのまま畳んで返し、二重保持しない（照合規則は不変）
4. DirectoryFileScanner（BefoldKit）: 非 Git 時の再帰走査。深さ8・件数10000・.git/node_modules/.build 除外・隠しファイル設定・打ち切りフラグ＋テスト
5. QuickOpenCandidates（BefoldKit）: 索引/走査/履歴/ブックマークをマージ。normalizedPathKey で重複除去、履歴加点、上限と打ち切り＋テスト
6. QuickOpenModel（App, @MainActor @Observable）: 入力→候補配列、決定を注入クロージャへ。パスモードは親ディレクトリ列挙＋前方一致、Tab は共通接頭辞補完＋テスト
7. QuickOpenPanelController + QuickOpenView（App）: NSPanel と SwiftUI。判断ロジックを持たない。自動テスト対象外
8. MainMenuBuilder: Quick Open を Cmd+P、Print を Shift+Cmd+P へ。Localizable.xcstrings に文言追加＋テスト更新
9. AppDelegate 配線: lazy + クロージャ注入で QuickOpen コーディネータを保持。決定時は NSApp.keyWindow の ViewerWindowController.switchFile(to:)、無ければ openViewer(for:)
10. 手動チェック（パネル表示/Esc/フォーカス喪失/上下キー/Shift+Cmd+P 印刷）
<!-- SECTION:PLAN:END -->
