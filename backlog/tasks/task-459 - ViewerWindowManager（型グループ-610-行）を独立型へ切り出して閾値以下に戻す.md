---
id: TASK-459
title: ViewerWindowManager（型グループ 610 行）を独立型へ切り出して閾値以下に戻す
status: To Do
assignee: []
created_date: '2026-08-12 02:21'
labels: []
dependencies: []
priority: low
ordinal: 683000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-426 で ViewerWindowManager を分割したが、切り出し先を同ディレクトリの ViewerWindowManager+*.swift にしたため、型グループ（Foo.swift + 同ディレクトリの Foo+*.swift の合算）としては 610 行で閾値 400 を超えたままになっている。scripts/type-group-baseline.txt に凍結値として残っており、TASK-428.5（ベースライン撤去）の着手を妨げている。

内訳（実測 2026-08-12）:
ViewerWindowManager.swift 155 / +OpenViewer 144 / +SessionSync 93 / +GlobalDisplay 82 / +TabGroups 69 / +RecentRepositories 67。

extension への分割では型グループの合計は減らないため、責務を独立した型へ移す（同ディレクトリの ViewerWindowManager+*.swift ではなく、別の型として切り出す）。どの責務を独立型にするかは着手時に判断する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 型グループ BefoldApp/befold/App/ViewerWindowManager の行数が 400 以下になっている（scripts/check-type-group-size.sh の出力で確認）
- [ ] #2 scripts/type-group-baseline.txt から ViewerWindowManager のエントリが削除されている
- [ ] #3 swift test が緑で、swiftlint のベースライン差分がゼロである
<!-- AC:END -->
