---
id: TASK-658
title: パネル窓の位置テストが窓の実寸を完全一致で比べており、CI の画面構成で落ちうる（TASK-656 のレビュー指摘）
status: To Do
assignee: []
created_date: '2026-09-28 06:30'
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
- [ ] #1 位置テストが窓の実寸の完全一致に依存せず、守りたい保証（中央に戻っていない、保存値が使われた等）を画面構成に左右されない形で確かめている
- [ ] #2 位置テストが作った窓をすべて閉じる
- [ ] #3 位置テストが途中で落ちても、利用者の設定領域に保存値が残らない（分離した保存先を使う、または残らないことを説明できる）
<!-- AC:END -->
