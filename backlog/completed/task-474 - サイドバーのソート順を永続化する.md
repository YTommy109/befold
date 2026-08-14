---
id: TASK-474
title: サイドバーのソート順を永続化する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-13 11:31'
updated_date: '2026-08-13 13:39'
labels: []
dependencies: []
priority: low
ordinal: 695000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ソート順は現在 FileListModel.sortOrder 直書きでウィンドウごと・非永続。⋯ メニューへ移した(TASK-473)ことで設定らしい見た目になったが、再起動で既定へ戻る。UserDefaults へ永続化するなら、CLAUDE.md「UserDefaults キーの廃止・改名」の手順(移行経路を 1 本に畳む・defer での stale キー削除・3 ケースのテスト)に従うこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーのソート順が再起動後も保たれる
- [x] #2 全ウィンドウで同じソート順になるか、窓ごとに独立かの判断が Implementation Notes に記録されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化検討: 新しい仕組みは足さない。並び順の保存先は既存の SidebarDisplayPreference（サイドバー表示設定の UserDefaults 置き場）へ相乗りさせ、専用のストアは作らない。
2. 粒度の決定（AC #2）: 窓が生きている間は窓ごとのライブ値、保存値は「次に窓を開くときの既定値」。ADR 0002 の 2 分類でいう「文書の状態」側の持ち方で、行番号表示（ViewerStore.showLineNumbers + アプリ全体の既定値）と同型。既に開いている他窓へは配らない。
   → 当初案（隠しファイル表示と同じ「アプリの好み」= GlobalDisplayBroadcaster で全窓即時同期）は採用しない。採用しないことで、CLI --sort が「その起動限りの窓単位の上書きで保存済み設定は書き換えない」（SessionRestorer の doc に明記された既存の不変条件）のまま保てる。
3. SortOrder（Viewer/FileListEntry.swift）に String raw 値を与え、SidebarLayoutMode.stored(_:) と同型の static func stored(_:) を置く。壊れた値・未設定は既定 .foldersFirst へ倒す。
4. SidebarDisplayPreference へ sortOrder を追加（キー SidebarSortOrder、didSet で保存、init で stored 読み込み）。フィーチャーゲート対象外なので降格読みは無し。
5. 書き込み経路を 1 本に絞る: SidebarListingCoordinator.setSortOrder(_:) がライブ値の更新・既定値の保存・refreshFileList を必ず対で行う唯一の入口。SidebarNavigator は委譲のみ。⋯ メニューは ViewerWindowAssembler の onSortOrderChanged からここへ入る。
   → 置き場所を SidebarNavigator にしないのは、そこへ置くと型グループが 404 行となり scripts/check-type-group-size.sh の閾値 400 を超えるため。閾値は緩めず、preference と refreshFileList を既に持つ SidebarListingCoordinator へ責務ごと置く。
6. 新規ウィンドウの初期値は「CLI の明示指定 > 保存された既定値」。SidebarNavigator.init の sortOrder を Optional 化し、nil なら sidebarDisplayPreference.sortOrder から始める。ViewerWindowController.initialSortOrder も Optional 化し、ViewerWindowManager+OpenViewer は options.sortOrder != nil のときだけ値を渡す。
7. syncDisplayPreferences() では sortOrder を同期しない。ここで preference を読み直すと、生きている窓が他窓の操作を後から拾ってしまい粒度が破れる（かつ CLI の窓単位の上書きが潰れる）。
8. ViewerDisplayOptionsApplier の CLI --sort はそのまま（窓のライブ値だけを書き、既定値は書き換えない）。その意図をコメントで明示する。
9. UserDefaults 移行: 旧キーは存在しない（並び順はこれまで一度も永続化されていない）ため、移行経路・stale キー削除は不要と明示的に判断する。
10. テスト: (a) 既定は .foldersFirst、(b) 保存値が次のインスタンスへ引き継がれる、(c) 壊れた raw 値は既定へ倒れる、(d) 新しい窓は保存された既定値で始まる、(e) setSortOrder がライブ値と既定値の両方を更新する、(f) 並び順変更後に開いた窓が追随する、(g) 既に開いている別窓は変わらない（粒度の担保）、(h) 初期値の明示指定は既定値を書き換えない（CLI の担保）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 粒度の判断（AC #2）

**窓が生きている間は窓ごとのライブ値、保存値は「次に窓を開くときの既定値」**とした（ユーザー指示による確定）。ADR 0002 の 2 分類でいう「文書の状態」側の持ち方で、行番号表示（ViewerStore.showLineNumbers + アプリ全体の既定値）と同型。

当初は隠しファイル表示・変更ファイルのみ表示と同じ「アプリの好み」（全ウィンドウ即時同期）を提案したが、採用しなかった。採用しなかったことで、CLI --sort が「その起動限りの窓単位の上書きで保存済み設定は書き換えない」（SessionRestorer の doc に明記された既存の不変条件）のまま保てている。

## UserDefaults の移行判断

新設キー SidebarSortOrder には**旧キーが存在しない**（sortOrder はこれまで一度も永続化されておらず、FileListModel の直書きのみだった）。したがって CLAUDE.md「UserDefaults キーの廃止・改名」の移行経路・stale キー削除は**不要**と明示的に判断した。読み手が消える旧キーも無い。

## 書き込み経路の絞り込み

ライブ値の更新と既定値の保存が必ず対になるよう、利用者操作の入口を SidebarListingCoordinator.setSortOrder(_:) の 1 本に絞った（SidebarNavigator は委譲のみ）。唯一の例外は CLI --sort で、これは既定値を書き換えないことを doc とテストの両方で固定している。

置き場所を SidebarNavigator ではなく SidebarListingCoordinator にしたのは、前者に置くと型グループが 404 行となり scripts/check-type-group-size.sh の閾値 400 を超えたため。閾値は緩めず、preference と refreshFileList を既に持つ後者へ責務ごと移した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの並び順を UserDefaults の新設キー SidebarSortOrder へ永続化した。粒度は「窓が生きている間は窓ごとのライブ値、保存値は次に窓を開くときの既定値」（ADR 0002 の「文書の状態」側）。SortOrder に String raw 値と stored(_:) を与え、SidebarDisplayPreference にキーを追加、SidebarListingCoordinator.setSortOrder(_:) をライブ値更新と既定値保存が対になる唯一の入口とした。CLI --sort は従来どおりその起動限りの窓単位の上書きで、既定値を書き換えない。

検証: swift test 1517 件全通過（240 suites）。xcodebuild build -scheme befold 成功。scripts/check-type-group-size.sh --check 通過（SidebarNavigator が 404 行で閾値超過したため setSortOrder を SidebarListingCoordinator へ移して解消）。swiftlint は origin/main を git archive で別ディレクトリへ展開して比較し、65 件で差分ゼロ。新規テストは修正を戻すと落ちることを実測で確認済み（初期値の preference 読み取りを外すと永続化 3 件が落ち、逆に列挙のたびに保存値を読み直す実装にすると CLI 上書きのテストが落ちる）。
<!-- SECTION:FINAL_SUMMARY:END -->
