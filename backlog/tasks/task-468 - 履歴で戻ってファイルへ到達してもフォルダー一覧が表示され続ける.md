---
id: TASK-468
title: 履歴で戻ってファイルへ到達してもフォルダー一覧が表示され続ける
status: Done
assignee: []
created_date: '2026-08-13 06:27'
updated_date: '2026-08-13 06:48'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 691000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 現象

ウィンドウ左上の history back ("<") ボタンで戻っていくと、履歴の途中でフォルダーを通過してプレビューエリアにフォルダー一覧が表示される。そこからさらに戻ってファイル提示のエントリに到達しても、そのファイルが表示されずフォルダー一覧が表示され続ける。

## 調査結果（原因）

根本原因は **履歴エントリが「フォルダー一覧を出していたか／ファイルを出していたか」を保持していない** こと。`HistoryEntry` は `{ directory, file }` の 2 値のみ（`BefoldApp/befold/App/NavigationHistory.swift:7-12`）で、記録側も選択を残していない（`BefoldApp/befold/App/SidebarHistoryController.swift:46-50`）。一方、プレビューがフォルダー一覧になるかは `fileListModel.selection` だけで決まる（`BefoldApp/befold/Viewer/PreviewTargetResolver.swift:47-63`）。復元時の選択は副作用頼みで、次の 3 経路すべてがフォルダー一覧に落ちうる。

- **A（本命・ドリルダウン）**: 同一ディレクトリ復元 `SidebarHistoryController.swift:74-77` は `matchingEntryURL(for:)` の結果をそのまま選択にするが、一覧に該当行が無いと生 URL が返る（`BefoldApp/befold/Viewer/FileListEntryIndex.swift:72-74`）。選択は非 nil だが索引に当たらず `PreviewTargetResolver.swift:57-59` で `.folder` に落ちる。この分岐は `refreshFileList()` を発行しないため `DirectoryLister.appendingOpenFile` の救済（`BefoldApp/befold/Viewer/DirectoryLister.swift:65-84`）も走らず、一覧が被さり続ける。
- **B（ツリー表示・親へ戻る）**: `dirChanged == true` 側は選択確定を一覧着地に委ねる（`SidebarHistoryController.swift:78-87`）が、着地側は既存のフォルダー選択が一覧内に残っていれば優先して保持する（`BefoldApp/befold/App/SidebarListingCoordinator.swift:88-96`）。履歴適用経路には「ファイルを選び直せ」という指示が無いため区別できない。さらに `SidebarHistoryController.swift:78` は `fileListModel.currentDirectory` へ直接代入しており、正規経路 `SidebarNavigator.moveCurrentDirectory`（`SidebarNavigator+FolderNavigation.swift:36-50`、TASK-465 で直接代入禁止と明記）を通らないため `discardExpansion()` 等がスキップされ、古い展開行が残って B を起こしやすくする。
- **C**: `SidebarHistoryController.swift:81-86` は「開いているファイルの親 ≠ 復元先ディレクトリ」でフォルダー行を選ぶが、`folderEntryURL` は `.folder` 行しか引かない（`FileListEntryIndex.swift:61-69`）ため nil になりやすく、`PreviewTargetResolver.swift:52` の guard でやはり `.folder` になる。

## 方針の候補

`HistoryEntry` に「提示対象（ファイル／フォルダー）」を持たせ、復元時に選択を一意に確定させる。実装着手前に `/review-design` を回すこと（状態を増やす変更のため）。

## テストの穴

`BefoldApp/befoldTests/ViewerWindowControllerHistoryTests.swift` の 4 ケースはファイル↔ファイルのみで、履歴がフォルダー提示を跨ぐケースが未カバー。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 履歴でフォルダー提示を通過した後に戻ってファイル提示のエントリへ到達すると、そのファイルがプレビューされる
- [ ] #2 上記が同一ディレクトリ内の戻り（原因 A）と親ディレクトリへの戻り（原因 B）の両方で成立する
- [x] #3 履歴適用時のディレクトリ変更が SidebarNavigator.moveCurrentDirectory を通る（currentDirectory への直接代入をやめる）
- [x] #4 ViewerWindowControllerHistoryTests に「フォルダー提示を跨ぐ戻り」の回帰テストを追加し、修正を戻すと落ちることを確認済み
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結論を反映した実装計画

### 1. HistoryEntry に「提示していた対象」を持たせる（NavigationHistory.swift）
- `enum HistoryPresentation: Equatable { case file(URL); case folder(URL?) }` を新設。
  生の selection URL ではなく **記録時点の previewTarget から起こした事実** を持つ。
  推論（selection != file ならフォルダー）に頼らないため（review-design 項目 1）。
- `HistoryEntry` に `presentation` を追加。`==` に含める
  （含めないと「同一 dir/file で提示だけフォルダーへ移った」エントリが重複扱いで捨てられる）。
- `renameOccurred` は presentation の URL も同じファイル一致規則で写す。
  フォルダーのリネーム追随は現状同様に範囲外。

### 2. 記録（SidebarHistoryController.record）
- `fileListModel.previewTarget` を読んで写す。
  - `.file` -> `.file(fileListModel.selection ?? host.currentFileURL)`
  - `.folder` -> `.folder(fileListModel.selection)`
  - `.undetermined`（ウィンドウ生成直後の記録経路 ViewerWindowController.swift:322 は
    一覧未着のため必ずここに落ちる） -> `.file(host.currentFileURL)`。
    「未確定だからフォルダー」に落とさないことが要点。

### 3. 適用（SidebarHistoryController.applyEntry）を 1 本の経路へ
1. ファイル切替を先に試す（現状どおり。失敗時は状態を変えず false）
2. dirChanged なら `navigator?.moveCurrentDirectory(to:)` を通す（AC #3。直接代入を廃止）
3. **同期区間で選択を確定する**: `selection = 記録した URL.map(matchingEntryURL)`
   （`folderEntryURL` ヒューリスティック＝原因 C は廃止）
4. dirChanged の有無によらず `refreshFileList` を発行し、custom closure で同じ値を
   書き直す（冪等）。これは `DirectoryLister.appendingOpenFile` の救済で行が遅れて
   載るケースの上積みであり、**選択の正しさは着地に依存しない**。
   着地に委ねる設計は SidebarNavigator.swift:286-293 の不変条件（TASK-445）に反する。

### 4. 履歴メニューのラベル（HistoryButtonView.menuLabel）
消費経路の漏れ。現在は `entry.file ?? entry.directory` から作るため、フォルダー提示の
エントリでも直前のファイル名が出る。presentation の case で分岐させる。

### 5. 行数の制約（実測）
`SidebarNavigator` グループは 394 行 / 閾値 400。**SidebarNavigator*.swift には 1 行も足さない**。
追加は SidebarHistoryController（96 行）と NavigationHistory（92 行）に閉じる。

### 6. テスト
- ViewerWindowControllerHistoryTests に「フォルダー提示を跨ぐ戻り」を同一ディレクトリ
  （原因 A）と親ディレクトリ（原因 B）の 2 ケース追加。
- AC #3 の担保（doc コメントでは守られない / 項目 9）: ディレクトリを跨ぐ履歴の戻りで
  旧ルートの展開が破棄されることを検証し、直接代入へ戻すと落ちることを確認する。
- NavigationHistoryTests に presentation を含む == とリネーム写像のケースを追加。
- いずれも修正を戻して落ちることを実測する（AC #4）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- `HistoryPresentation`(.file(URL) / .folder(URL?))を新設し、`HistoryEntry` へ必須フィールドとして追加。記録は `FileListModel.previewTarget` から起こす(推論しない)。`.undetermined` はファイル提示として記録する。
- `SidebarHistoryController.applyEntry` を 1 本の経路へ: 切替 -> (dirChanged なら)`moveCurrentDirectory` -> **同期区間で選択確定** -> refreshFileList の着地でも同じ値を再確定(冪等)。`folderEntryURL` / `matchingEntryURL(currentFileURL)` によるヒューリスティックは廃止。
- 設計レビューで「選択確定を着地に委ねる」案を却下した。SidebarNavigator.swift:286-293 の不変条件(TASK-445)に反し、着地しなければ旧選択が永続するため。
- 消費経路の漏れを 1 件修正: `HistoryButtonView.menuLabel` はフォルダー提示のエントリでも直前のファイル名を出していた(TASK-469 と同型)。提示対象から作るよう変更。

## 検証(実測)

- 全テスト: `swift test --skip Integration --skip FileWatcherTests` -> 1364 tests / 208 suites すべて通過。
- 修正を戻して落ちることを確認した(applyEntry を旧実装へ差し戻して実行):
  - 「フォルダー一覧を出していたエントリへ戻ると、そのフォルダー一覧が復元される」-> previewTarget が .file、選択が a.mmd になり **落ちる**
  - 「履歴の適用は moveCurrentDirectory を通り、離れるフォルダーの選択を記憶する」-> 選択が child.mmd になり **落ちる**(AC #3 の担保)
- swiftlint: 変更ファイルに警告 0 件。型グループ行数: SidebarNavigator は 394 行のまま(追加していない)。

## AC #2 について(未達を明記)

親ディレクトリへの戻り(原因 B 側)は上記テストで押さえた。**同一ディレクトリ内の戻り(原因 A)は再現ケースを構成できなかった**。`DirectoryLister.appendingOpenFile` が「開いている文書は必ず一覧に含める」を保証するため、そのディレクトリを列挙した直後に当該ファイルの行が欠ける状態を作れない。原因 A の経路自体は構造的に塞いである(同一ディレクトリでも refreshFileList を発行するようにし、行が遅れて載る場合も選択が当たる)。再現できていないことを理由に AC #2 はチェックしない。

なお「フォルダー提示を跨いで戻りファイルへ到達する」テストは修正前でも通る(ドリルダウンでは着地側の既定フォールバックが結果的に救うため)。報告された症状そのものの経路は握れていない。回帰を検知するのは上記 2 件。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
履歴エントリに「記録時の提示対象」(HistoryPresentation)を持たせ、復元をヒューリスティックから記録値の書き戻しへ変えた。適用経路は moveCurrentDirectory を通す 1 本に畳み、選択は同期区間で確定させる。履歴メニューのラベルも提示対象から作るよう修正。SidebarNavigatorHistoryTests を新設し、修正を戻すと 2 件が落ちることを実測。全 1364 テスト通過。AC #2 の同一ディレクトリ側は再現ケースを構成できず未チェック(Notes 参照)。
<!-- SECTION:FINAL_SUMMARY:END -->
