---
id: TASK-41
title: サイズ超過テキストが「未対応フォーマット」と誤表示される(サイズ上限チェックが3箇所に重複)
status: To Do
assignee: []
created_date: '2026-07-17 02:07'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerStore.computeLoad の事前サイズチェックは `if let size = fileReader.fileSize(at:)` で、fileSize が nil を返すと黙ってスキップされる(DefaultFileReader は resourceValues 失敗で nil を返し得る。サイズチェック後に readData までにファイルが100MBを超える TOCTOU もある)。その場合 NormalizedTextCache.init が NormalizedTextCacheError.fileTooLarge を throw するが、computeLoad の generic catch が全エラーを .unsupportedFormat にマップするため、ユーザーには「未対応フォーマット」と誤った理由が表示される。

背景: 100MB 上限の強制が ContentLoader.swift:33、computeLoad(:291-296, :310-315)、NormalizedTextCache.init の3箇所に重複しており、理由マッピングが揃っていない。修正時は単純化(上限チェックの単一情報源化、例: テキスト読み込み分岐を ContentLoader へ戻す)を先に検討する。TASK-2(エンコーディング検出の単一情報源化)と関連。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 NormalizedTextCacheError.fileTooLarge が rejectReason .fileTooLarge として表示される(テストあり)
- [ ] #2 サイズ上限の判定と理由マッピングの単一情報源化を検討し、結果をタスクに記録する
<!-- AC:END -->
