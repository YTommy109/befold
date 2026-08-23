---
id: TASK-485.19.4
title: Enter/Shift+Enterの受け口統一とIME結線を整理する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-21 09:12'
updated_date: '2026-08-21 11:32'
labels: []
dependencies:
  - TASK-485.19.2
parent_task_id: TASK-485.19
priority: medium
ordinal: 778000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
find は入力欄への keydown、jump は document の keydown（keyboard.ts の
resolveJumpNavigationKey）という構造的に非対称な Enter/Shift+Enter の受け口を、
統合バーの構造に合わせて整理する。

対象:
- find.ts:452-467（入力欄 keydown）
- keyboard.ts:103-114 resolveJumpNavigationKey（document keydown）
- keyboard.ts の ownsEnterKey（リンク上のEnterを奪わない除外ロジック）
- ime.ts の isComposingKeyEvent は検索モードの入力欄に直結させたまま、
  非入力モード（見出し/変更箇所）向けの経路を document keydown に残すか、
  フォーカス設計を変えて入力欄方式に寄せるかを実装時に確定する
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 検索/見出し/変更箇所いずれのモードでもEnter/Shift+Enterで前後移動できる
- [x] #2 IME変換確定のEnterではどのモードでも移動しない（既存テストの型を踏襲）
- [x] #3 フォーカスがリンク上にあるときEnterを奪わない既存の挙動を壊していない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査の結果、本タスクが想定していた『受け口の再構築』は不要と判明した。resolveJumpNavigationKey(keyboard.ts:103-114)・ownsEnterKey・isComposingKeyEvent はいずれも活動中の種類(activeKind: heading/changeBlock)ではなく currentBar()(find/jumpの2値)だけで分岐しており、jump コントローラが持つ「見出し」「変更箇所」の違いを一切見ない。bar-mode.ts のモード切替は既存の _mmdOpenFind/_mmdOpenJump をそのまま呼ぶだけなので、この共有経路にも新しい分岐は増えていない。\nAC1: 見出しモードのEnterキー確認は既存テストにあったが、変更箇所モードでの実際のキー入力(document keydown経由)を確認するテストは無かったため1件追加(viewer-main-jump.test.js「Enterで次の変更箇所へ、Shift+Enterで前の変更箇所へ動く」)。検索モードは既存のfind側テスト群でカバー済み。\nAC2/AC3: IME判定・リンクフォーカス時の除外はkindに依存しない共有ロジックであることをコード確認した上で、既存の見出しモード向けテスト(IME変換確定Enter、リンク/ボタン/入力欄フォーカス時の除外)＋今回追加した変更箇所モードのEnterテストで、共有経路が変更箇所でも通ることを示した。個別に3モード×各edgeケースを重複して書くのではなく、分岐が無いことをコードで示す形にした(冗長なテストを避ける単純化)。\n検証: npm test 563/563通過(新規1件を含む)。production コードの変更は無し(find.ts/keyboard.ts/ime.tsいずれも無変更)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
調査の結果、Enter/Shift+Enterの受け口統一・IME結線整理は追加実装不要と判明した(既存のresolveJumpNavigationKey等がactiveKindではなくopenBarだけで分岐しており、3モードとも既に同じ経路を通っていたため)。変更箇所モードでの実際のキー入力を確認するテストが無かった穴だけを1件埋めた。npm test 563/563通過。プロダクションコードの変更なし。
<!-- SECTION:FINAL_SUMMARY:END -->
