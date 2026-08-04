---
id: TASK-284
title: stable ビルドで ShowChangedFilesOnly を OFF に戻せない問題に対処する
status: To Do
assignee: []
created_date: '2026-08-04 06:47'
labels: []
dependencies: []
priority: low
ordinal: 474000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-264 で追加した「変更されたファイルのみ表示」の設定は UserDefaults（キー ShowChangedFilesOnly）に永続化される。dev ビルドで ON にしたまま stable ビルドを起動すると、メニュー項目もヘッダーのアイコンボタンも FeatureGate で消えるため、ユーザーは ON を OFF に戻す手段を持たない。

現時点の実害（2026-08-04 にコードで確認）:
- FileListModel.isGitChangeFilterEffective が gitStatuses / gitFolderStatuses の空を見て縮退するため、stable では絞り込みが効かず一覧は全件表示される。一覧が空になる事故は起きない。
- 残る影響は「次に dev ビルドを起動したとき ON で始まる」ことのみ。

対処の候補（着手時に選定する。ゲート解除 TASK-187 が先に済めば本タスク自体が不要になる）:
- A: SidebarNavigator.syncDisplayPreferences で FeatureGate 無効時は false を同期する（設定値は残すが、無効ビルドでは一切効かないことを明示する）
- B: SidebarDisplayPreference 側で無効時は読み出しを false に倒す
- C: 対処せず、TASK-187 まで許容する（この場合は本タスクを Won't Do にして理由を残す）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 stable ビルドで ShowChangedFilesOnly が ON でも、モデル側の showChangedFilesOnly が ON にならない（または OFF に戻す手段がある）
- [ ] #2 dev ビルドへ戻したときの挙動が意図どおりであることが説明できる（設定を保持するのか初期化するのか決めて記録する）
- [ ] #3 選んだ方針の理由が Notes に残る
<!-- AC:END -->
