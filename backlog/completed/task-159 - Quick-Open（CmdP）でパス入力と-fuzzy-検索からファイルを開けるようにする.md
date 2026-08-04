---
id: TASK-159
title: Quick Open（Cmd+P）でパス入力と fuzzy 検索からファイルを開けるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-07-26 06:03'
updated_date: '2026-07-27 04:09'
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
- [x] #1 Cmd+P で Spotlight 風パネルが開き、Esc とフォーカス喪失で閉じる
- [x] #2 入力が / ~ . で始まる場合はパスモードとして解決し、親ディレクトリの中身を末尾断片で前方一致絞り込みして表示する
- [x] #3 Tab で候補の共通接頭辞まで補完し、候補が1件のディレクトリなら次の階層へ進む
- [x] #4 上記以外の入力では候補を fuzzy 検索し、スコア降順・同点はパス昇順で決定論的に最大50件表示する
- [x] #5 fuzzy 検索の候補は Git 管理下なら GitCommandFileIndex、非 Git なら DirectoryFileScanner（深さ上限8・件数上限10000・.git/node_modules/.build 除外）から集める
- [x] #6 候補を拡張子で区別せず全ファイルを対象とし、隠しファイルの扱いは HiddenFilesPreference.showHiddenFiles に従う
- [x] #7 空入力時に最近開いたファイルとブックマークを合計20件まで表示し、fuzzy 検索時もそれらを normalizedPathKey で重複除去して候補に混ぜる
- [x] #8 Enter で現在のウィンドウが switchFile(to:) で切り替わり、ウィンドウが無い場合のみ新規ウィンドウを開く
- [x] #9 決定対象がディレクトリの場合は SupportedFileResolver 経由で中の1ファイルを開く
- [x] #10 候補の上限に達して打ち切った場合はリスト末尾にその旨を表示する
- [x] #11 候補ゼロは一致なし表示のみでアラートを出さない
- [x] #12 Print のショートカットが Shift+Cmd+P に移り、Cmd+P が Quick Open に割り当てられる
- [x] #13 QuickOpenQuery / FuzzyMatcher / DirectoryFileScanner / QuickOpenCandidates / QuickOpenModel に自動テストがあり swift test が通る
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装は BefoldKit の純粋ロジック（QuickOpenQuery / FuzzyMatcher / DirectoryFileScanner / QuickOpenCandidates）と、App 層の表示・配線（QuickOpenModel / QuickOpenPanelController / QuickOpenView / AppQuickOpenEnvironment）に分けた。

設計上の判断:
- SuffixPathIndex.allCandidates は候補 URL を二重に保持せず、既存の照合用の格納をそのまま畳んで返す。辞書の反復順は安定しないため正規化パス昇順に並べ直した。照合規則には触れていないので既存のリンク解決の挙動は不変。
- DirectoryFileScanner は深さ上限と件数上限を別物として扱う。深さ上限は「その枝を潜らない」だけで走査全体は続け、件数上限のみ全体を打ち切る。当初これを混ぜており、深い枝が1本あるだけで以降のファイルが丸ごと欠ける不具合をテストで検出した。
- 決定時の切り替え先は、パネルを開いた時点の ViewerWindowController を捕まえておく。パネル自身がキーウィンドウを奪うため、決定時に NSApp.keyWindow を引き直すと常にパネルが返り、既存ウィンドウでの切り替えにならない。

実機確認で見つけて直した不具合:
- パネルが生成時の高さのまま固定され、候補リストが一切見えていなかった（入力欄だけのパネル）。NSHostingController.sizingOptions = [.preferredContentSize] で解消。自動テストでは検出できない層だった。

検証:
- swift test: 783 tests / 109 suites 全通過（integration 含む）
- 実機の UI スクリプト確認（xcodebuild Debug ビルドを起動し System Events で操作）:
  - File メニューの実測値: クイックオープン… key=P mods=0（⌘P）、プリント… key=P mods=1（⇧⌘P）
  - ⌘P でパネルが開き（ウィンドウ数 1→2）、Esc とフォーカス喪失（他アプリ activate）でいずれも 2→1 に閉じる
  - 入力 'changelog' で候補が .claude/skills/changelog.md と CHANGELOG.md の2件に絞り込まれる
  - 入力 '/etc/' でパスモードとして /etc の中身 84 件を列挙する
  - '/usr/sh' + Tab で '/usr/share/' へ補完（候補1件のディレクトリなので次の階層へ進む）
  - Enter で同一ウィンドウが README.md → changelog.md に切り替わる（ウィンドウ数は 1 のまま）

補足（本タスク範囲外の観察）: 実機では GitFileIndexing.trackedFileIndex が nil を返し、候補は DirectoryFileScanner のフォールバック（800件）から集まっていた。git の解決が効かない環境要因（起動時の PATH など）と見られ、Quick Open 側の実装とは独立。候補収集自体はフォールバックで正しく機能している。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
VSCode の Cmd+P に相当する Quick Open を追加した。判断ロジックは BefoldKit の純粋ロジック（入力の分類・fuzzy 照合・非 Git 時のディレクトリ走査・候補のマージ）に置き、AppKit/SwiftUI 層は NSPanel の生存とキー配線だけを持つ。Print は Shift+Cmd+P へ移した。

検証は swift test（783 tests / 109 suites 全通過）に加え、実機ビルドを起動して System Events で UI を操作し、パネルの開閉（Esc・フォーカス喪失）、fuzzy 絞り込み、パスモードの列挙、Tab 補完、Enter による同一ウィンドウでの切り替え、メニューのキー割当（⌘P / ⇧⌘P）を実測で確認した。この実機確認で「パネルが生成時の高さのまま固定され候補リストが表示されない」不具合を発見し、NSHostingController の sizingOptions 指定で修正済み。
<!-- SECTION:FINAL_SUMMARY:END -->
