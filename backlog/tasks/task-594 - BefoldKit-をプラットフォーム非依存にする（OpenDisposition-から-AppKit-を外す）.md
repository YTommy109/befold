---
id: TASK-594
title: BefoldKit をプラットフォーム非依存にする（OpenDisposition から AppKit を外す）
status: To Do
assignee: []
created_date: '2026-09-07 14:59'
labels: []
dependencies: []
ordinal: 865000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldKit はコアロジック層だが、47 ファイル中 1 ファイルだけが AppKit に依存している（OpenDisposition.swift の `init(modifiers: NSEvent.ModifierFlags)`）。判定規則そのものは同ファイルの `init(commandKey:shiftKey:)` に閉じており、NSEvent 版はその薄いラッパーでしかない。

依存が 1 箇所しか残っていないため、いま外せば BefoldKit は Foundation のみで成立する層になる。これは将来の Windows 版検討（AppKit / SwiftUI / WebKit が存在しないため UI 層は書き直しになる一方、コア層は再利用したい）で最も再利用価値が高い部分だが、Windows 版を作るかどうかとは独立に、層の責務としても素直になる。逆に AppKit 依存を放置したまま BefoldKit へ機能を足し続けると、依存が 1 から増えて外せなくなる。

NSEvent 版の呼び出し元は AppKit を既に import している呼び出し側（リンククリックの修飾キー解釈）なので、変換をそちら側へ寄せれば済む想定。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 BefoldKit 配下のどの Swift ファイルも AppKit / Cocoa / WebKit / SwiftUI を import していない（`grep -rl 'import AppKit\|import Cocoa\|import WebKit\|import SwiftUI' --include='*.swift' BefoldApp/BefoldKit` が 0 件）
- [ ] #2 修飾キーから OpenDisposition を決める規則が 1 箇所に閉じたままで、既存の OpenDispositionTests が変更なしに通る
- [ ] #3 NSEvent からの変換を行う新しい入口が、AppKit を既に使っている層（befold / BefoldRenderKit のいずれか）に置かれている
- [ ] #4 この依存が再び入ったら落ちる担保がある（テストか、BefoldKit へ AppKit が入らないことを検査する仕組み）
<!-- AC:END -->
