---
id: TASK-485.31
title: ジャンプの無い表示で「ジャンプ…」が検索と同じ動作になり、バーには「検索」だけのスイッチが出る
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 09:12'
updated_date: '2026-09-25 12:43'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/ViewerMenuValidator.swift
  - BefoldApp/viewer-src/bar-mode.ts
parent_task_id: TASK-485
priority: low
type: enhancement
ordinal: 832000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-485.26 で見出しジャンプを Markdown だけにし、TASK-485.28 で cmd+shift+F を「使えるジャンプが無ければ検索」にした(2026-09-25 のコードレビューで検出)。この組み合わせで、mmd・JSON・YAML・HTML・SVG・CSV/TSV・定義ジャンプ未対応の言語など多くの表示に次の 2 点が生じる。
- Edit > ジャンプ…(cmd+shift+F)が有効なまま表示され、押すと Edit > 検索…(cmd+F)と同じことをする。項目名からは検索が開くと分からない。`ViewerMenuValidator.validateDocumentJumpItem` は `canFind` を返すため、グレーアウトもしない
- 統合バー上段のモード切替スイッチ(`bar-mode.ts` の `updateSwitchAppearance`)が「検索」1 つだけのセグメントを出す。以前は見出しがどの表示でも使えたので、選択肢は常に 2 つ以上あった。選択肢が 1 つのスイッチは押しても何も変わらない
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ジャンプの無い表示で Edit > ジャンプ… をどう見せるか(無効化 / 検索へ倒すことを項目名で示す / 現状維持)を決め、その根拠を Notes に残す
- [x] #2 選べるモードが検索だけのとき、モード切替スイッチを出すかどうかを決め、出さないなら jest で固定する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Edit > ジャンプ… はユーザー判断で現状維持（有効のまま検索へ倒す）
2. bar-mode.ts の updateSwitchAppearance で、選べるモードが検索だけなら #mmd-bar-modes の行ごと隠す
3. jest で固定（同期前 / 可用性 [] → 隠す、ジャンプが届けば出す）、viewer-bundle 再生成、viewer-ui.md 更新
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
判断 #1（Edit > ジャンプ…）: 現状維持を採用（2026-09-25 ユーザー確認）。理由: TASK-485.28 の AC #2「ジャンプが無い表示で cmd+shift+F を押すと検索が開く」はユーザーが決めた挙動で、無効化はそれを覆す。項目名の動的な書き換えは cmd+F と同名の項目が 2 つ並ぶ。検索だけの表示ではスイッチを出さなくなるので、開いたのが検索だと見て分かる。有効判定は TASK-485.32 で canToggleJump（ジャンプか検索のどちらかができる）へ寄せ済み。
判断 #2（スイッチ）: 出さない。選べるのは『検索 + 1 種』か『検索』だけで、後者の 1 セグメントは押しても何も変わらないため、#mmd-bar-modes の行ごと隠す（上段の gap も消える）。単純化の検討: 状態を足さず、既存の isModeAvailable の結果の件数だけで決める。
検証: jest 666 件合格。修正を戻すと『Swift からまだ同期が届く前は…スイッチの行ごと隠す』『選べるモードが検索だけのときは…』の 2 件が落ちることを実測。oxlint / oxfmt / tsc（viewer・viewer-test）0。swift test 1878+66 件合格。アプリ上の目視確認は未実施。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ジャンプの無い表示での Edit > ジャンプ… は、ユーザー判断により現状維持（有効のまま検索を開く）とした。統合バーのモード切替スイッチは、選べるモードが検索だけのとき行ごと隠すようにし、jest で固定した。修正を戻すと新しい 2 件のテストが落ちることを確認済み。jest・swift test は全件合格、lint もすべて 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
