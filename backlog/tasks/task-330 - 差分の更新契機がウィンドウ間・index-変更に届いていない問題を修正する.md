---
id: TASK-330
title: 差分の更新契機がウィンドウ間・index 変更に届いていない問題を修正する
status: To Do
assignee: []
created_date: '2026-08-06 01:47'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 502000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
refreshDiff の呼び出し元は toggleSourceDiff（自ウィンドウのみ）と store.onContentReloaded の 2 箇所だけ。DiffDisplayPreference はアプリ全体で共有されているのに、⌘D で ON にしても他ウィンドウは差分を取得しないため、メニューのチェックだけ付いて画面は変わらない（他ウィンドウで ⌘D を押すと共有フラグが OFF に反転し、元のウィンドウの差分が消える）。また GitIndexWatch による .git/index 変更・windowDidBecomeKey はバッジのみ更新し refreshDiff を呼ばないため、git commit -a / checkout / stash 後もコミット済みの差分が残り続ける。ViewerWindowController.swift:876 のコメントは「バッジと差分がずれないよう契機を 1 つにする」と主張しているが、バッジは 3 契機・差分は 1 契機になっている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 2 つのウィンドウを開いた状態で片方の ⌘D が両方に反映される
- [ ] #2 git commit -a 後に表示中の差分が更新（消滅）する
- [ ] #3 バッジと差分の更新契機が実際に同一であることを担保するテスト、または構造上ずらせない配線がある
<!-- AC:END -->
