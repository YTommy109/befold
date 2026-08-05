---
id: TASK-309
title: フォルダー移動で戻ってきたとき、直前にそのフォルダーで選択していた項目を復元する
status: To Do
assignee: []
created_date: '2026-08-05 02:28'
updated_date: '2026-08-05 02:29'
labels: []
dependencies: []
priority: medium
ordinal: 507000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SidebarNavigator.navigateToFolder(_:)(SidebarNavigator.swift:314-332)は現在、上へ移動したときだけ選択元の子フォルダーを1階層分復元し(:325-326、folderEntryURL(forKey:)経由)、下や横へ移動したときは selection = nil にする(:328、フォルダー一覧を自動で開かないための意図的な仕様)。既存の戻る/進む履歴(NavigationHistory / SidebarNavigator+History.swift)はブラウザ型の directory+file スナップショットのスタックで、明示的に非永続(永続化はしない、と文書化済み)だが、選択復元はヒストリーの巻き戻し(戻る/進むボタン)経由でしか働かず、通常のクリックによるフォルダー間往復では効かない。「dirB で何かを選択→上へ移動→再び dirB へ入る」という、履歴を使わない通常操作でも、直前に dirB で選択していた項目が再選択されるようにしたい。

FileListModel.selection(FileListModel.swift:85-102)はウィンドウ(SidebarNavigator)ごとのインスタンスで UserDefaults 等へは永続化されておらず、ウィンドウ/アプリの生存期間だけで自然にスコープが切れる。今回求めるのもまさにその範囲(アプリ起動中・ウィンドウが開いている間だけ)なので、ディレクトリごとの「直前の選択」をプロセス内メモリだけで覚えておけばよく、既存の永続化ストア(PathKeyedDictionary 系、ScrollPositionStore・SidebarStateStore 等)ほど重い仕組みは不要と見られる。実装方針(記憶をどこに持たせるか等)は着手時に調査して決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 あるフォルダーで項目を選択した状態で上位階層へ移動し、通常のクリック操作(履歴の戻る/進むを使わない)で再びそのフォルダーへ入ると、直前に選択していた項目が再選択されている
- [ ] #2 この記憶はアプリ実行中(ウィンドウが開いている間)のみ有効で、UserDefaults 等へ永続化されず、アプリ再起動後には復元されない
- [ ] #3 記憶していた項目が削除・リネームされているなど復元できない場合は、現状と同じデフォルト挙動(選択なし)にフォールバックする
- [ ] #4 既存の戻る/進む履歴(NavigationHistory)による選択復元と重複・矛盾しない
<!-- AC:END -->
