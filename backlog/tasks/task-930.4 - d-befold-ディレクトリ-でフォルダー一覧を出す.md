---
id: TASK-930.4
title: (d) befold <ディレクトリ> でフォルダー一覧を出す
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T00:12:58Z'
updated_date: '2026-11-25T10:46:49Z'
labels: []
dependencies:
  - TASK-930.1
documentation:
  - docs/adr/0013-presentation-intent-before-sidebar-sync.md
parent_task_id: TASK-930
priority: medium
type: feature
ordinal: 866000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0013 決定 5。いまは befold <ディレクトリ> がフォルダー内の最初のファイルを開く（SupportedFileResolver.resolveFileToOpen 経由で DocumentOpener.openViewer へ渡す）。ディレクトリを指定した意図どおり、その一覧を出すようユーザーが決めた（2026-11-25）。Finder・Dock・最近使った項目からディレクトリを開く経路も同じ解決を通っているため、扱いを揃えるか個別に決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold <ディレクトリ> で開いた窓は、本文にそのディレクトリの一覧を出し、ファイルを開かない
- [x] #2 ファイルの無いディレクトリでも、cli.folder.noFile のアラートではなく一覧（空の状態）を出す
- [x] #3 Finder・Dock・最近使った項目・リポジトリを開く経路でディレクトリを渡したときの扱いを決め、決めた内容を Notes に残す
- [x] #4 befold --help など CLI の説明文と docs の記述を新しい挙動に合わせる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
方針 A: ディレクトリは文書を持たない窓(BlankTabWindowController)で開き、本文に FolderListingView を出す。ViewerWindowController にディレクトリ URL を渡す案 B は、ViewerStore/ローダ/監視/台帳/セッションにディレクトリ分岐が 0 件(rg)で影響が広いため採らない。
1. BlankTabWindowController に PresentationIntent を持たせる(.file = 空タブの画面、.folder(D) = D の一覧)。本文は intent を見て BlankTabView と FolderListingView を切り替える。presentedTarget は .folder のときだけ返す。タイトル/representedURL はフォルダー名に合わせる。
2. 空タブのサイドバーで、フォルダー行を選ぶ・フォルダーに入る(navigateToFolder の presentingFolder)と intent を書く。文書タブと同じ規則(ADR 0013 決定 5)。⌘T の空タブも、フォルダーに入れば一覧を出すようになる。
3. ViewerWindowManager に openFolder(directory, options) を足す。ディレクトリから BlankTabSidebarContext を作り(makeBlankTabSidebar を起点窓/ディレクトリの両方から作れる形にする)、--sort/--hidden-files/--sidebar を窓単位で適用し、intent を .folder(directory) で始める。
4. DocumentOpener の private openViewer: ディレクトリなら resolveFileToOpen を通さず openFolder へ。presentNoFileAlert と cli.folder.noFile を撤去。openInTabs(allowsDirectories: false)は据え置き。
5. AC#3 の判断を Notes に残す: CLI/Finder/Dock/Open Recent/開くパネル(単一)は DocumentOpener を通るので一律に一覧。リポジトリを開く(SessionRestorer.openRootFallback)・Quick Open・--check は据え置き。フォルダー窓はセッション復元・再利用・最近使った項目の対象にしない。
6. テスト: 実ディレクトリでファイルあり/空の両方、空タブでのフォルダー移動、修正を戻して落ちることの確認。
7. 文書: CLI の discussion、DocumentOpener/PresentationIntent の doc、docs/dev/viewer-ui.md。

/review-design の結果(2026-11-25): 1 判定=入口の isDirectory(事実)と intent で決め、行の有無は見ない。2 不変条件=空タブの『WebKit と文書監視を作らない』『セッション・履歴に含めない』を保つ(フォルダー窓は再起動で戻らない、を仕様として Notes へ)。PresentationIntent をサイドバー型へ渡さない規則も保つ(書くのは BlankTabWindowController の delegate 実装)。3 兄弟=BlankTabWindowController を型判定する 4 箇所(DocumentOpener.enqueueBlankTabOpen / ActiveViewerProvider / ViewerWindowOpenPolicy x2)はフォルダー窓にもそのまま効く: 手前のフォルダー窓から Open Recent・Quick Open でファイルを開くと置き換わる(一覧でファイルを選ぶのと同じ)。4 表示=空のディレクトリ・列挙失敗は FolderListingView の既存空状態(SidebarEmptyState 共有)。5 順序=CLI の並び順・不可視の上書きは navigator の初回 refresh より前に適用し、intent は窓生成時に書く。6 高頻度経路なし。7 テストは ViewerWindowController が増えないことと空タブの intent を測る。8 一覧の非同期は FolderListingView 既存の世代管理。9 intent は窓ごと(init で生成、注入しない)。CLI 上書きは applyCLIOverride(既定値を書かない)。10 型グループ: BlankTabWindowController 192 行→約 240 行(stored property +1 は窓の提示で既存の関心)、ViewerWindowManager 385→約 400、DocumentOpener は減る。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: DocumentOpener の private openViewer はディレクトリを resolveFileToOpen へ通さず ViewerWindowManager.openFolder へ渡す。openFolder はディレクトリから作ったサイドバーを持つ BlankTabWindowController を新しい窓で開き、PresentationIntent を .folder(ディレクトリ) で始める。本文は BlankTabContentView が intent を見て FolderListingView / 空タブの画面を切り替える。presentNoFileAlert と cli.folder.noFile は到達不能になったので撤去した。
AC#3 の決定:
- CLI(openPaths)・Finder/Dock(application(_:open:))・Open Recent・ブックマーク・パネルの単一選択・参照クリック: すべて DocumentOpener の private openViewer を通るので一律に一覧(ADR 0013 決定 5)。
- パネルの複数選択・ドロップ(openInTabs): allowsDirectories: false のまま。ディレクトリは開かない(従来どおり)。
- リポジトリを開く(SessionRestorer.openRootFallback)と Quick Open(QuickOpenModel.commitSelection): 据え置き。中のファイルを開く。前者はタブ構成の復元が主で代替の経路、後者は『ファイルを開く』操作のため。揃えたくなれば別タスク。
- befold --check <ディレクトリ>: 据え置き(中のファイルを開けるかを答える。開く操作ではないため)。
- フォルダーの窓は空タブと同じく、文書の台帳・セッション復元・Open Recent の記録に載らない。同じディレクトリを再度開くと再利用せずもう 1 枚開く。手前がこの窓のときに Open Recent/Quick Open でファイルを開くと置き換わる(空タブの規則)。
- 付随する挙動の変化: ⌘T の空タブでもフォルダー行を選ぶ・フォルダーに入ると本文に一覧を出す(文書タブと同じ規則。従来は空タブの画面のまま)。
テスト: DocumentOpenerFolderTests 5 本(ファイルあり/空ディレクトリ、フォルダー窓での移動、空タブでフォルダー行選択、CLI 上書きが既定値を書かない、サイドバー開閉 nil/--no-sidebar)。旧挙動(先頭ファイルを開く・intent を書かない・CLI 上書き/開閉を当てない)の変異を入れ、全ケースが落ちることを確認。開閉の検査は最初の形だと保存値に引きずられて変異でも通ったため、最後の開閉操作を逆にして測る形へ直した。swift test --skip PDF で 2003 件が通過。変更ファイルの swiftlint 0 件。
openFolder の前面化は NSApplication.shared.activate() にした(NSApp は単体実行のテストで未初期化のため nil で落ちた)。
文書: CLI の discussion に 1 文、docs/dev/viewer-ui.md に『ディレクトリを開く』節、native-app-design.md の DocumentOpener / BlankTab 行。
実機(GUI)での確認はまだ。
CHANGELOG 用: befold <フォルダー> や Finder からフォルダーを開くと、中のファイルを開かずにフォルダーの一覧を表示するようになりました。ファイルの無いフォルダーも一覧(空)を表示します。

追加の確認(advisor の指摘):
- コールド起動: AppDelegate.applicationDidFinishLaunching は restoreLastSession を窓の数に関係なく常に呼ぶ(従来どおり)。フォルダーの窓が台帳に無いことで起動処理が変わる経路は無い。
- サイドバーのフォルダー行の『新しいタブ/ウィンドウで開く』は SidebarContextMenu.openElsewhereButton が DirectoryLister.firstSupportedFile で先頭ファイルへ解決してから渡すので、この変更は届かない(従来どおり先頭ファイルを開く)。揃えるなら別タスク。
- 文書内リンクがディレクトリを指す場合(AppDelegate.openViewer(for:disposition:placement:relativeTo:) → DocumentOpener): disposition を見ずに新しい窓で一覧を開く。従来は指定どおりの位置で先頭ファイルを開いていた。文書の窓自身に .folder を出す形が本来なので、930.5 以降か別タスクで扱う候補。
- CLI の --sort / --hidden-files は窓限りの上書きなので、一覧でファイルを選んで文書タブへ置き換わると引き継がれない(置き換えは CLIOpenOptions() で開く)。⌘T の空タブにも元からある性質。行番号・表示モード・--new-tab 等(openDisposition)はフォルダーの窓では使わない。
- 空タブ由来の制約: View メニューのサイドバー項目は使えない(ヘッダーのメニューは使える)、戻る/進むは効かない(historyStateDidChange が空)、初期フレームは既定値、最近使ったリポジトリへ記録しない。
- 実機確認: インストール版 befold(/Applications)が起動中で GUI 自動化を奪うため実施していない。

訂正(実機確認で判明): 開くパネルは canChooseDirectories を設定しておらず(既定 false)、ディレクトリを選べない。上の「パネルの単一選択も一律に一覧」は誤りで、パネルはディレクトリの入口ではない。docs/dev/viewer-ui.md も訂正した。パネルでフォルダーを選べるようにするかは別判断。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
befold <ディレクトリ>・Finder・Dock・Open Recent などからディレクトリを開くと、中のファイルを開かず、文書を持たない窓(空タブ)の本文にそのディレクトリの一覧を出すようにした(ADR 0013 決定 5)。空のディレクトリも一覧の空状態になり、cli.folder.noFile のアラートは撤去。空タブはフォルダー行の選択・フォルダーへの移動で一覧を出すようになった。テストは変異で全ケースが落ちることを確認し、全体 2003 件が通過。実機確認は未実施。
<!-- SECTION:FINAL_SUMMARY:END -->
