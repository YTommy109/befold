---
id: TASK-278
title: previewTarget のキャッシュがファイルシステム状態の変化を取りこぼす（TASK-273 のレビュー指摘）
status: To Do
assignee: []
created_date: '2026-08-04 02:00'
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
- [ ] #1 previewTarget の解決結果が、ファイルシステム状態の変化（シンボリックリンクの解決先変更）で陳腐化しない。キャッシュを保つなら解決入力を純粋な値へ寄せる、キャッシュをやめる、のいずれでもよいが、採用した方針の根拠を実装ノートに残す
- [ ] #2 1 回のフォルダー移動（currentDirectory / entries / selection の連続書き換え）で previewTarget の解決が 1 回に畳まれ、onPresentationTargetChange の発火も重複しない
- [ ] #3 currentDirectory の didSet と他 2 つの didSet でコールバック発火が対称になる。意図的に非対称にする場合は didSet にその理由をコメントで残す
- [ ] #4 previewTarget の再計算回数を検証するユニットテストがある（連続書き換えで解決が 1 回であること）
<!-- AC:END -->
