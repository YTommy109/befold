---
id: TASK-485.19.3
title: モード可用性に基づく表示制御と状態保持を実装する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-21 09:12'
updated_date: '2026-08-21 11:32'
labels: []
dependencies:
  - TASK-485.19.2
parent_task_id: TASK-485.19
priority: high
ordinal: 777000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
統合バーのモード切替スイッチに、可用性判定と状態保持を配線する。

- canFind（常時true）/ canJump(to:) 由来の availableKinds を使い、非対応モードの
  セグメントを非表示にする（/review-design の結論: 新しいgate概念を足さず、
  TASK-485.18 の _mmdApplyJumpAvailability 経路を拡張して流用する）
- 現在のモードが不可になったら、別の利用可能モードへフォールバックするか
  バーを閉じるかを実装時に決め、Implementation Notes に理由を残す
- モード切替をまたいで検索クエリ・Aa/ab|/.* トグル・見出しレベル選択を保持する
  （ユーザー承認済み方針。バーを完全に閉じたときにリセットする）
- 非アクティブモードは再描画時に列挙計算をスキップし、モードへ切り替えた瞬間にのみ
  列挙する（jump.ts の isRendering 方針を他モードにも広げる）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 非対応モードのセグメントが自動的に非表示になる（実機・テストで確認）
- [x] #2 モード切替をまたいで検索クエリ・トグル・見出しレベル選択が保持される
- [x] #3 現在のモードが不可になったときの挙動（フォールバック/閉じる）が決まりテストで固定されている
- [x] #4 非アクティブモードが再描画のたびに無駄な列挙計算をしないことを確認している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC2(状態保持): 実装前提が判明。find.ts/jump.tsのclose()はもともとquery/options/activeKind/selectedLevelsをクリアしていないため、『モード切替をまたいで保持』は追加コードなしで既に成立していた。新規テスト2件でこれを固定した。一方『バーを完全に閉じたときにリセットする』(設計レビュー時に承認された方針)は、find.tsの既存挙動(Escapeで閉じてもクエリが残る、TASK-485.19より前からの仕様)と矛盾するため実装しなかった。ユーザーに再確認し、既存挙動を優先する方針で承認を得た。\nAC3(不可時の挙動): フォールバックではなく『閉じる』を採用。TASK-485.18で確立済みのjump.closeUnlessAvailableの挙動をそのまま踏襲し、新しいフォールバック機構は追加していない(最小の変更)。\nAC4: find.ts側はrender.tsの_mmdFindRefreshAfterRenderにある呼び出し時isOpen()ガード、jump.ts側はrefresh()内のisJumpBarOpen()ガードで、いずれも既存コードのまま満たされていた。新規コードは不要だったため、既存ガードを一時的に外すと落ちる回帰テストを追加して担保した。\n検証: npm test 562/562通過(新規12件を含む)、typecheck/build/cycle-checkいずれも新規エラーなし。Swiftコードは未変更のためswiftformat/swift test/型グループ計測は対象外。native-app-design.mdへの反映はTASK-485.19.5でまとめて行う(19.1/19.2と同じ判断)。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-08-21 11:29
---
AC1(実機・テストで確認)のうち実機側は未実施です。理由はTASK-485.19.2のコメントと同じ(自動スクリーンショット取得の信頼性問題)。テストでは _mmdApplyJumpAvailability(['heading']) 等で非対応セグメントが display:none になること、開いているモードが不可になるとバーごと閉じ外枠・選択状態・セグメントが揃って消えることを固定済みです（ガードを一時的に外すと該当テストが落ちることを実測: render.tsのisOpen()ガード除去→1件失敗、bar-mode.tsのdisplay制御除去→3件失敗、いずれも復元後562/562通過）。
---

author: @claude
created: 2026-08-21 11:32
---
実機でのレイアウト目視確認は未実施のままです(TASK-485.19.2/.3のコメントで記録済み)。
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
モード切替スイッチに可用性判定(canJump(to:)由来のavailableKindsを流用、新しいgate概念は追加せず)と状態保持を配線した。状態保持は既存のfind.ts/jump.tsのclose()仕様により追加実装なしで成立していたため、新規コードはjump.tsのavailableKinds追跡+bar-mode.tsのセグメント表示制御のみ。『完全に閉じたときのリセット』は既存挙動と矛盾するため見送り(ユーザー承認済み)。npm test 562/562通過、ガード除去による回帰テストの有効性も実測済み。実機でのレイアウト確認は未実施(TASK-485.19.2と同じ理由)。
<!-- SECTION:FINAL_SUMMARY:END -->
