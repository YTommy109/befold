---
id: TASK-140.3
title: Find/zoom の共有グローバル状態をカプセル化し順序依存を明示する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:42'
updated_date: '2026-07-25 03:03'
labels:
  - refactor
  - structural
  - js
dependencies:
  - TASK-140.1
parent_task_id: TASK-140
priority: medium
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
find 状態が 6 つの裸のモジュールグローバル(_mmdFindOptions/_mmdFindQuery/_mmdFindMatches/_mmdFindCurrentIndex/_mmdFindIsOpenFlag/_mmdIsTruncated)に散り、_mmdFindRun/_mmdFindRefresh/_mmdFindNext/Prev/_mmdFindUpdateCount/_mmdSetTruncated/appendChunk が横断的に読み書きする。_mmdModeJustSwitched や _lastChunkEndedWithNewline が render→appendChunk/setViewMode→refresh を跨ぐ順序依存を持つ。find 状態+操作を FindController 相当(クロージャ/クラス)へ閉じ込め、render/zoom 状態も小さなレコードに集約し、next/prev の循環・refresh の位置維持ロジックを単体テスト可能にする。TASK-140.1 のエクスポート境界導入が前提。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 find 状態+操作が単一のコントローラ相当に閉じ込められ、裸のモジュールグローバルが解消している
- [x] #2 next/prev の循環ナビゲーションと refresh の現在位置維持ロジックが単体テストされている
- [x] #3 順序依存(モード切替直後の refresh・チャンク末尾改行の持ち越し)が明示的な受け渡しになり、find/切替/追記読み込みに回帰がない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
0. 単純化検討: (a) find の 6 グローバルを単なるレコード(_findState オブジェクト)に束ねるだけの案 → 名前空間は片付くが、外部から状態を直接書き換えられる点は変わらず「カプセル化」にならないため不採用。(b) 採用: クロージャで状態を閉じた _createFindController() を作り、状態は外から触れなくする。Swift から evaluateJavaScript で呼ばれる名前(_mmdOpenFind/_mmdCloseFind/_mmdFindRefresh/_mmdFindNextIfOpen/_mmdFindPrevIfOpen/_mmdInitFind)と、ViewerBridgeTests が署名を文字列一致で検査している関数はトップレベルの薄い委譲として残す。内部呼び出し(next/prev/run/toggle)は委譲を作らず _mmdFind.xxx() を直接呼ぶことでラッパーの増殖を避ける。

1. viewer.js に純粋なインデックス演算を追加(AC#2 の単体テスト到達点):
   - nextMatchIndex(currentIndex, count)  : 循環して次へ
   - prevMatchIndex(currentIndex, count)  : 循環して前へ
   - keptMatchIndex(previousIndex, count) : refresh 時の現在位置維持(範囲クランプ)
   いずれも count<=0 を -1 とする全域関数にし、module.exports へ追加する。
2. viewer-main.js に _createFindController() を追加し、options/query/matches/currentIndex/isOpen/isTruncated をクロージャへ閉じる。clearMarks/walk/walkText/updateCount/highlightCurrent/run/refresh/next/prev/toggleOption/open/close/setTruncated/applyHostSettings/initControls を内部関数にし、_mmdFindSkipTags もコントローラ内へ移す。裸のモジュールグローバル 6 本を削除する。
3. 順序依存を明示的な受け渡しにする:
   - _mmdModeSwitch(mark/consume): setViewMode が mark()、render/_renderSource 後の _mmdFindRefreshAfterRender が consume() で 1 度だけ取り出す(find が閉じていてもフラグを消費する現行挙動を維持)。
   - _mmdChunkTail(record/endedWithNewline): render(初回)と appendChunk(追記)が record()、次の appendChunk が endedWithNewline() で読む一方向の受け渡しに限定する。
4. _mmdSetTruncated はバナー DOM の責務を持つのでトップレベルに残し、検索側の状態更新は _mmdFind.setTruncated() へ委譲する(Swift 署名 _mmdSetTruncated(isTruncated, lineCount, failed) は維持)。
5. テスト: viewer.test.js に 1 の純粋関数(循環・クランプ・count=0)を追加。viewer-main.test.js に next/prev の循環、refresh の位置維持/先頭リセット、モード切替フラグの 1 回消費、チャンク末尾改行の持ち越しを追加する。
6. 検証: npx jest / swift test(ViewerBridgeTests の署名ドリフト検知) / swift scripts/webview-smoke.swift / 実アプリで find・モード切替・段階読み込みの手動確認。

補足: タスク説明にある「render/zoom 状態も小さなレコードに集約」は AC に含まれないため本サブタスクでは行わない(AC#1 は find 状態のみを対象としている)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装:
- viewer.js に純粋なインデックス演算 nextMatchIndex / prevMatchIndex / keptMatchIndex を追加(count<=0 は -1 を返す全域関数)。
- viewer-main.js に _createFindController() を追加し、options/query/matches/currentIndex/isOpenFlag/truncated をクロージャへ閉じた。裸のモジュールグローバル 6 本(_mmdFindOptions/_mmdFindQuery/_mmdFindMatches/_mmdFindCurrentIndex/_mmdFindIsOpenFlag/_mmdIsTruncated)と _mmdFindSkipTags は消滅し、モジュールレベルに残るのは _mmdFind インスタンス 1 個のみ。
- next/prev/refresh は共通の moveTo(index) に集約し、インデックス計算は viewer.js の純粋関数へ委譲。
- Swift(evaluateJavaScript)から名前で呼ばれる _mmdInitFind / _mmdOpenFind / _mmdCloseFind / _mmdFindRefresh / _mmdFindNextIfOpen / _mmdFindPrevIfOpen はトップレベルの薄い委譲として残した(ViewerBridgeTests が署名を文字列一致で検査しているため)。内部呼び出しは _mmdFind.xxx() を直接使い、委譲の増殖を避けた。
- _mmdSetTruncated はバナー DOM の責務としてトップレベルに残し、検索側の状態更新のみ _mmdFind.setTruncated() へ委譲。

順序依存の明示化:
- _mmdModeSwitch(mark/consume): setViewMode が mark()、_mmdFindRefreshAfterRender が consume() で 1 度だけ取り出す。検索バーの開閉に関わらず必ず消費する現行挙動を維持し、その理由をコメントに明記した。
- _mmdChunkTail(record/endedWithNewline): render(初回チャンク)と appendChunk(追記)が record()、次の appendChunk のみが endedWithNewline() で読む一方向の受け渡しに限定した。

AC#1 の客観確認: viewer-main.js のモジュールレベルに残る find 関連の var は _mmdFind のみ(grep で確認)。状態 6 本はすべて _createFindController() 内のローカル。

検証:
- npx jest: 266 passed(viewer.test.js に純粋インデックス演算 11 件、viewer-main.test.js に検索ナビゲーション/refresh 位置維持/段階読み込み件数表示/モード切替持ち越し/チャンク末尾改行の持ち越し 17 件を追加)
- swift test: 615 tests / 86 suites passed(ViewerBridgeTests の署名ドリフト検知を含む)
- swift scripts/webview-smoke.swift: PASS

AC#3 の手動確認を実施(ユーザーによる目視、2026-07-25)。
- 検索: ⌘F でのヒット表示・件数、⌘G/⌘⇧G の前後移動(末尾↔先頭の循環)、Esc での終了。
- モード切替: 検索中の表示モード切替で先頭リセット、切替なしの再描画では位置維持。
- 追記読み込み: 3000 行の .log(コード経路)と .csv(テーブル経路)に NEEDLE を 500/1500/2500 行目へ配置した検証用ファイルで、初回 1/1(表示範囲内) → 続きを読み込むたびに 2/2 → 3/3 と増え、追記分が検索対象に入りつつ現在位置が先頭へ飛ばないこと、全チャンク読了でバナーと「表示範囲内」表記が消えることを確認。
いずれも回帰なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
find の状態(トグル/クエリ/ヒット一覧/現在位置/開閉/段階読み込み中)を _createFindController() のクロージャへ閉じ、裸のモジュールグローバル 6 本を解消した(モジュールレベルに残るのは _mmdFind インスタンス 1 個のみ)。next/prev/refresh のインデックス計算は viewer.js の純粋関数 nextMatchIndex/prevMatchIndex/keptMatchIndex へ切り出して単体テスト可能にし、共通の moveTo() へ集約した。順序依存は _mmdModeSwitch(mark/consume)と _mmdChunkTail(record/endedWithNewline)という一方向の受け渡しに限定して明示化した。Swift から名前で呼ばれる入口は薄い委譲として残し、ViewerBridge との署名契約を維持している。検証: npx jest 266 passed(純粋インデックス演算 11 件・検索ナビゲーション/refresh 位置維持/モード切替持ち越し/チャンク末尾改行の持ち越し 17 件を新規追加)/ swift test 615 passed / webview-smoke PASS / 実アプリで検索・モード切替・段階読み込み(3000 行の .log と .csv)を目視確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
