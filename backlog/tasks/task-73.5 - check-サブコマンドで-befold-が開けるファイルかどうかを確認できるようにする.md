---
id: TASK-73.5
title: check サブコマンドで befold が開けるファイルかどうかを確認できるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-07-19 09:11'
updated_date: '2026-07-20 12:51'
labels: []
dependencies:
  - TASK-73.1
parent_task_id: TASK-73
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLM エージェントが事前に「このファイルは befold で開けるか」を判断できるよう、
`befold check <path>` サブコマンドを追加する。既存の対応フォーマット判定ロジック
(FileType 等)を再利用し、専用の判定ロジックを新設しない方針で単純化を検討すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold check <path> で befold が開けるファイルかどうかを判定して結果を表示する
- [x] #2 結果にファイルサイズを含める
- [x] #3 結果にファイル型(拡張子/判定された FileType など)を含める
- [x] #4 開けないファイル（未対応フォーマット、サイズ超過等）の場合は理由を表示する
- [x] #5 存在しないパスを指定した場合はエラーメッセージを表示して終了する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 新規 CLICheckCommand(App/CLISubcommandCommand.swift)がbefold check <path>を処理。既存のFileType(url:)による拡張子判定・ContentLoader.maxFileSizeBytes/maxTextFileSizeBytes・NormalizedTextCache.maxFileSizeBytesというサイズ上限定数・RejectReason(unsupportedFormat/fileTooLarge)を再利用し、専用の判定ロジック/エラー種別は新設しなかった。ViewerLoadPipeline.load自体はファイル全体を読み込んで正規化するフルパイプラインのため、サイズ・型を知りたいだけのcheckコマンドには過剰と判断し、同じ定数・FileType判定を使う軽量な再実装(サイズ比較+FileReading.isBinaryでの拡張子偽装検知)とした。これも単純化検討の結果であり、新しい分類ロジックではなく既存の判定基準をそのまま参照している。フォルダー指定時はDirectoryListerと同じ優先順位(対応形式優先→先頭ファイル)で最初のファイルを解決する。結果にはファイルサイズ・FileType(拡張子込み)を含め、開けない場合はRejectReason.localizedMessageで理由を表示する。存在しないパスはexit(1)でエラー終了。CLIArgumentParser.subcommandsに'check'を登録。検証: swift test 521件全パス(CLICheckCommandTests新規7件、CLIArgumentParserTests 2件追加)、swiftlint新規違反なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
befold check <path> サブコマンドを実装。既存のFileType・ContentLoader/NormalizedTextCacheのサイズ上限定数・RejectReasonを再利用し、開けるかどうか・ファイルサイズ・型・(開けない場合の)理由を返す。フォルダー指定時は既存のDirectoryListerと同じ優先順位で最初のファイルを解決する。swift test 521件全パスで検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
