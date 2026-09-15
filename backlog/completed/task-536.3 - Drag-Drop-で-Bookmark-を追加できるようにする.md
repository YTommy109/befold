---
id: TASK-536.3
title: Drag & Drop で Bookmark を追加できるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-21 07:27'
updated_date: '2026-09-12 18:25'
labels: []
milestone: m-9
dependencies:
  - TASK-536.4
parent_task_id: TASK-536
priority: medium
type: feature
ordinal: 779000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
本アプリには Drag & Drop の実装が現状どこにも無い（`NSDraggingDestination` / `draggingEntered` / `registerForDraggedTypes` / `performDragOperation` / SwiftUI `onDrop` のいずれも製品コードにヒット0件、実測）。前例のない状態からの新規実装になる。

Finder 等からファイル／フォルダをブックマーク管理 UI にドラッグ&ドロップすることで、そのパスをブックマークとして追加できるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Finder からファイルを管理パネルへドラッグ&ドロップするとブックマークに追加される（一覧の空き領域へ落とすとトップレベル、フォルダー行へ落とすとそのフォルダー）
- [x] #2 複数ファイルを同時にドロップした場合、受け入れられるものはすべて追加される
- [x] #3 既にブックマーク済みのパスをドロップしても重複登録されない（弾いた件数にも数えない）
- [x] #4 存在しないパス・対応形式でないファイルがドロップされた場合、クラッシュせずパネル下部の 1 行で件数と理由を伝える（モーダルは出さない）。フォルダーは受け入れる（DocumentOpener がフォルダーを開ける）
- [x] #5 受け入れ規則（存在・形式・重複・落とし先フォルダー）と onChange の発火（1 件でも追加したときだけ）をユニットテストで担保する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BookmarkLibrary に add(_:to:) を足し（add(_:) は to: [] へ委譲）、BookmarkStore.add(_:toFolder:) を 1 回の書き込みで行う
2. BookmarkManagerModel に fileReader（既定 DefaultFileReader。Pruner と同じ形）と addDropped(_ urls: [URL], into folder: [String]) async を足す。判定は純粋関数 dropDecision(urls, library, fileReader) に切り出し、stat は withBlockingWork で MainActor 外へ逃がす。結果は DropOutcome（added / rejected(url, reason)）で、モデルの lastDrop に残す。1 件でも追加したら onChange
3. BookmarkManagerView+Drop.swift: List 全体（ルート）とフォルダー行に .onDrop(of: [.fileURL])。NSItemProvider → URL は loadObject(ofClass: URL.self) を withCheckedContinuation で集める。落とし先の強調は isTargeted。弾いた分はパネル下部に 1 行（件数 + 理由）
4. Localizable: bookmarks.manager.drop.rejected（%lld）/ .missing / .unsupported
5. テスト（BookmarkManagerModelTests、InMemoryFileReader）: 存在する対応ファイル → 追加 / ディレクトリ → 追加 / 存在しない → 弾く / 非対応拡張子 → 弾く / 登録済み → 追加も弾きもしない / フォルダーへ落とすと所属が付く / 追加ゼロなら onChange なし
6. 検証: swift test、swiftformat、swiftlint ベースライン、xcodebuild、l10n-check、実機で Finder からのドロップ

## /review-design（チェックリスト）
- 1 真実の源: 存在は FileReading.fileExists（ドロップ時だけの stat。表示では stat しない約束は保つ）、形式は FileType.isSupported（通常ファイルのみ。ディレクトリは受け入れる）、重複は library.contains
- 2 不変条件: 単一 writer は不変。追加とフォルダー所属は add(_:to:) の 1 操作（2 回書かない）
- 3 消費経路: 追加は集合を変えるので onChange → refreshAllToolbars（CLI 追加・削除と同じ経路）。メニューは表示直前に読み直す
- 4 表示: 弾いた件数と理由の 1 行。全件受け入れなら何も出さない。ドロップ中は強調
- 5/6: ライフサイクル・高頻度経路の変更なし
- 7 測るもの: モデルのテストが InMemoryFileReader でストアの中身・所属・onChange 回数・rejected を直接見る
- 8 非同期: provider の読み出しと stat は await し、着地でストアへ書く。世代管理は不要（結果は集合への追加で、表示の差し替えではない。lastDrop は最後のドロップの結果で上書きしてよい）
- 9 粒度: 同じ AppStores.bookmarkStore。fileReader は共有物ではないので既定値あり（MissingBookmarksPruner と同じ）
- 10 行数: Model 96 → 約 150、View 225（+Drop 拡張 約 70 → 合算約 300）、Library +6。モデルの注入クロージャは 2 のまま
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-09-12）

BookmarkManagerView+Drop.swift（アプリ内で初めての onDrop 実装）: パネル全体（→ トップレベル）とフォルダー行（→ そのフォルダー）が .fileURL を受ける。NSItemProvider → URL は loadObject(ofClass: URL.self) を継続で順に取り出す（NSItemProvider は Sendable でないため task group には渡せない。件数は数個で取り出しは即時）。受け入れ規則は BookmarkManagerModel.dropDecision（純粋関数）: 登録済み（同じドロップ内の重複も）は追加も弾きもしない / 存在しなければ弾く（missing）/ 通常ファイルで対応形式でなければ弾く（unsupported）/ ディレクトリは受け入れる。存在確認はドロップの瞬間だけ withBlockingWork で MainActor 外へ逃がし、表示では stat しない約束を保つ。着地でストアへ add(_:toFolder:)（1 操作。フォルダーが消えていればルート）。弾いた分はモーダルにせずパネル下部の 1 行（件数 + 名前 (理由)）。1 件でも追加したら onChange。

検証（実測）:
- swift test --skip Integration --skip FileWatcherTests: 1930 tests / 313 suites 通過（新規: BookmarkManagerModelTests +2（受け入れ規則・フォルダーへの着地と追加ゼロ時の onChange なし）、BookmarkLibraryTests +1（add(_:to:) のルート fallback）、BookmarkManagerViewDropTests 3（実 NSItemProvider を handleDrop に渡して非同期の着地まで / ファイル URL を含まないドロップは不受理 / 文言）
- swiftlint ベースライン差分: main 48 / HEAD 48、新規 0。swiftformat 0 files。型グループ閾値以内（BookmarkManagerView 311、Model 148、DropOutcome 20）
- xcodebuild build -scheme befold: 成功。l10n-check: 追加 3 キーとも en/ja 揃い（%lld の対応も一致）
- **Finder からの実ドラッグは未自動化**（System Events ではドラッグを起こせず、cliclick も無い）。SwiftUI の .onDrop より内側（provider → URL → モデル → ストア → onChange）は BookmarkManagerViewDropTests で実 provider を通した。残るのは .onDrop の配線だけで、これは標準修飾子
- docs/dev/native-app-design.md: BookmarkManagerModel / View の行に D&D の受け口と受け入れ規則を追記

responsibility-reviewer: must-fix 0、Low 2。Low 2（View+Drop に文言の組み立てが同居）は BookmarkDropOutcome.feedback / Rejection.localizedReason へ移動（移動のみ、テストも値型を直接測る形に）。Low 1（モデルが fileReader を持つ = 表示で stat しない約束がコメント頼み）は見送り: dropDecision は純粋関数で stored property を参照せず、既定引数の形は RecentRepositoriesStore / MissingBookmarksPruner と同形。型を 1 つ増やしてまで構造で縛る価値は今は無いと判断（レビュー側も見送り可寄り）。反映後: swift test 1930 件通過、swiftlint 新規 0、xcodebuild 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Finder からファイル／フォルダーを管理パネルへドロップしてブックマークに追加できるようにした。パネル全体はトップレベル、フォルダー行はそのフォルダーへ入る。受け入れ規則は純粋関数 dropDecision（登録済みは数えない / 存在しなければ弾く / 通常ファイルで対応形式でなければ弾く / ディレクトリは受け入れる）で、存在確認はドロップの瞬間だけ MainActor 外で行う。弾いた分はパネル下部の 1 行で件数と理由を伝え、1 件でも追加したら全窓のツールバーを再同期する。検証: swift test 1930 件通過（実 NSItemProvider を通す経路テストを含む）、swiftlint 差分 0、xcodebuild 成功。Finder からの実ドラッグ自体は自動化できず未確認。
<!-- SECTION:FINAL_SUMMARY:END -->
