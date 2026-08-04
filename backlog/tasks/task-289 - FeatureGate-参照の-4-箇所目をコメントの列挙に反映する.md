---
id: TASK-289
title: FeatureGate 参照の 4 箇所目をコメントの列挙に反映する
status: To Do
assignee: []
created_date: '2026-08-04 07:29'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 479000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review(high, 2026-08-04)。TASK-283 でコメントに『露出点は 3 箇所』と列挙した直後、TASK-284 で SidebarDisplayPreference.init の既定引数（isChangedFilesOnlyAvailable = FeatureGate.inProgressFeaturesEnabled）という 4 箇所目の参照を足しており、列挙が既にずれている。

放置した場合の影響: TASK-187 でコメントどおり 3 箇所の分岐を消すと、SidebarDisplayPreference 側の読み出しだけが残る。stable 昇格後も保存値 ON が OFF として読まれ続け、機能を有効化したのに絞り込みが復活しない。

同型の抜けが 2 回続いているため、コメントの追記ではなく『ゲート参照を足したら必ず列挙が更新される』仕組み（テストで参照箇所数を固定する等）も併せて検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 FeatureGate の列挙に SidebarDisplayPreference.init の参照が含まれる
- [ ] #2 TASK-187 で消すべき箇所が列挙から漏れなく辿れる
- [ ] #3 ゲート参照を足したときに列挙の更新漏れが検知できる手段が用意されるか、用意しない判断の理由が記録される
<!-- AC:END -->
