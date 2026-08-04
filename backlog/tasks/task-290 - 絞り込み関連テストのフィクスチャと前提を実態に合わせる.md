---
id: TASK-290
title: 絞り込み関連テストのフィクスチャと前提を実態に合わせる
status: To Do
assignee: []
created_date: '2026-08-04 07:29'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 480000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review(high, 2026-08-04)のテスト品質指摘 2 件。

1. FileListModelFilterTests: 新しい絞り込みテストが gitStatuses だけを設定し gitFolderStatuses を空にしているが、SidebarNavigator は常に同じ aggregate 呼び出しから両方を代入するため、この組み合わせは本番で発生しない。結果として本番では到達しない分岐を固定してしまい、gitFolderStatuses 経路の退行は緑のまま通る。フィクスチャは GitFolderStatus.aggregate(statuses:) 経由で組む。
2. SidebarDisplayPreferenceTests: showChangedFilesOnly の永続化テスト 2 件が既定イニシャライザで読み戻しており、注入引数ではなく周囲の FeatureGate 値（DEBUG かどうか）に依存する。swift test -c release などでは永続化とは無関係の理由で落ちる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 絞り込みテストのフィクスチャが GitFolderStatus.aggregate 経由で組まれ、本番で起きうる状態だけを固定する
- [ ] #2 永続化テストが FeatureGate の周囲の値に依存せず、注入引数で意図した状態を作る
- [ ] #3 swift test -c release で該当テストが通ることを確認する
<!-- AC:END -->
