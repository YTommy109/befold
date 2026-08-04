---
id: TASK-73
title: CLI オプションを拡充し --help を充実させる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-19 09:10'
updated_date: '2026-07-20 12:52'
labels: []
dependencies: []
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状 befold CLI シム(CLIInstaller.shimScriptContents)は `exec open -a <bundle> "$@"` のみで、
ファイルパス以外のオプション引数を受け取れない。LLM エージェント(Claude Code など)が
シェル経由で befold を操作しやすくするため、CLI オプション・サブコマンドを拡充し、
--help の usage を充実させる。詳細は各サブタスクで扱う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold --help で全オプション・サブコマンドの usage が一覧できる
- [x] #2 複数ファイル/フォルダを指定した場合は複数ウィンドウで開く
- [x] #3 表示オプション(隠しファイル表示・並び順・行番号表示・ソース/プレビューモード)を CLI から指定できる
- [x] #4 bookmark サブコマンドでブックマークを追加できる
- [x] #5 check サブコマンドで befold が開けるファイルかどうかとファイルサイズ・型などの詳細を確認できる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
5つのサブタスク(TASK-73.1〜73.5)をすべて完了。73.1でCLIArgumentParser(argv解析基盤・--help)とCLIシムのbundle内バイナリ直接exec化・起動中インスタンスへの転送(CLIInstanceRouter)を実装。73.2は73.1の実装(initialPathsループ+複数URL転送)で複数ウィンドウオープンが既に成立していたため追加のプロダクションコードなしでテストのみ追加。73.3で--hidden-files/--sort/--line-numbers/--source/--previewを実装し、既存ストア(HiddenFilesPreference/ViewerStore.showLineNumbers/SourceModeStore)を再利用、CLIInstanceRouterをDistributedNotificationCenter方式に見直してオプションも起動中インスタンスへ届くようにした。73.4でbefold bookmark add <path>を実装(既存BookmarkStoreにadd(_:)追加)。73.5でbefold check <path>を実装(既存FileType・サイズ上限定数・RejectReasonを再利用)。全サブタスクでswift test全パスを確認、最終的に521件全パス・swiftlint新規違反なしを維持。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLI引数パーサー基盤の整備、複数ファイル/フォルダーの複数ウィンドウオープン、--hidden-files/--sort/--line-numbers/--source/--previewの表示オプション、bookmark/checkサブコマンドを実装し、befold --helpで全体のusageを確認できるようにした。既存の設定ストア・判定ロジック(HiddenFilesPreference・ViewerStore・SourceModeStore・BookmarkStore・FileType等)を可能な限り再利用し、専用の内部状態は最小限(ソート順・行番号・ソースモードの一回限りの起動時オーバーライドパラメータ)に留めた。CLIシムはopen -a経由からbundle内バイナリの直接execに変更し、起動中インスタンスへはDistributedNotificationCenter経由でパス・オプションをまとめて転送する設計にした。swift test 521件全パス、swiftlint新規違反なしで検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
