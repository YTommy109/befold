---
id: TASK-525
title: >-
  TSan 全件実行が NSMenu の dealloc で稀にクラッシュする（NSPointerArray removePointerAtIndex
  範囲外）
status: To Do
assignee: []
created_date: '2026-08-19 02:17'
labels:
  - bug
dependencies: []
priority: medium
ordinal: 767000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`swift test --sanitize=thread` の全件実行 4 回のうち 1 回、テストはすべて pass しながらプロセスが signal 6 で落ちた。

## 事実（実測 2026-08-19、TASK-516 の検証中）

- 手元（macOS 26 / arm64）で TSan 全件実行を 4 回。3 回は `1649 tests in 264 suites passed`、1 回だけ以下で abort。

```text
*** Terminating app due to uncaught exception 'NSInvalidArgumentException',
reason: '*** -[NSConcretePointerArray removePointerAtIndex:]: attempt to remove pointer at index 5 beyond bounds 5'
  3 AppKit -[NSPointerArray removePointersInRange:]
  4 AppKit -[NSPointerArray removePointersPassingTest:]
  5 AppKit -[NSMenu _setMenuName:]
  6 AppKit -[NSMenu dealloc]
  7 AppKit -[NSMenuItem dealloc]
```

- 落ちた時点で失敗テストは 0 件。«unknown» issue も出ていない（TASK-516 で扱った協調スレッド枯渇とは別物）。
- スタックは AppKit 内部のみで、befold のフレームを含まない。メニューを組み立てるテスト（MainMenuBuilder 系）の `NSMenu` / `NSMenuItem` が並行に dealloc されている疑い。

## 未確認

- 再現率 1/4 は TSan 実行のみでの実測。通常実行でも起きるかは未確認。
- TASK-516 の変更（`Task.detached` → `withBlockingWork`）以前から起きていたかは未確認。CI の thread-sanitizer ジョブの過去ログを漁れば分かる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TSan 全件実行を反復し、再現率と、TASK-516 以前から起きていたかを実測する
- [ ] #2 原因がメニュー系テストの NSMenu 寿命管理にあるなら、dealloc が並行しない形へ直す
<!-- AC:END -->
