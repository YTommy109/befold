---
id: TASK-621
title: フォルダーをブックマークに追加できる経路（管理パネルへのドロップと CLI --bookmark）を塞ぐ
status: Done
assignee:
  - '@claude'
created_date: '2026-09-13 14:58'
updated_date: '2026-09-13 15:06'
labels: []
milestone: m-9
dependencies: []
priority: medium
type: bug
ordinal: 816000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
フォルダーはブックマークできない仕様（ウィンドウ側の ⌘D / ツールバーは ViewerCapabilities.canBookmark = isPresentingDocument で、フォルダー一覧の表示中は無効）なのに、2 つの経路がフォルダーを追加できてしまう。

- 管理パネルへの Finder からのドロップ: BookmarkManagerModel.dropDecision が「ディレクトリは受け入れる」。TASK-536.3 の設計スナップショット（docs/superpowers/specs/2026-09-12-bookmark-management-design.md の 4 節）が仕様と逆の判断をそのまま入れていた
- CLI の befold --bookmark <path>: CLIBookmarkCommand.run が存在確認しかしておらず、転送先の GUI（GlobalDisplayBroadcaster.addBookmarks）も判定しない

TASK-620.1 はこの前提（ディレクトリのブックマークがある）の上に BookmarkEntry.isDirectory の記録とフォルダーアイコンを作ったが、フォルダーを追加できないならその記録は不要になる。

ユーザー判断（2026-09-13）: 両方の入口で弾く / 既存のフォルダーのブックマークは消さずに表示し続ける（削除はユーザーが明示的に行う）/ TASK-620 の stacked PR（#662〜#666）の上に 1 本積む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 管理パネルへフォルダーをドロップすると追加されず、弾いた理由がパネル下部の 1 行に出る
- [x] #2 befold --bookmark にフォルダーを渡すと追加されず、エラーメッセージを出して非 0 で終了する（GUI 起動中の転送経路でも追加されない）
- [x] #3 フォルダーかどうかの判定が 1 箇所にあり、ドロップと CLI の両方がそれを使う
- [x] #4 BookmarkEntry.isDirectory の記録とフォルダーアイコンの分岐を撤去し、アイコンは拡張子だけで決まる（既存データのフォルダーのブックマークは消えずに表示される）
- [x] #5 native-app-design.md のブックマーク関連の記述（ドロップの受け入れ規則・種別の記録・アイコン）が実装に追随している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 規則を BookmarkStore.canBookmark(_:fileReader:)（フォルダーなら false）の 1 つに置く
2. BookmarkManagerModel.dropDecision でフォルダーを新しい理由 .folder で弾く（l10n bookmarks.manager.drop.folder）
3. CLIBookmarkCommand.run で GUI へ転送する前に弾く（存在確認のクロージャを FileReading に置き換え、同じ読み手で判定）
4. TASK-620.1 の BookmarkEntry.isDirectory の記録・ストアへの FileReading 注入・BookmarkDropOutcome.Added を撤去し、iconType は拡張子だけに
5. テストと native-app-design.md
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化の検討: ストアの add に同じ判定を重ねる案は採らなかった。CLI は run の中で転送前に弾くので転送経路にも効き、⌘D は提示中の文書にしか効かない（canBookmark = isPresentingDocument）ため、入口は 2 つで足りる。620.1 の種別の記録を撤去したことで、ストアの FileReading 注入と BookmarkDropOutcome.Added も不要になり削除した。
既存データ: ユーザー判断どおり消さない。表示では stat しないので種別は分からず、拡張子の無いフォルダー名は汎用の書類アイコンになる。url は .notDirectory のヒントで作るが、開くときは DocumentOpener が stat して判定するので開ける。
検証:
- swift test --skip Integration --skip FileWatcherTests: 1942 件パス / xcodebuild 成功 / swiftlint 差分ゼロ / 型グループ閾値内 / l10n の欠落なし
- 戻すと落ちる: dropDecision の判定を外す → BookmarkManagerModelTests のドロップテスト（/mock/dir が .folder で弾かれない）/ CLI の判定を外す → CLIBookmarkCommandTests「フォルダーはエラーになり、追加も転送もしない」（exit 0・転送 1 回）
- 実機（Debug ビルド、GUI 起動中）: befold-cli --bookmark <フォルダー> → 'Folders cannot be bookmarked: …' exit=1。検証用ドラッグ元アプリからフォルダーをパネルへドロップ → 追加されず、パネル下部に '1 item(s) could not be added: finder-drop (folders can't be bookmarked)'。以前の版の形で保存したフォルダーのブックマーク（sample-folder）は消えずに表示（.tmp/TASK-620/621-*.png, 6203-621drop.png）
native-app-design.md: BookmarkStore / BookmarksMenuController / BookmarkManagerView の行を更新（種別の記録の記述を撤去し、フォルダーを弾く規則を追記）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
フォルダーをブックマークに追加できていた 2 経路（管理パネルへのドロップ・befold --bookmark）を、共有の規則 BookmarkStore.canBookmark で塞いだ。ドロップは理由付きの 1 行で、CLI は GUI へ転送する前にエラーで伝える。TASK-620.1 の isDirectory 記録とフォルダーアイコンは前提が崩れたので撤去し、アイコンは拡張子だけで決まる。既存のフォルダーのブックマークは残す。Swift 1942 件パス、実機で CLI・ドロップ・既存データの表示を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
