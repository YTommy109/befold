---
id: TASK-166
title: Quick Open で入力しても候補が絞り込まれない(タイプで refresh が走らない)
status: To Do
assignee: []
created_date: '2026-07-27 08:36'
updated_date: '2026-07-27 08:36'
labels:
  - quick-open
  - bug
  - regression
dependencies: []
priority: high
type: bug
ordinal: 241000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cmd+P の Quick Open でファイル名をタイプしても候補リストが絞り込まれない。VSCode のようにキーストロークごとに更新されず、パネルを開いた時点の一覧(履歴+ブックマーク)のまま固定される。

## 再現(実機で確認済み)
git リポジトリ内のファイルを開き Cmd+P → 'viewer' とタイプ。TextField の値は 'viewer' に更新されるが、候補は履歴のまま(例: alpha.md / gamma.md)で、'viewer' に一致する追跡ファイル(ViewerStore.md 等)が現れない。

## 原因(A/B 検証で確定)
TASK-165 の項目(5)で QuickOpenModel.queryText を『明示 computed setter(storedQueryText + setter 内で refresh())』から『格納プロパティ + didSet で refresh()』へ変更したことが原因。
- @Observable の didSet は Swift の直接代入では発火するため QuickOpenModelTests(model.queryText = ... を直接代入)は通ってしまう。
- しかし SwiftUI TextField が @Bindable の $model.queryText binding 経由で書き込む経路では didSet が発火せず refresh() が呼ばれない。
- 同一ビルドで queryText を明示 setter に戻すと、'viewer' 入力で ViewerStore.md が候補に現れる(絞り込み動作)ことを running app + System Events で確認。didSet 版では現れない。
- 元の TASK-159 実装は明示 setter を使い『@Observable の didSet 発火タイミングに依存しない』趣旨のコメントを残していた。TASK-165(5) はその根拠を『sizingOptions 欠落が真因』と誤読して didSet に戻し、本退行を作った。

## 該当
BefoldApp/befold/App/QuickOpenModel.swift:40-45(queryText の didSet) / BefoldApp/befold/App/QuickOpenView.swift:30($model.queryText)

## 対応方針
queryText を明示 computed setter(setter 内で refresh を呼ぶ形)に戻す。@Bindable binding 経由でも確実に refresh が走ることを実機で確認する。didSet に依存しない理由をコメントで残し、TASK-165(5) の再発を防ぐ。SwiftUI binding 特有の挙動のためユニットテストでの再現が難しい点も明記する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 タイプするたびに候補が絞り込まれる(fuzzy/パスモードとも)。git リポジトリで 'viewer' 等を入力し一致ファイルが現れることを running app で手動確認
- [ ] #2 queryText の変更が @Bindable($model.queryText)binding 経由でも確実に refresh を起動する実装になっている
- [ ] #3 didSet へ戻すと同じ退行が起きる旨と、SwiftUI binding 経由では didSet 発火に依存できない理由をコメントで残す
- [ ] #4 QuickOpenModelTests(直接代入)は引き続き通る。binding 経由の退行はユニットで再現困難なため手動確認手順を実装メモに残す
<!-- AC:END -->
