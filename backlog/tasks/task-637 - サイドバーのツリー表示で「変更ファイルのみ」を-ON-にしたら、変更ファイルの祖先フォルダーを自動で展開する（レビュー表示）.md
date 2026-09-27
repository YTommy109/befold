---
id: TASK-637
title: サイドバーのツリー表示で「変更ファイルのみ」を ON にしたら、変更ファイルの祖先フォルダーを自動で展開する（レビュー表示）
status: Done
assignee:
  - '@claude'
created_date: '2026-09-27 05:47'
updated_date: '2026-09-27 06:09'
labels: []
dependencies: []
priority: medium
type: enhancement
ordinal: 837000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 動機

コーディングエージェントが書いた変更をレビューするとき、GitHub の PR 画面のように変更ファイルを全階層で開いた状態で一覧したい。現状、ツリー表示で「変更ファイルのみ」を ON にしても、畳まれたフォルダーの中は出ない。行の元が「表示中ディレクトリの列挙＋展開済みフォルダーの子」だけで、絞り込みはその行にしか効かないため（`Viewer/SidebarTreeFilter.swift` / `Viewer/SidebarRowBuilder.swift`）。フォルダーを 1 つずつ開かないと変更ファイルに辿り着けない。

## 決定済みの仕様（2026-09-27 ユーザー確認済み）

- **新しいモード・状態は作らない。** 「ツリー表示 × 変更ファイルのみ」の組み合わせをそのままレビュー表示とみなす。UI に「コードレビュー」等の名前も出さず、2 設定を一括で ON にするメニュー項目も作らない。
- **規則は 1 つ**: 組み合わせが成り立った時点で、表示中ディレクトリ配下の変更ファイルの祖先フォルダーを展開集合（`SidebarExpansion.expandedKeys`）へ**足す**。既存の展開は閉じない（和集合）。
- 規則が走る契機: (1) 組み合わせに入ったとき（ON にする順序は問わない） (2) レビュー表示中のフォルダー移動（`moveCurrentDirectory` が展開を捨てるため） (3) git 状態の更新（新しく変更を持つようになったフォルダーだけ。更新前の git 状態との比較で求め、状態は足さない） (4) 窓を開いたとき（`SidebarInheritance` で引き継いだ上で）。
- レビュー表示中のユーザーの開閉は尊重する。閉じたフォルダーが git 更新で開き直らない。
- **解除時（ツリーを外す / 変更のみを外す）は展開をそのまま残す。** 入る前の展開へ戻すための保存状態は作らない。
- **範囲は表示中ディレクトリ配下のみ**（既存の変更のみ表示と同じ）。git ルートへの自動移動はしない。
- 丸ごと新しい untracked フォルダー（git 状態で `newdir/` の 1 エントリに畳まれる。`App/GitStatusReader.swift` の `statusFlags` 参照）は **1 段だけ開く**。中を再帰的には開かない（列挙回数の上限が無くなるため）。
- サブモジュール（`isIndeterminate`）の中には入らない。削除ファイルは現状どおり出ない（GitHub との差として受け入れる）。

## TASK-361.5 の却下案 B との関係

TASK-361.5 は名前フィルタで「一致する子を持つ未展開フォルダーを自動展開する」案 B を却下した（再帰列挙が要る / I/O を持たない `SidebarRowBuilder` と衝突 / 勝手に開くと驚く / 奥を探すのは Quick Open の役割）。今回は当たらない: 祖先は git 状態（リポジトリ全体ぶんの絶対パスキー。`SidebarGitStatus.covers`）からメモリ上で分かり、列挙は展開フォルダー 1 つにつき 1 回で既存の上限内。展開集合を書き換えるだけで `SidebarRowBuilder` は変えない。ユーザーが組み合わせを選んだときだけ開く。

## 未確認の前提

- `newdir/` 配下の子ファイルに untracked バッジが付くか（付かなければ変更のみ表示で子が消え、「1 段開く」が空振りする）。`SidebarGitStatus.folderStatus` と `SidebarChangedFilesOnlyIntegrationTests` で確認できる。
- 変更フォルダーが数百ある場合に、展開 1 つにつき列挙 1 回で重くならないか。未計測。

## 着手時の注意

状態・共通経路（`applyDisplayChange`、展開集合）に触る変更なので、実装前に `/review-design` を回し、結果を Implementation Plan に反映する。関連: TASK-353（比較基準の切り替え。バッジが追従すれば展開対象も変わる）、TASK-403（ネストしたリポジトリ・サブモジュールの限界）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 「変更ファイルのみ → ツリー」「ツリー → 変更ファイルのみ」のどちらの順で ON にしても、表示中ディレクトリ配下の変更ファイルの祖先フォルダーがすべて展開され、同じ展開集合になる（テストで検証）
- [x] #2 組み合わせに入る前から開いていたフォルダーは閉じられない（和集合であることをテストで検証）
- [x] #3 レビュー表示中にユーザーが閉じたフォルダーは、git 状態が更新されても開き直らない。新しく変更を持つようになったフォルダーだけが展開される（テストで検証）
- [x] #4 レビュー表示中に別のフォルダーへ移動すると、移動先で同じ規則が適用される（テストで検証）
- [x] #5 ツリーを外す / 変更のみを外すと、展開はそのまま残る。再びツリーに戻すと、残った展開に和集合で規則が再適用される（テストで検証）
- [x] #6 表示中ディレクトリの外にある変更は展開対象にならない（テストで検証）
- [x] #7 丸ごと新しい untracked フォルダーは 1 段だけ展開され、その子が変更のみ表示で表示される（未確認の前提を着手時に確認し、結果を Notes に残す）
- [x] #8 サブモジュールの中は展開しない（テストで検証）
- [x] #9 変更フォルダーが数百ある実リポジトリで、組み合わせに入ってから描画が落ち着くまでの時間を実測し、Notes に記録している
- [x] #10 viewer-ui.md のサイドバー節に、この規則と契機・解除時の振る舞いを追記している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarGitStatus に foldersToReveal(under:isDirectory:) を足す（純粋関数）。対象 = folders のキーのうち表示中ディレクトリの厳密な配下で、(a) files に無い（=変更の祖先フォルダー）か (b) files で untracked かつ実ディレクトリ（丸ごと新しいフォルダー。1 段だけ）。indeterminateRoots とその配下は除く。
2. SidebarTreePresenter.revealChangedFolders(since:) を足す。ツリー×変更のみ×gitStatus あり のときだけ動く。印 revealedDirectoryKey（全件適用済みの表示中ディレクトリ）が今のディレクトリと一致すれば since の状態との差分だけ、一致しなければ全件を expandFolder する。組み合わせを外れていたら印を消す。
3. 呼び出し点: (a) applyRows の末尾（ルート一覧の着地後 = 移動・窓を開く・ツリー切替を拾う。reloadExpandedChildren の後なので券が無効化されない）(b) FileListModel.gitStatus の didSet から通知（反映と setEntries での昇格の両方を拾う）(c) SidebarNavigator.applyDisplayChange の後（変更のみの切替は一覧を取り直さないため）。
4. テスト: 両順序で同じ展開集合 / 和集合 / 閉じたフォルダーが git 更新で開き直らない / 移動先で再適用 / 解除で残り再適用で和集合 / 範囲外 / untracked 1 段 / サブモジュール除外。
5. 実測（数百フォルダー）と viewer-ui.md 追記。

review-design 反映: (c) の呼び出しは SidebarNavigator（425 行・恒久例外）ではなく SidebarListingCoordinator.applyDisplayChange の末尾へ置く（tree を既に持つ）。applyRows はフォーカス復帰ごとに走るため、印が一致し since == 現在の状態なら候補計算前に return する。FileListModel の通知は onPresentationTargetChange と同じ @ObservationIgnored クロージャの前例に倣う。サブモジュールは indeterminateRoots（事実）で、丸ごと新しいフォルダーはファイルシステムの isDirectory（事実）で判定し、キーの形では判定しない。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装
- 規則は SidebarTreePresenter.revealChangedFolders(since:) の 1 本。呼び出し点は 3 つ: applyRows の末尾（ルート一覧の着地 = 移動・窓を開く・ツリーへの切替）、FileListModel.gitStatus の didSet → onGitStatusChange（反映と setEntries での保留の昇格の両方を拾う）、SidebarListingCoordinator.applyDisplayChange の .toggleChangedFilesOnly（一覧を取り直さない切替）。
- 「全件を開く」か「git 差分だけ開く」かを分けるため、presenter に revealedDirectoryKey（全件適用済みの表示中ディレクトリ）を 1 つ持つ。入る前の展開を戻すための保存ではない（Description の決定どおり）。無いと、入るとき（git 状態は既に同じ）と定常の更新が区別できない。
- 展開対象は SidebarGitStatus.foldersToReveal。GitFolderStatus.aggregate は変更ファイル自身のキーも集約に入れるため、folders のキーのうち files に無いもの = 祖先フォルダー。丸ごと新しい未追跡フォルダーは pathKey で末尾スラッシュが落ちてファイルと区別できないため、FileManager の isDirectory で判定（ponytail コメント: 未追跡 1 件につき stat 1 回）。indeterminateRoots（サブモジュール・ネストしたリポジトリ）とその配下は除外。
- ツリーへの切替では applyDisplayChange 側で開かない。ルート一覧の着地前に開くと、着地した子リストが古い lastListing で行を組み直す（SidebarLayoutTransition.revealSelection と同じ理由）。applyRows 側で拾う。

## 未確認だった前提の確認結果
- newdir/ 配下の子ファイルに untracked バッジが付くか: 付く。SidebarGitStatus.fileStatus が祖先の畳み込みを見て未追跡を返し、hasChange はそこへ委ねる（既存テスト SidebarGitStatusTests.reportsUntrackedForFilesUnderCollapsedDirectory）。
- 数百フォルダーでの重さ（AC#9）: .tmp に 100 dir × 3 subdir = 400 変更フォルダー・300 変更ファイルの実リポジトリを作り、実 GitStatusStore と DirectoryLister で、変更のみ ON から全 300 ファイル行が揃うまでを測定。規則の同期部分は 38〜53ms。全行が揃うまでは 3.78 / 3.81 / 4.05 秒。原因は子リストの着地ごとの行の全組み直し（700 行で 1 回約 12ms × 400 回）。着地の組み直しを同時期のぶんで 1 回へまとめる scheduleRebuild を入れて 80ms になった。全テストとサイドバー系 542 件 × 3 回で退行なし。

## 検証
- 追加テスト: SidebarGitStatusRevealTests 4 件、SidebarNavigatorReviewExpansionTests 5 件（引数 2 ケース込みで 6）。
- 差分計算（isRevealed の分岐）を壊すと gitUpdateRevealsOnlyNewlyChangedFolders が Expectation failed: expandedFolderKeys == [key(b)] で落ちることを確認。早期 return（isRevealed && previous == status）を外しても落ちないのは想定どおり（差分が空になるだけの最適化）。
- swift test 全件: 1997 + 72 件 pass。xcodebuild build 成功。swiftlint は origin/main と差分ゼロ（真の新規・解消とも 0）。swiftformat の lint で整形ずれ 0。
- 型グループ: FileListModel 398 / SidebarTreePresenter 288 / SidebarListingCoordinator 207 / SidebarGitStatus 168 行（check-type-group-size.sh 通過）。
- 現在仕様: docs/dev/viewer-ui.md のサイドバー節に「レビュー表示」を追記。native-app-design.md は型の追加・依存の向きの変更が無いため更新不要。

## 責務レビュー（responsibility-reviewer）
- High / Medium なし。L1（onGitStatusChange を購読側の presenter が init で繋いでおり、前例の onPresentationTargetChange は組み立て側で繋いでいる）: FileListModel の doc に「購読者は SidebarTreePresenter の 1 者。上書きしない」を明記して対応。
- L2（presenter が FileManager で直接 stat）: 見送り。判定の本体は foldersToReveal(isDirectory:) の純粋関数に切り出してあり、単体テストはそちらで isDirectory を差し替えて書ける。presenter へ注入クロージャを足しても、差し替えたいテストが現状ない。
- AC#5 のツリーを外して戻す経路も SidebarNavigatorReviewExpansionTests.leavingTreeKeepsExpansionAndReenteringReapplies で検証（テストは計 6 件）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーが「ツリー表示 × 変更ファイルのみ」のとき、表示中ディレクトリ配下の変更ファイルの祖先フォルダーを展開集合へ足す（和集合）。規則は SidebarTreePresenter.revealChangedFolders(since:) の 1 本で、呼び出し点はルート一覧の着地・git 状態の変化（FileListModel.onGitStatusChange）・変更のみの切り替えの 3 つ。git 更新では更新前の状態との差分だけを開くので、閉じたフォルダーは開き直らない。展開対象の算出は SidebarGitStatus.foldersToReveal。丸ごと新しい未追跡フォルダーは 1 段だけ開き、サブモジュールの中には入らない。実測で 400 フォルダーだと全行が揃うまで 3.8 秒かかったため、子リスト着地の行の組み直しを 1 回へまとめて 80ms にした。viewer-ui.md に仕様を追記。
<!-- SECTION:FINAL_SUMMARY:END -->
