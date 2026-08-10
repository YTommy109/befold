---
id: TASK-418
title: サイドバーのフィルタで選択行が隠れると矢印キー操作が死ぬ
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 07:28'
updated_date: '2026-08-10 21:44'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 103000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FileListView.selectNext / selectPrevious（FileListView.swift:346 付近）は `guard let current = model.selection, let index = visibleEntries.firstIndex(where: { $0.id == current }) ...` で始まり、フォールバックは model.selection == nil のときしか発火しない。

FileListFilter.apply は presentedPathKey を git フィルタのときだけ残し filterText では残さないため、開いているファイルに一致しないパターンを入力すると選択行が visibleEntries から落ちる。この状態で ↓ / j を押すと firstIndex が nil を返してガードが失敗し、フォールバックにも入らず .ignored を返す。selectPrevious も同じ。マウスで行をクリックするまでキーボードで絞り込み結果へ到達できない。

あわせて visibleEntries の再計算コストも同じ箇所にある。FileListModel.visibleEntries（:269）は listFilter.apply を毎回走らせ（filterText 非空または git フィルタ ON なら 1 件ごとに WildcardMatcher）、entryList が body 1 回につき 2 回（List :161 とオーバーレイ :181）、selectNext が 1 打鍵につき 3 回、selectPrevious が 3 回、enterSelected が 2 回評価する。数千件のディレクトリでフィルタ欄を開いていると矢印キー 1 回でメインアクタ上のフィルタが 5 回以上走る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フィルタで選択行が隠れている状態でも ↓ / ↑ / j / k で絞り込み結果の先頭（または末尾）へ移動できる
- [x] #2 フィルタをクリアしたときの選択位置が破綻しない
- [x] #3 1 回のキー操作あたり visibleEntries の評価が 1 回になる
- [x] #4 キーボード操作のユニットテストを追加する（選択が visibleEntries 外のケースを含む）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計レビュー（/review-design）を反映した方針。

1. FileListModel に絞り込み結果のスナップショット型 FileListSnapshot（visible: [FileListEntry] / matchedIDs: Set<ID>）を導入する。listFilter.apply を 1 回だけ走らせ、そこから祖先足し戻し・開閉三角の確定・一致行集合を同時に得る。visibleEntries と firstSelectableEntryURL はこのスナップショットからの導出に一本化する（現状 firstSelectableEntryURL は visibleEntries と filteredEntries を別々に評価しており、apply が 2 回走る）。
2. FileListView+Keyboard.handleKey でスナップショットを 1 回だけ取り、selectedTarget / selectNext / selectPrevious / navigateToParent / performOnSelectedEntry へ引数で渡す。状態は増やさない。
3. 移動計算は純粋関数 SidebarSelectionMove（新規ファイル）へ切り出す。選択が visible に無い場合のフォールバックを next=先頭 / previous=末尾 とし、その「先頭」は TASK-406 の規則（.parentNavigation を飛ばし、祖先として足し戻されただけの行より一致行を優先）と同じ関数を使う。答えを 2 つ作らない。
4. entryList では List とオーバーレイが同じ配列を 2 回評価しているため、body でもスナップショットを 1 回取って両方へ渡す。
5. AC#3 の担保: #if DEBUG 限定の @ObservationIgnored 評価カウンタをスナップショット生成に置き、キー操作 1 回でカウンタが 1 しか増えないことをテストする（設計を破ると落ちる形）。

未確認だった前提と結論:
- 「キー操作 1 回 = visibleEntries 1 回」は、選択が実際に動く場合には成立しない。selection の didSet が scrollSelectionIntoView → selectedRow() を次のランループで呼ぶため（FileListModel.swift:255-267）。この評価は非同期で、その時点の一覧を読み直すのが正しい（一覧差し替えと選択書き込みの順序が逆転する経路があるとコメントに明記されている）。よって AC#3 はキーハンドラの同期区間を対象とし、スクロール追従ぶんは対象外とする。テストもその区間で測る。
- 不変条件「visibleEntries の添字 = NSTableView の行番号」（SidebarRowBuilder.swift:9-10）はモデル側の導出を変えないため影響しない。
- 絞り込みが 0 件（.. のみ）のときはフォールバックも行を見つけられず .ignored。既存の emptyStateView がそのまま出るので新しい表示は不要。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-11）

/review-design を 1 回実施し、当初案（handleKey でスナップショットを取って引数で渡す）に次の 3 点を足した。

1. 「絞り込み結果の先頭」の答えを 2 つ作らない。隠れた選択からの ↓ の行き先は、TASK-406 で決めた規則（.parentNavigation を飛ばし、祖先として足し戻されただけの行より一致行を優先）と同じ関数を使う。FileListSnapshot.firstSelectable / lastSelectable に集約し、FileListModel.firstSelectableEntryURL もそこへ寄せた。
2. filteredEntries と visibleEntries を別々に評価していた firstSelectableEntryURL を畳んだ。旧実装は 1 回の呼び出しで FileListFilter.apply を 2 回走らせていた（FileListModel.swift:322-327 の旧コード）。
3. body 側も List とオーバーレイが同じ配列を 2 回評価していたため、entryList(showing:) へ 1 回だけ渡す形にした。

構造:
- FileListSnapshot（新規）: visible / filtered / matchedIDs と、next(after:) / previous(before:) / entry(for:) / firstSelectable / lastSelectable。選択が visible に無い場合と選択が nil の場合を同じ扱いにするのがバグの本体。
- FileListModel+Snapshot.swift（新規）: listSnapshot がこの一覧の唯一の作り方。FileListModel.swift が 400 行を超えたため extension へ分割（swiftlint file_length）。
- selectNext / selectPrevious はスナップショットを必須引数で受ける（デフォルト引数を置かない）。

AC#3 の範囲について: 「キー操作 1 回 = 評価 1 回」は選択が実際に動く場合には成立しない。selection の didSet が scrollSelectionIntoView → selectedRow() を次のランループで呼ぶため（FileListModel.swift:255-267）。この評価は非同期で、その時点の一覧を読み直すのが正しい（一覧差し替えと選択書き込みの順序が逆転する経路があるとコメントに明記）。よって AC#3 はキーハンドラの同期区間を対象とし、#if DEBUG 限定の評価カウンタ（FileListModel.snapshotEvaluationCount）で測る。破れたら keyPressEvaluatesSnapshotOnce が落ちる。

検証（実測）:
- swift test: 1400 tests / 204 suites すべて成功（新規 6 件を含む）
- swiftformat --lint: 0 files require formatting
- swiftlint（変更 7 ファイル）: 指摘 0 件（分割前は file_length と identifier_name が各 1 件出ていたので、それを潰した結果）
- xcodegen generate 実施済み（新規 3 ファイル）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
選択行が絞り込みで隠れている場合を「選択なし」と同じ扱いにし、↓ で絞り込み結果の先頭・↑ で末尾へ移れるようにした。あわせて絞り込み結果を FileListSnapshot に畳み、キー操作 1 回・body 1 回あたりの FileListFilter.apply を 1 回にした。swift test 1400 件成功、swiftformat/swiftlint 指摘 0 件で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
