---
id: TASK-485.19.3
title: モード可用性に基づく表示制御と状態保持を実装する
status: To Do
assignee: []
created_date: '2026-08-21 09:12'
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
- [ ] #1 非対応モードのセグメントが自動的に非表示になる（実機・テストで確認）
- [ ] #2 モード切替をまたいで検索クエリ・トグル・見出しレベル選択が保持される
- [ ] #3 現在のモードが不可になったときの挙動（フォールバック/閉じる）が決まりテストで固定されている
- [ ] #4 非アクティブモードが再描画のたびに無駄な列挙計算をしないことを確認している
<!-- AC:END -->
