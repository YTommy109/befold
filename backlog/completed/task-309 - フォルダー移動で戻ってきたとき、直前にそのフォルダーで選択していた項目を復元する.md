---
id: TASK-309
title: フォルダー移動で戻ってきたとき、直前にそのフォルダーで選択していた項目を復元する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-05 02:28'
updated_date: '2026-08-05 07:41'
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
- [x] #1 あるフォルダーで項目を選択した状態で上位階層へ移動し、通常のクリック操作(履歴の戻る/進むを使わない)で再びそのフォルダーへ入ると、直前に選択していた項目が再選択されている
- [x] #2 この記憶はアプリ実行中(ウィンドウが開いている間)のみ有効で、UserDefaults 等へ永続化されず、アプリ再起動後には復元されない
- [x] #3 記憶していた項目が削除・リネームされているなど復元できない場合は、現状と同じデフォルト挙動(選択なし)にフォールバックする
- [x] #4 既存の戻る/進む履歴(NavigationHistory)による選択復元と重複・矛盾しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarNavigator にプロセス内メモリ(ディレクトリ pathKey -> 直前の選択 URL)を持たせる
2. navigateToFolder で移動元の選択を記録し、移動先で記録があり一覧に存在すれば復元(ファイルなら performFileSwitch も行う)
3. 記録が無い/復元できない場合は現状の挙動(上へ移動=直前の子フォルダー、それ以外=先頭行)へフォールバック
4. 履歴(NavigationHistory)経路には手を入れない
5. SidebarNavigatorFolderNavigationTests にテストを追加
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: SidebarNavigator に selectionMemory([正規化パスキー: URL], メモリ内のみ)を追加し、navigateToFolder が移動前に現在の選択を記録、移動後は記録があり可視一覧に残っていればそれを選択(ファイルなら performFileSwitch まで行い、プレビューを追従させる)。記録が無い/復元できない場合は従来どおり「上へ移動なら直前の子フォルダー、それ以外は先頭行」へフォールバック。選択反映は selectHeadEntry を select(_:presentingWith:) に一般化して共通化した。履歴(NavigationHistory / applyHistoryEntry)には手を入れていない。

単純化の検討: 上へ移動時の子フォルダー復元は多くの場合この記憶で置き換えられるが、パンくず等クリック以外で降りた場合に記録が無く退行するため、記憶ミス時のフォールバックとして残した。

ファイル分割: selectionMemory のヘルパーは SidebarNavigator+SelectionMemory.swift、テストは SidebarNavigatorSelectionMemoryTests.swift に切り出した(既存ファイルのままだと file_length / type_body_length が新規警告になるため)。xcodegen generate 済み。

検証: swift test 全 1119 テスト green。新規テスト 2 件は修正前に赤(復元テストが a.mmd を選び host.currentFileURL も切り替わらない)ことを確認済み。swiftlint はベースライン(main と同じ 78 件)から増減なし、swiftformat 差分なし、xcodebuild build -scheme befold exit=0。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
フォルダーごとの直前の選択をウィンドウ内メモリ(SidebarNavigator.selectionMemory)に覚え、通常のクリック操作で再訪したときに復元するようにした。復元できない場合は従来の既定挙動へフォールバックし、戻る/進む履歴の経路は変更していない。SidebarNavigatorSelectionMemoryTests の 2 テスト(復元・削除時フォールバック)と swift test 全件 green、swiftlint ベースライン差分ゼロで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
