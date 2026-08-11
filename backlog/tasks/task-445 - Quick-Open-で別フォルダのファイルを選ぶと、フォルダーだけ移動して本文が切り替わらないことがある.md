---
id: TASK-445
title: Quick Open で別フォルダのファイルを選ぶと、フォルダーだけ移動して本文が切り替わらないことがある
status: To Do
assignee: []
created_date: '2026-08-11 08:17'
updated_date: '2026-08-11 13:52'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 100650
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 症状（ユーザー報告）

Quick Open（cmd+p）で選んだファイルが開かないことがある。サイドバーのフォルダーは選んだファイルのフォルダーへ移動するのに、ビューア本文が切り替わらない。現在表示中のファイルとは**異なるフォルダー**のファイルを選んだときに起きているように見える。

## 現時点で分かっていること（静的調査のみ。再現・実測は未実施）

決定からオープンまでの経路:

1. `QuickOpenModel.commitSelection()`（BefoldApp/befold/App/QuickOpenModel.swift:113-117）— `await environment.resolveFileToOpen` を挟んでから `onOpen`
2. `QuickOpenPanelController.present()` 内のクロージャ（QuickOpenPanelController.swift:70-73）— `dismiss()` してから `onOpen(url)`
3. `AppDelegate.openFromQuickOpen(_:)`（AppDelegate.swift:447-453）— `activeViewerController` があれば `switchFile(to:)`、無ければ `openViewer(for:)`
4. `ViewerWindowController.switchFile(to:)`（ViewerWindowController+FileNavigation.swift:36-46）→ `performFileSwitch`（:55-73）で `store.openFile(newURL)` → 成功時のみ `sidebar.syncAfterSwitch(to:)`
5. `SidebarNavigator.syncAfterSwitch(to:)`（SidebarNavigator.swift:349-358）でフォルダー移動

本文の読み込み（`ViewerStore.openFile` → `loadContent`、ViewerStore.swift:247-264 / 343-368）は世代ガード付きの非同期。フォルダー移動（`refreshFileList` → `performListing`、SidebarNavigator.swift:197-219 / 240-280）は別タスクの非同期。**2 つは別々の非同期経路**で、症状は「後者だけ成功し前者が反映されない」形に一致する。

## 未確認の疑い（着手時にここから潰す）

- **A. `activeViewerController` が `NSApp.mainWindow` 依存**（AppDelegate.swift:237-239）。Quick Open パネルは `.nonactivatingPanel` の borderless panel（main にはならない想定）だが、`dismiss()` 直後に `NSApp.mainWindow` が nil を返す瞬間があると `openViewer(for:)` 側へ落ち、期待と違うウィンドウ挙動になりうる。
- **B. `syncAfterSwitch` の分岐が非対称**（SidebarNavigator.swift:349-358）。同一フォルダー分岐は `fileListModel.selection` を同期的に確定するが、別フォルダー分岐は確定せず非同期の `refreshFileList` 着地に委ねる。症状が「別フォルダーのときだけ」である報告と分岐が一致する。
- **C. `commitSelection()` の await 中に候補配列が差し替わりうる**（QuickOpenModel.swift:113-117。URL はキャプチャ済みのため誤ファイルを開くことは無いが、確定タイミングの競合は残る）。

再現条件（フォルダー階層・ツリー表示 ON/OFF・絞り込みの有無・毎回か時々か）が特定できていないため、まず再現から入ること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 別フォルダーのファイルを Quick Open で確定したとき、サイドバーの一覧取得タスクが世代の追い越しなどで着地しなかった場合でも、previewTarget が .folder に落ちたまま残らない
- [ ] #2 別フォルダー・同一フォルダーのいずれのファイルを Quick Open で確定しても、サイドバーのフォルダー移動と本文の切り替えが必ず両方反映される
- [ ] #3 syncAfterSwitch の同一フォルダー分岐と別フォルダー分岐で選択確定の扱いが非対称なまま残らない（統一するか、非対称である理由を doc コメントで明示する）
- [ ] #4 上記を破ると落ちるユニットテストがある（一覧の着地を起こさずに syncAfterSwitch を実行し、previewTarget が .file であることを検証する）
- [ ] #5 疑い D（ViewerRenderer.handleNavigationFailure による pendingUpdate の上書き）は本タスクの対象外として別タスクに起票されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 再現条件の追加情報（ユーザー報告 2026-08-11）

- サイドバーのツリー表示: OFF
- 絞り込み: なし
- 発生頻度: 時々（毎回ではない）。パターンは不明

**間欠的である**ことから、静的な分岐ミスではなく非同期の着地順に依存する競合の可能性が高い。Description の疑い A / B のうち、決め打ちせずまずログを仕込んで再現を捕まえること。

## 描画側の追加調査（静的調査、実測なし）

ViewerStore の content が更新されたのに WKWebView が追従しない経路を洗った結果:

- 描画の sink は `ViewerContentView`(:69-90) → `ViewerWebView.updateNSView`(:97-108) → `ViewerRenderer.updateContent` の 1 本のみ。`onContentReloaded` は描画に関与しない（ツールバー・git バッジ更新のみ、ViewerStore.swift:413）
- `performFileSwitch` の順序（applyDisplayMode → applyURLToWindow → store.openFile → beginPresentingDocument）と `loadGeneration` の組み合わせに穴は見つからず。`ViewerStore.apply()`(:378-380) が filePath と content を同時確定するため「新パス＋旧本文」の中間状態は作れない
- 描画ミラーの確定は `recordRendered`(ViewerRenderer+RenderHelpers.swift:163-165) の 1 箇所で、`applyRender` は await 復帰後の世代ガードから送信・記録までを同期区間に閉じている。TASK-320/334/336 型の穴は塞がれたまま

### 疑い D（新規・条件は狭い）

`ViewerRenderer.handleNavigationFailure`(ViewerRenderer.swift:358-368) → `exitDirectHTMLMode` → `reloadViewerHTML`(RenderHelpers.swift:214-228) が **単一スロットの `pendingUpdate` を無条件に上書き**する。直接 HTML モード中（.html を loadFileURL 中、`isReady == false`）に別ファイルへの切替が来ると更新は `pendingUpdate` に積まれるだけ(ContentUpdate.swift:235)で、そこにナビゲーション失敗が挟まると**積んだ描画要求が空 completion に置き換わって消滅**する。以後 SwiftUI 側の値は変わらないため再描画の契機が無い。

ただし前提が「切替元が .html の直接 HTML モード」かつ「そのナビゲーションが失敗する」であり、今回の報告（ツリー OFF・絞り込み無し・時々）と一致するかは未確認。**まず切替元ファイルの種別が .html だったかを確認すること。** 一致しない場合は疑い A / B へ戻る。

なお疑い D が真因でなくても `pendingUpdate` の単一スロット上書きは実在の欠陥なので、別タスクとして起票する価値がある。

## 症状の追加情報と本命の特定（2026-08-11）

ユーザー報告の補足: 切替**元**は `.swift` と `.sh`。症状は「前のファイルの内容が残る」または「**ファイル一覧が残る**」。

→ 切替元がソースコードのため **疑い D（直接 HTML モード + ナビゲーション失敗）は該当しない**。D は別の欠陥として残るが、この事象の原因ではない。

「ファイル一覧が残る」は決定的で、`ViewerContentView`(:43-52) が `previewTarget.folderURL != nil` のときだけ `FolderListingView` を重ね、`filePreview(isVisible:)` を opacity 0 にする実装（TASK-266 で常駐化）から、**`previewTarget` が `.folder` に落ちたまま戻っていない**ことを意味する。

### 疑い E（本命）: 別フォルダー分岐が currentDirectory だけ同期的に変え、選択の確定を落ちうるタスクに委ねている

`SidebarNavigator.syncAfterSwitch`(:349-358) の別フォルダー分岐は
`fileListModel.currentDirectory` を**同期的に**書き換え、選択の確定は
`refreshFileList` → `performListing` の非同期タスクへ委ねる（同一フォルダー分岐は
その場で `selection` を確定する。この非対称が疑い B）。

`performListing`(:240-280) の着地には二重のガードがある:

```swift
guard generation == self.listingGeneration, let host = self.host else { return }
onApplied(host, directory, entries)
```

**世代が追い越されるか host が nil になると `onApplied` が走らない**。その場合
`selection` は旧ファイルのまま、`currentDirectory` だけ新フォルダーに変わった状態で残る。
`PreviewTargetResolver.resolve`(:36-56) はこの状態で

```swift
guard let entry else { return hasLoadedEntries ? .folder(currentDirectory) : .undetermined }
```

に落ち、**`.folder(currentDirectory)` を返す＝ファイル一覧が出たまま**になる。
これは報告された症状そのもの。世代の追い越し（切替直後に走る別の一覧取得契機:
git 状態・フォーカス復帰・並び順同期など）に依存するため **間欠的**である点も一致する。

「前のファイルの内容が残る」ほうは、フォルダー一覧が重なっている間
`ViewerRenderer.updateContent`(ContentUpdate.swift:99) の `guard isVisible else { return }`
が描画要求を落とす（ミラーも更新しないので、可視へ戻れば再描画される設計）ため、
一覧が出たままなら旧内容が背後に残り続けることと整合する。

### 修正方針の候補（着手時に単純化を検討すること）

非対称を消す方向が本筋。次のどれかで、**非同期の着地に依存せずに previewTarget が
`.folder` へ落ちない**ようにする。

1. `syncAfterSwitch` の別フォルダー分岐でも、一覧の着地を待たず `selection` を
   新ファイルへ同期的に確定する（`matchingEntryURL` は一覧に無ければ生 URL を返すので
   確定自体は可能。一覧着地後に既存の保持/フォールバック処理が上書きする）
2. `PreviewTargetResolver` の「選択が索引に無い」フォールバックを、
   `currentFileURL` と一致するなら `.file` とする（`.folder` へ落とすのは
   選択が明示的に nil のとき、または選択が実在フォルダーのときに限る）
3. `currentDirectory` の書き換えと選択確定を 1 つの同期区間に閉じ、
   部分適用（dir だけ変わって選択未更新）を作れなくする。
   `applyHistoryEntry`(SidebarNavigator+History.swift:32-35) は同型の部分適用を
   避けるコメントを既に持っており、そこと揃う

いずれにせよ CLAUDE.md の「決めたことには破れたら落ちるものを付ける」に従い、
`onApplied` が走らなかった場合でも `previewTarget` が `.folder` にならないことを
検証するテストを置くこと。

疑い D は TASK-446 として別途起票済み。

ordinal を 673000 → 100650 へ繰り上げた（2026-08-11 の優先順位評価）。理由: ユーザー報告・再現条件の追加情報まで揃っている medium bug が、LOW の chore 群より下に沈んでボード最下部にあった。CLAUDE.md の「ボード表示順は ordinal 順」「HIGH タスクが MEDIUM/LOW より上に来るようにする」に反する配置。
<!-- SECTION:NOTES:END -->
