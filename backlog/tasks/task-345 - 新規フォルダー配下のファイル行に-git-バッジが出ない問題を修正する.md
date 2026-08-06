---
id: TASK-345
title: 新規フォルダー配下のファイル行に git バッジが出ない問題を修正する
status: To Do
assignee: []
created_date: '2026-08-06 07:56'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 611000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーで、新しく作った未追跡フォルダーの配下にあるファイルの行に git ステータスバッジが一切出ない（'?' も出ない）。同じ行が「変更ファイルのみ表示」フィルターには残るため、フィルター結果とバッジ表示が食い違う。

原因（コード参照）:
- porcelain の既定 `-unormal` は未追跡ディレクトリを `dir/` の 1 レコードへ畳むため、新規フォルダー配下のファイルは statuses にキーを持たない（BefoldApp/befold/App/SidebarGitStatus.swift:44-52 に既知として記述あり）。
- TASK-285 でこの畳み込みへの対処が hasChange 側にだけ入った。hasChange（SidebarGitStatus.swift:53-57）は hasUntrackedAncestor で祖先を辿るが、バッジの供給元である fileStatus(at:)（同 :34-37）は files の直接引きのままで祖先を辿らない。
- 結果、Viewer/FileListView.swift:163-164 → Viewer/FileListEntryRow.swift:71-73 の経路でバッジが nil になる。

単純化の検討結果: 新しい状態や分岐を足さず、fileStatus(at:) 側で既存の hasUntrackedAncestor を使い、畳み込み配下では isUntracked の GitFileStatus を返すようにするのが最小。そうすると hasChange は `fileStatus(at:) != nil || folders[pathKey] != nil` に縮み、現在 2 か所に分かれている祖先判定の経路が 1 本になる（判定のずれが再発しない構造になる）。

FeatureGate.isSidebarGitStatusEnabled 配下のため、コミットには (gate) スコープを付けること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 未追跡フォルダー配下のファイル行に、未追跡を示す灰色の '?' バッジが表示される
- [ ] #2 fileStatus(at:) と hasChange(at:) の判定が一致し、フィルターに出る行には必ずバッジが付く（祖先判定のロジックが 1 か所に集約されている）
- [ ] #3 追跡済みフォルダー内の未変更ファイルにバッジが付かないこと（TASK-285 のコメントが警告している誤判定）を検証するテストがある
- [ ] #4 修正を戻すと落ちることを確認したテストが追加されている
- [ ] #5 swiftlint の main 比ベースライン差分がゼロである
<!-- AC:END -->
