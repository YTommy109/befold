---
id: TASK-278
title: previewTarget のキャッシュがファイルシステム状態の変化を取りこぼす（TASK-273 のレビュー指摘）
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 02:00'
updated_date: '2026-08-04 02:23'
labels:
  - review-finding
dependencies: []
priority: high
type: bug
ordinal: 320000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-273 で previewTarget を computed property から didSet 駆動のキャッシュへ変えたが、PreviewTargetResolver.resolve は 3 つの stored property（currentDirectory / entries / storedSelection）だけの純粋関数ではない。matchingEntry のフォールバックが selection.normalizedPathKey（resolvingSymlinksInPath = ライブな syscall）を呼ぶため、3 つのどれも書き換わらないままファイルシステム側が変わるとキャッシュが陳腐化する。

再現の筋道: シンボリックリンク経由のパス（entries は /private/tmp/... を持ち、選択は /tmp/...）で文書を開くと previewTarget=.file が pathKey フォールバック経由で解決されキャッシュされる。その後、監視対象 currentDirectory の外にあるリンク先が変わっても entries の再読み込みが起きないため、メニュー検証とツールバーは古い .file を読み続け、文書専用コマンド（ソース表示・行番号・ブックマーク）が有効なまま提示対象でない文書に作用する。キャッシュ化前は毎回の検証で再解決していた。

同じキャッシュ機構に付随するクリーンアップ 2 件も本タスクに含める。

1. 早期再計算の重複: updatePreviewTarget() は書き換えたプロパティごとに O(entries) の線形走査を走らせる。SidebarNavigator.swift:287-296 は 1 回のフォルダー移動で currentDirectory → entries → selection の順に 3 つとも書き換えるため、走査が最大 3 回・onPresentationTargetChange が 2 回発火する。TASK-273 自身の実測（30,000 件で 1 回あたり約 5.6 ms）だと移動ごとに約 11〜17 ms を @MainActor 上で無駄にしている。dirty フラグ + 初回読み出し時の遅延再計算、または一括更新の入口を 1 つにすれば、読み出しの O(1) を保ったまま連続書き込みを 1 回の解決へ畳める。
2. コールバックの非対称: currentDirectory の didSet は updatePreviewTarget() を呼ぶが onPresentationTargetChange を呼ばない。entries / storedSelection の didSet は両方呼ぶ。コールバックの doc コメントは「提示対象(previewTarget)が変わりうる書き換えのあとに呼ばれる」と書いてあり矛盾している。現状は全ての currentDirectory 書き込み地点（SidebarNavigator.swift:287, :370 / ViewerWindowController.swift:376）の直後に entries 代入が続くため隠れているだけ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 previewTarget の解決結果が、ファイルシステム状態の変化（シンボリックリンクの解決先変更）で陳腐化しない。採用した方針の根拠を実装ノートに残す
- [x] #2 1 回のフォルダー移動（currentDirectory / entries / selection の連続書き換え）で entries の線形走査が 1 回に収まり、onPresentationTargetChange の発火が提示対象の変化した回数だけになる
- [x] #3 currentDirectory の didSet と他 2 つの didSet でコールバック発火が対称になる。意図的に非対称にする場合は didSet にその理由をコメントで残す
- [x] #4 連続書き換えでのコールバック発火回数と、各時点の previewTarget の正しさを検証するユニットテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileListEntry の索引型を作る: entries から id→entry / pathKey→entry（先勝ち）の 2 辞書を作る値型を追加し、FileListModel.entries の didSet で 1 回だけ構築する。線形走査はここに集約する。
2. 選択側の pathKey をスナップショットする: selection の setter で normalizedPathKey を storedSelectionPathKey に保存する（FileListEntry.pathKey が構築時スナップショットなのと対称にする）。これで解決経路から syscall が消える。
3. PreviewTargetResolver.resolve を索引と選択 pathKey を受け取る O(1) の純粋関数にする。振る舞い（id 一致優先→pathKey フォールバック、hasLoadedEntries の意味）は変えない。
4. FileListModel.previewTarget をキャッシュ（stored）から computed へ戻す。updatePreviewTarget()・init の初期化行を削除する。キャッシュが無くなるので陳腐化しない。
5. onPresentationTargetChange を「値が実際に変わったときだけ」発火するエッジトリガにする（O(1) になったので毎回の比較が安い）。3 つの didSet すべてから同じ通知経路を通し、非対称を解消する。
6. テスト: PreviewTargetResolverTests を新シグネチャへ更新（シンボリックリンク別表記のケースを含む）。FileListModel に対して、フォルダー移動相当の連続書き換えでコールバックが対象変化の回数だけ発火すること、各時点の previewTarget が正しいことを検証するテストを追加する。
7. swiftformat/swiftlint のベースライン差分ゼロ確認、swift test。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 採用した方針: キャッシュを持たず、導出を O(1) にする

陳腐化の根はキャッシュそのものではなく「導出がライブな syscall を読む」ことだった。一覧側の
FileListEntry.pathKey は構築時のスナップショットなのに、選択側だけ導出のたびに
resolvingSymlinksInPath を呼んでおり、同じ入力から違う答えが出る余地があった。そこで

1. 選択の正規化キーも書き込み時にスナップショットする（storedSelectionPathKey）。これで
   PreviewTargetResolver.resolve は引数だけから決まる純関数になり、ディスクを読まなくなった。
2. entries の代入時に FileListEntryIndex（id→entry / pathKey→entry、pathKey は先勝ちで
   従来の entries.first {} と同じ行を返す）を 1 回だけ作る。導出は索引引き 2 回で O(1)。
3. 導出が O(1) になったので previewTarget を computed へ戻し、キャッシュ（stored）を捨てた。
   保持していないものは古くならない。updatePreviewTarget() と init の初期化行も消えた。
4. onPresentationTargetChange は 3 つの didSet すべてから同じ経路（notifyPresentationTargetChangeIfNeeded）
   を通し、対象が実際に変わったときだけ発火するエッジトリガにした。比較のための導出も O(1)。

線形走査は「一覧の代入 1 回につき索引構築 1 回」に集約された。フォルダー移動で 3 回走っていた
O(entries) の走査は 1 回になり、通知も 2 回から 1 回（対象が変わった回数）になった。

## 途中で見つけて直した回帰

previewTarget を computed にすると、View がそれを読んだときに依存として登録されるのは導出が
触れた保存値だけになる。索引を @ObservationIgnored にしていたため、選択も currentDirectory も
動かないまま一覧だけが変わったケース（監視による再列挙で選択中の行が消える等）で SwiftUI が
再描画されない状態になっていた。索引を観測対象に戻し、withObservationTracking で検証する
テストを追加した。@ObservationIgnored を戻すとこのテストだけが落ちることを実測で確認済み。

## 検証

- swift test: 967 tests / 137 suites すべて成功
- xcodebuild build -scheme befold: BUILD SUCCEEDED（新規ファイル追加のため xcodegen generate 実施済み）
- swiftlint: 本タスクで触れた 3 ファイルの警告 0 件（全体 77 件は main のベースライン内）
- swiftformat --lint: 差分なし
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
previewTarget のキャッシュを捨て、導出を O(1) の純関数に変えた。選択の正規化キーを書き込み時にスナップショットして解決経路から syscall を除き（一覧側の pathKey と同じ扱いに揃えた）、entries の代入時に作る索引（FileListEntryIndex）で行を引くようにした。導出が O(1) になったので previewTarget は computed へ戻し、保持をやめたことで陳腐化そのものが起きなくなった。通知は 3 つの didSet 共通の経路を通し、対象が実際に変わったときだけ発火する。副産物として、フォルダー移動あたりの線形走査は 3 回から 1 回、通知は 2 回から 1 回になった。作業中、computed 化により一覧だけが変わったときの SwiftUI 再描画が落ちる回帰を作り込んでいたのを発見し、索引を観測対象に戻して withObservationTracking のテストで裏打ちした（修正を戻すとそのテストだけが落ちることを実測）。検証: swift test 967 件成功、xcodebuild BUILD SUCCEEDED、swiftlint 該当ファイル 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
