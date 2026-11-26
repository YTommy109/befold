---
id: TASK-930.8
title: フォルダーを開く残りの入口を ADR 0013 決定 5 に揃える
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T13:14:02Z'
updated_date: '2026-11-26T02:17:03Z'
labels: []
dependencies: []
parent_task_id: TASK-930
priority: low
type: bug
ordinal: 870000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の指摘(2026-11-25、いずれも nit)。原因は同じで、TASK-930.4 でディレクトリを一覧の窓で開くようにしたとき、文書の開き方にある規則が一部移っていない。(1) DocumentOpener.openViewer のディレクトリ分岐は disposition・sourceWindow・placement・prefersExistingWindow を見ず、常に新しい窓を作る。befold <dir> を 2 回実行すると同じ一覧の窓が 2 つでき、手前の空タブから Open Recent でフォルダーを選んでも空タブは置き換わらない(openViewer(for:) の doc コメントと食い違う)。(2) ViewerDisplayOptionsApplier.folderSeed / apply(_:toFolderWindow:) は並び順・不可視ファイル・開閉だけを当て、--compare-to を一覧の窓の comparisonTarget に当てない。--line / --source などは何も言わずに捨てる。(3) サイドバーのフォルダー行のコンテキストメニュー「新しいタブ/ウィンドウで開く」は、いまもフォルダー内の最初のファイル(DirectoryLister.firstSupportedFile)を開く(SidebarContextMenu.openElsewhereButton)。コード上の該当は確認済み、実機での再現は未実施。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 同じディレクトリを手前のタブ扱い(既定)でもう一度開くと、既存の一覧の窓を前面に出す(新しい窓を作らない)。--new-window なら新しい窓
- [x] #2 --compare-to をディレクトリの窓の比較基準に当てる。文書にしか意味の無いオプションをディレクトリだけに付けたら標準エラーへ警告し、窓は開く
- [x] #3 サイドバーのフォルダー行で「新しいタブ/ウィンドウで開く」(メニュー・⌘クリック・⌘Return)を選ぶと、新しいタブ/窓にそのフォルダーの一覧を出す
- [x] #4 各経路をテストで確かめ、修正を戻すと落ちることを確かめる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計は Plan エージェントの案を採用(前提はコードで確認: --compare の --diff 必須検証 = BefoldCLICommand.validate、InMemoryFileReader.fileExists はディレクトリでも真)。
1. 規則の置き場 = BlankTabCoordinator.openFolder(_:options:disposition:relativeTo:)(必須引数)。候補はフォルダーの窓のうち意図 .folder(dir) が一致するもの。再利用の表は ViewerWindowOpenPolicy.reusableController の switch を NSWindowController 汎用の reusableWindow に切り出して共有する(.currentTab = 前面化、.newTab = 同じタブグループなら選ぶ、.newWindow/.slide = 常に新規)。新しいタブは起点のタブ(背面)、種は ViewerDisplayOptionsApplier.folderSeed。再利用した窓にもオプションを当てる
2. ViewerWindowManager: openFolder と makeBlankTabSidebar(from:) を撤去し coordinator へ移す。振り分け openElsewhere(_:disposition:placement:relativeTo:) を足し、fileReader.isDirectory ならフォルダーの窓、でなければ openViewer。文書の窓と空タブの窓の openElsewhere クロージャをこれに通す
3. ViewerDisplayOptionsApplier.apply(_:toFolderWindow: BlankTabWindowController): 並び順・不可視ファイル(取り直し)・開閉・比較基準(fileListDidRequestComparisonTarget)
4. DocumentOpener のディレクトリ分岐は blankTabs.openFolder に disposition と起点を渡す
5. サイドバー: FileListView の ⌘クリックと SidebarKeyAction の ⌘Return をフォルダー行にも効かせ、fileListDidRequestOpenElsewhere へ渡す。SidebarContextMenu はフォルダー行でスライドを出さず(ユーザー決定 B)、新しいタブ/窓はフォルダーの URL を delegate へ渡す。containsSupportedFile / firstSupportedFile(DirectoryLister・DirectoryEnumeration)と関連テストを撤去
6. CLI: CLIOpenOptions.hasDocumentOnlyOptions、CLIAppLauncher で全パスがディレクトリなら stderr へ警告(終了コード 0)。validate はパスがすべてディレクトリなら --compare 単独を許す。help と docs/dev/cli-launch.md を直す
7. テスト: 再利用(currentTab 1 窓 / newWindow 2 窓)、--compare が git 取得に効く(記録する reader)、再利用した窓へのオプション、フォルダー行の newTab/newWindow(文書の窓・フォルダーの窓が起点)、⌘クリック/⌘Return、メニュー、CLI 警告の表、--compare の検証。いずれも修正を戻すと落ちることを確かめる
8. 文書: native-app-design.md(openFolder の置き場・再利用)、viewer-ui.md(開き分けの表)、product-code.md の firstSupportedFile
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
到達性の調査(2026-11-26): ディレクトリが届く入口は CLI(openPaths)と Finder/Dock(openSequentially)だけで、どちらも起点の窓は無い。開くパネルは canChooseDirectories が既定の false、openInTabs は allowsDirectories: false、Open Recent・ブックマークはファイルのみ。手前の空タブを起点にディレクトリが来る経路は無いので、AC#1 の「空タブを置き換える」は外す。
方針(ユーザー決定 2026-11-26): (a) フォルダー行の「新しいタブ/ウィンドウで開く」はフォルダーの一覧を開く。⌘クリック・⌘Return もフォルダー行で同じく効かせる。(b) 文書にしか意味の無い CLI オプションをディレクトリだけに付けたら、標準エラーへ警告して続ける(終了コード 0)。(c) --compare-to はディレクトリの窓にも当てる。

スライド(ユーザー決定 2026-11-26): フォルダー行のメニューでは「スライドモードで開く」を出さない(案 B)。--compare のフラグ名について: ユーザーへの質問では --compare-to と書いたが実際は --compare。ディレクトリだけに付けると現状はパースで落ちるため、検証を緩めることを決定 (c) の実現に必要な変更として扱う。

実装: 計画どおり。BlankTabCoordinator.openFolder(_:options:disposition:relativeTo:)(必須引数)が、意図 .folder(dir) の一致する窓を ViewerWindowOpenPolicy.reusableWindow(reusableController の switch を NSWindowController 汎用に切り出した)で再利用し、無ければ新規(.newTab は起点のタブとして背面)。ViewerWindowManager.openFolder / makeBlankTabSidebar(from:) を撤去し、振り分け openElsewhere(fileReader.isDirectory でフォルダーの窓 / 文書の窓)を足して文書の窓・空タブの窓の両方の openElsewhere をこれに通した。ViewerDisplayOptionsApplier.apply(_:toFolderWindow:) は並び順・不可視ファイル(取り直し)・開閉・比較基準を、新しい窓にも再利用した窓にも当てる(生成時の一覧取得は世代ガード、git 取得は基準の照合で捨てられる: SidebarListingCoordinator.performListing の guard generation と SidebarGitStatusCoordinator.apply をコードで確認)。サイドバーは ⌘クリック・⌘Return をフォルダー行にも効かせ(FileListView.open(_:with:) / SidebarKeyAction.commandReturn)、コンテキストメニューはフォルダー行でスライドを出さない(openElsewhereEntries(for:))。DirectoryLister.containsSupportedFile / firstSupportedFile、DirectoryEnumeration.firstSupportedFile、FileListEntry.containsSupportedFile と専用テスト(DirectoryListerSupportedFileTests ほか)を撤去した(一覧のたびにフォルダー行ごとに中を列挙していた分も消える)。resolveFileToOpen の自然順・対応形式優先は DirectoryListerTests が引き続き測る。CLI は CLIOpenOptions.hasDocumentOnlyOptions と CLIAppLauncher.opensOnlyFolders で警告し(stderr、終了コード 0)、validate はパスがすべてディレクトリなら --compare 単独を許す。
テスト: 再利用(DocumentOpener 経由で 2 回 → 1 窓、表 currentTab 1 / newWindow 2)、--compare が git 取得の基準になる(基準を記録する reader)、再利用した窓へのオプション、フォルダー行を別の場所で開く(文書の窓・フォルダーの窓 × newTab・newWindow、タブグループの共有で新規タブを測る)、⌘タップ・⌘Return、メニュー項目、CLI 警告の表(9 行)、--compare の検証。変異(再利用しない / --compare を当てない / ⌘ をファイル行だけに戻す / 振り分けをやめる / 警告しない / 検証を戻す)で、それぞれ対応するテストが落ちることを確認した。
検証: swift test --skip PDF 2015 件・--filter PDF 103 件・CLI 85 件通過。swiftlint は変更ファイルで新規 0 件(FileListEntry の id は HEAD からの既存)。型グループ --check 通過(ViewerWindowManager は 400 以内)。xcodegen generate 後、別の derivedDataPath で xcodebuild 成功。実機確認は未実施(メニュー表示・背面タブ・befold dir 2 回の前面化)。
文書: viewer-ui.md(ディレクトリを開く・開き分け)、native-app-design.md(DocumentOpener / BlankTabCoordinator)、cli-launch.md(--compare と警告)、rules/product-code.md(firstSupportedFile)。

追加の確認(advisor の指摘): (1) setSidebarCollapsed は利用者の開閉として記録しない(ViewerSplitViewController の doc「記録しない」)。新しい窓に当てても lastToggledCollapsed は変わらない。(2) 文書内リンクの ⌘クリックも新しい振り分けを通るが、参照の解決(TrackedPathResolver)は isExistingFile = 存在しかつディレクトリでない ものだけを .resolved にするので、ディレクトリへは届かない。リンクの挙動は変わらない。(3) 未確認: 「変更のあるファイルのみ」が ON のときに --compare 付きで開くと、比較基準を当てる前に発行した最初の一覧で絞り込みが一瞬空になるか。git 取得は基準の照合で捨てられるが、一覧と git 状態の待ち合わせ(TASK-293)の経路は追っていない。実機または ViewerWindowManager のテストで確かめられる。(4) viewer-ui.md の見出し「ファイル行の開き分け」をフォルダー行も扱うため「行の開き分け」にした(見出しへのリンクは無い)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ディレクトリを開く残りの入口を ADR 0013 決定 5 に揃えた。(1) 同じディレクトリを既定の開き方でもう一度開くと既存の一覧の窓を前面に出す(--new-window は常に新規)。規則は BlankTabCoordinator.openFolder に置き、再利用の表は文書の窓と共有する。(2) --compare をディレクトリの窓の比較基準に当て、ディレクトリだけなら --diff なしでも通す。文書向けの指定をディレクトリだけに付けたら CLI が警告して窓は開く。(3) サイドバーのフォルダー行の新しいタブ/ウィンドウ(メニュー・⌘クリック・⌘Return)はその一覧を開き、フォルダー行ではスライドを出さない。不要になった containsSupportedFile / firstSupportedFile を撤去した。検証: 新規・書き換えテスト(変異で全落ち)、全体テスト通過、xcodebuild 成功。実機確認は未実施。
<!-- SECTION:FINAL_SUMMARY:END -->
