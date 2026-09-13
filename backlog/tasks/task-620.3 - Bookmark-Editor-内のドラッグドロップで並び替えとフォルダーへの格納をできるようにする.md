---
id: TASK-620.3
title: Bookmark Editor 内のドラッグ&ドロップで並び替えとフォルダーへの格納をできるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-09-13 11:43'
updated_date: '2026-09-13 15:11'
labels: []
milestone: m-9
dependencies:
  - TASK-620.2
parent_task_id: TASK-620
priority: medium
type: feature
ordinal: 813000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bookmark Editor では並び順が常に名前順（`BookmarkLibrary.children(of:)` がフォルダーは名前順、エントリは表示名順にソート）で変えられず、フォルダーへの格納も右クリック > フォルダーへ移動 からしかできない。行をドラッグして順序を変えたり、フォルダー行へ落として格納したりしたい。

TASK-536 の設計では「Bookmark Editor 内の行 D&D（並び替え・フォルダー間移動）」と「手動並び替え（保存順は持つが表示は名前順のまま）」を明示的にスコープ外にしていた（`docs/superpowers/specs/2026-09-12-bookmark-management-design.md` の対象外の節）。今回それを取り込む。

TASK-620.2 に依存させている理由: ⋯ ボタンは行の中に置くボタンで、行をドラッグ元にするとボタンのクリックとドラッグ開始の扱いが干渉しうる。行の構成を先に確定させてからドラッグを載せないと、行の組み直しで二度手間になる。

着手時に決めること・気をつけること:
- **表示順の意味が変わる**: いまユーザーが見ている順は名前順で、保存配列の順（追加順）とは違う。手動順へ切り替えた瞬間に既存ユーザーの並びが崩れないよう扱う必要がある。永続化キー `Bookmarks` の値の意味を変える変更なので CLAUDE.md「UserDefaults キーの廃止・改名」の節を通す
- Bookmarks メニュー（`BookmarksMenuController`）も同じ `children(of:)` で並ぶ。Bookmark Editor とメニューで順序が食い違わないこと
- 手動順を入れても「フォルダーが先、エントリが後」を保つか、混在を許すか
- 新しく追加したブックマーク（cmd+D・CLI・Finder からの D&D）がどこに入るか
- Bookmark Editor とフォルダー行には既に Finder からの `.onDrop(of: [.fileURL])`（`BookmarkManagerView+Drop`）がある。Bookmark Editor 内の行ドラッグと Finder からのドロップを取り違えない
- ドラッグ対象はブックマーク行。フォルダー行のドラッグ（フォルダーごとの移動・並び替え）を含めるかは着手時に判断し、含めないなら理由を Notes に残す
- 新しい状態・値の持ち方の変更なので、実装前に `/review-design` を回す
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ブックマーク行をドラッグして、同じ階層内の任意の位置へ並び替えられる
- [x] #2 ブックマーク行をフォルダー行へドロップすると、そのフォルダーの直下へ移る
- [x] #3 フォルダー内のブックマーク行をトップレベルへ（または別のフォルダーへ）ドラッグで移せる
- [x] #4 並び替えた順序がアプリ再起動後も保たれ、Bookmarks メニューにも同じ順序で出る
- [x] #5 既存ユーザーの保存データを読み込んだ直後の並びが、変更前に見えていた並びと変わらない（移行のテストで担保する）
- [x] #6 Finder からのドロップによる追加（TASK-536.3）が従来どおり動く
- [x] #7 native-app-design.md のブックマーク関連の記述が実装に追随している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
ユーザー決定（2026-09-13）: 各階層でフォルダーが先（名前順・ドラッグ不可）、ブックマークは保存順。初回だけ既存データを表示名順へ並べ替えて保存し、移行済みの印を付ける。新規追加は行き先の末尾。

モデル（BefoldKit/BookmarkLibrary）
1. entries 配列の順 = 各階層での表示順。children(of:) はエントリをソートしない（フォルダーは名前順のまま）。表示名順の全件 entriesSortedByDisplayName と BookmarkManagerModel.entries は読み手がテストだけなので削除
2. BookmarkLibrary.hasManualOrder: Bool?（移行済みの印）と orderedManually()（表示名順へ安定ソートして印を付けた値を返す）
3. move(_:to:before:) — エントリを取り外し、before（同じ行き先に居る兄弟の URL）の直前へ、nil なら配列末尾（= 行き先の末尾）へ入れる。既存の move(_:to:) は before: nil
4. add は従来どおり末尾追加（= 行き先の末尾）。setAlias / replace は位置を変えない

永続化（BefoldKit/BookmarkStore）
5. init の一度きり移行を 1 本に畳む: 新キーの値（無ければ旧キー BookmarkedPaths からの変換）を読み、hasManualOrder != true なら orderedManually() を保存。旧キーは従来どおり defer で必ず削除
6. テスト 3 ケース: (a) 印の無い既存データ → 表示名順に並び印が付く (b) データなし → 何も書かない (c) 移行済み → 順序を変えない（+ 旧キーからの変換も表示名順）

ビュー（BookmarkManagerView + 新規 BookmarkManagerView+Reorder）
7. ドラッグ元: ブックマーク行の本体（⋯ を除く）に .onDrag。アプリ内専用の型 com.degino.befold.bookmark（.fileURL は載せない = Finder からのドロップと取り違えない）
8. 行間へのドロップ: 各階層のエントリの ForEach に .onInsert(of: [内部型]) → move(to: その階層, before: 挿入位置の兄弟)。挿入位置の兄弟はドロップの瞬間に同期で決め、非同期の取り出し後に index を引き直さない
9. フォルダー行へのドロップ: 既存の .onDrop に内部型を足し、内部型ならそのフォルダーの末尾へ move、.fileURL なら従来の Finder 追加。Bookmark Editor 全体の受け口も同様（→ トップレベル末尾）
10. 実機で並び替え・フォルダーへの格納・トップレベルへの取り出し・再起動後の保持・メニューの順・Finder ドロップの非退行を確認

/review-design（2026-09-13）
- 1 判定の真実の源: 移行済みかは印（事実）で判定し、配列の並びの形からは推定しない。内部ドラッグと Finder の判別は型（内部型 / .fileURL）で、内部ドラッグは .fileURL を載せない
- 2 不変条件: 1 パス 1 件は取り外して入れ直すので保たれる。フォルダーが先は ForEach の順で構造的に保たれる。記録の無い所属（ルート扱い）の兄弟判定は resolvedFolder で行う
- 3 消費経路: 並びの読み手は children(of:)（Bookmark Editor・メニュー）と deleteFolder の繰り上げ。bookmarkedURLs（Quick Open / Pruner）は順序に依存しない。兄弟判断: setAlias が暗黙に位置を変えていた効果は消える（意図どおり）
- 4 新状態の表示: 行間は onInsert の標準の挿入線。フォルダー行は既存 Finder ドロップと同じく強調なし
- 5 順序: 移行は init で cached を作る前に 1 回。CLI プロセスの BookmarkStore でも走る（旧キー移行と同じ扱い）
- 6 コスト: children(of:) からソートが消え軽くなる
- 7 測るもの: 移行はテストで直接測る。メニューと Bookmark Editor は同じ children(of:) を読むので順序の一致はそこで測る
- 8 非同期: NSItemProvider の取り出しは非同期。挿入先は兄弟の URL で持ち、着地時に行き先や兄弟が消えていれば move が false で何もしない（index を持ち越さない）
- 9 決めたことの担保: 並びの規則は BookmarkLibrary の 1 箇所。move の before は兄弟が同じ行き先に居なければ末尾へ（テストで固定）
- 10 行数: BookmarkLibrary 288 → 約 320、BookmarkStore 160 → 約 175、BookmarkManagerView 332 → D&D を +Reorder へ出しても合算で約 380（閾値 400 に近い。超えるなら既存の +Drop と統合して重複を削る）
- フォルダー行のドラッグは含めない（ユーザー決定。入れ子の移動は循環の検査と名前衝突の規則が要り、別の判断になる）
- 旧版との往復: 旧版は hasManualOrder を知らず、保存し直すと印が落ちて次回の新版起動で表示名順へ並べ直される（手動順が失われる）。旧版へ戻す運用は想定しない
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装中に計画から変えた点:
- 移行の印の既定値: 「保存時に印を付ける」だけだと、印の無い新規ユーザーの最初の手動順が次回起動で表示名順へ並べ直される。BookmarkLibrary() の既定を hasManualOrder = true とし、nil になるのは旧版の JSON をデコードしたときと旧キーからの変換（migrated(fromPaths:)）だけにした
- ドラッグの型は Info.plist の UTExportedTypeDeclarations に com.degino.befold.bookmark-entry を宣言した。UTType(exportedAs:) だけでは挿入線は出るがドロップが届かなかった（実測: onInsert / handleReorder が一度も呼ばれない。宣言後は届いた）
- BookmarkLibraryTests が type_body_length / line_length で新規警告になったため、手動の並びのテストを BookmarkLibraryOrderTests.swift へ分けた（閾値は変えていない）

UserDefaults キーの意味変更（CLAUDE.md の節）: キー Bookmarks は廃止も改名もせず、エントリの配列順に意味を持たせた。移行は既存の旧キー移行（BookmarkStore.init）と 1 本に合流（旧キーからの変換 → 印が無ければ orderedManually() を保存 → defer で旧キーを削除）。テスト 3 ケース: 並び未移行の値あり → 表示名順・印あり・再起動後も同じ / 旧値なし → 何も書かない（既存テスト）/ 移行済み → 保存順を保ち書き直さない。旧キーからの変換も表示名順へ（既存テストを更新）。旧版が保存し直すと印が落ちて次回起動で表示名順へ戻る（旧版へ戻す運用は想定しない）。

AppKit のアウトラインの挙動（実測）: 展開したフォルダーの最後の子とその次の行の境目では、挿入先の段はポインタの横位置と上下で決まり、フォルダーの末尾として扱われることが多い（Finder のリスト表示と同じ）。指示線の丸の字下げが挿入先の段を示し、結果はこれと一致した。

検証:
- swift test --skip Integration --skip FileWatcherTests: 1939 件パス / xcodebuild ビルド成功 / swiftlint 差分ゼロ / 型グループ閾値内（BookmarkManagerView 386、BookmarkLibrary 316、BookmarkStore 172）
- 戻すと落ちる: 移行を止める → BookmarkStoreMigrationTests の並び未移行・旧値ありの 2 件 / handleDrop から並び替えの振り分けを外す → BookmarkManagerViewDropTests「パネル内の行を落とすと追加ではなく移動になり…」
- 実機（CGEvent でドラッグ、.tmp/TASK-620/6203-*.png。各ケースでドロップ直前の指示線と結果を突き合わせ、onInsert の index と兄弟を一時ログで確認してから外した）
  - 移行: 既存データ（印なし）で起動 → 並びは変わらず、保存値に hasManualOrder=true
  - AC1: トップレベルで diagram.mmd を sample-folder の直前へ（onInsert parent=[] index=0）
  - AC2: Degino を Sample フォルダー行へ → Sample の末尾（フォルダー行の onDrop → handleReorder）
  - AC3: Sample 内の task-535-sample.md を一覧下の空き領域へ → トップレベルの末尾
  - AC4: 名前順ではない並び（task-535 → diagram → sample-folder → table）で再起動 → Bookmark Editor と Bookmarks メニューが同じ順
  - AC6: 別プロセスの検証用ドラッグ元（NSURL を pasteboardWriter にする最小アプリ。Warp の全画面スペースに Finder の窓が出せないための代替）から extra.md を Sample 行へ → 追加され Sample の末尾に入った。並び替えの受け口は反応しない
- フォルダー行のドラッグは含めない（ユーザー決定）。フォルダー行は名前順のまま

responsibility-reviewer（1 回目はサブエージェントが無応答で打ち切られたため範囲を絞って再実行）: 要対応なし。任意 2 件はいずれも対応——(a) hasManualOrder を public private(set) にし public init の引数から外した（書き換えは型の中の migrated / orderedManually とデコードだけ）(b) onInsert の index → 兄弟の変換を +Drop の handleInsert / sibling(at:in:) へ移し、テスト「行間の挿入位置は直後のエントリへ直し、末尾なら兄弟なしにする」を追加。申し送り: BookmarkManagerView グループは 395 行（閾値 400）。次に D&D を足すなら取り出しと振り分けを別の型（例 BookmarkDragTransfer）へ切り出すこと。
対応後: swift test 1940 件パス / xcodebuild 成功 / swiftlint 差分ゼロ / 実機で table.csv をトップレベルの diagram.mmd の直前へ移せることを再確認（.tmp/TASK-620/6203-final.png）
native-app-design.md: BookmarkStore / BookmarksMenuController / BookmarkManagerView の行を更新
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Bookmark Editor のブックマーク行をドラッグして、同じ階層での並び替え・フォルダー行への格納・トップレベルへの取り出しをできるようにした。エントリの保存順を手動の並びとし（フォルダーは名前順で先）、既存データは初回起動で表示名順へ並べて印を付ける移行を旧キー移行と 1 本に合流させた（3 ケースのテスト）。ドラッグの型はアプリ内専用の UTType を Info.plist に宣言し、Finder からの追加と型で分けた。Swift 1940 件パス、実機で各 AC とメニューの順序・再起動後の保持・別プロセスからのファイルドロップ追加を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
