---
id: TASK-658
title: パネル窓の位置テストが窓の実寸を完全一致で比べており、CI の画面構成で落ちうる（TASK-656 のレビュー指摘）
status: Done
assignee:
  - '@claude'
created_date: '2026-09-28 06:30'
updated_date: '2026-09-28 07:10'
labels:
  - test
dependencies:
  - TASK-657
priority: medium
type: chore
ordinal: 858000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-656 の実装後レビュー（/code-review high）の指摘。`HostedPanelWindowControllerTests` の位置テストの書き方の問題をまとめたもの。

## 指摘
1. `frame == moved` / `frame == centered` のように、`setFrameUsingName` や `center()` を経た窓の枠を完全一致で比べている。AppKit は保存値を保存時と現在の画面に合わせて補正するため、手元で通っても GitHub Actions の仮想ディスプレイで落ちうる。.claude/CLAUDE.md のテスト規約「環境に依存する実測値をアサートしない」に反し、TASK-593.5 と同じ型。レビューの実測では、別の画面で保存した (40, 60) が (60, 57) に戻った。
2. `rememberPositionRestoresOnlyTopLeft` がサイズの基準用に作った窓を閉じていない。
3. 位置テストが frame autosave の値を `UserDefaults.standard` に書く。defer で消すが、テストが途中で落ちると `NSWindow Frame HostedPanelWindowControllerTests-<UUID>` が残る。テストホストがアプリ（com.degino.befold）のとき、インストール版と同じ設定領域に残る。

TASK-657 で位置だけ戻す分岐が消えると、該当テストも書き直しになるため、そちらを先に片付ける。

## 未確認
指摘 1 は CI で実際に落ちたわけではない（TASK-656 の時点では手元でのみ実行）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 位置テストが窓の実寸の完全一致に依存せず、守りたい保証（中央に戻っていない、保存値が使われた等）を画面構成に左右されない形で確かめている
- [x] #2 位置テストが作った窓をすべて閉じる
- [x] #3 位置テストが途中で落ちても、利用者の設定領域に保存値が残らない（分離した保存先を使う、または残らないことを説明できる）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 移動先はリテラル座標ではなく window.screen.visibleFrame から作る（可視領域の内側なら setFrameUsingName は補正しない）
2. 期待値はリテラルで書かず、同じ実行中に AppKit が実際に採った枠（移動直後の frame・表示直後の中央の frame）を使う。移動先が中央と区別できることを #require で前提として確かめる
3. 初回中央の確認は別の窓との比較をやめ、center() をやり直しても枠が変わらないこと（冪等性）で見る
4. 全テストで作った窓を閉じる
5. 保存名の払い出し時に、同じ接頭辞の古い frame autosave 値を掃除する（Xcode のテストホストは befold.app で、インストール版と同じ領域に書かれるため）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: HostedPanelWindowControllerTests 13 件を 5 回連続で成功。swift test 全件 2019 + 72 件成功。
ミューテーション確認: (M1) showAndActivate を毎回 center() にすると記憶系 3 件が落ちる。(M2) centered でも初回以降は中央へ戻さないようにすると centered のテストが落ちる。(M3) 古い値の掃除を止めると掃除のテストが落ちる。
AC3 の根拠: project.yml の befoldTests は TEST_HOST が befold.app なので、Xcode 経由のテストでは frame autosave がインストール版と同じ com.degino.befold の領域に書かれる（CI の swift test では xctest 側の領域）。defer での削除に加え、保存名の払い出しのたびに同じ接頭辞の古い値を掃除するので、落ちた回の値は次の回で消える。テストはすべて @MainActor の同期テストで互いに割り込まないため、実行中の他テストの値は消さない。
未確認: CI（GitHub Actions の macOS ランナー）ではまだ回していない。可視領域から作った位置なら補正されない、という前提は手元の画面構成でしか確かめていない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
位置テストの期待値をリテラルから、同じ実行中に AppKit が採った枠へ変えた。移動先は可視領域から作り、中央と区別できることを前提として確かめる。初回中央は center() の冪等性で確かめる。途中で落ちた回の保存値は次の回に掃除する。ミューテーション 3 種で各テストが落ちることを確認した。CI での実行は未確認。
<!-- SECTION:FINAL_SUMMARY:END -->
