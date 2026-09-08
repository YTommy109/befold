---
id: TASK-598
title: BefoldKit から PDFKit 依存を外す（PDFDataProbe をシームにする）
status: To Do
assignee: []
created_date: '2026-09-08 11:57'
labels: []
dependencies: []
ordinal: 867000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-594 で BefoldKit の AppKit 依存を外した際、**もう 1 つプラットフォーム依存が残っていることが実測で分かった**。

実測（`grep -rhE '^ *import ' --include='*.swift' BefoldApp/BefoldKit | sort | uniq -c`、TASK-594 完了時点）:

    45 import Foundation
     2 import CryptoKit
     1 import PDFKit    ← BefoldApp/BefoldKit/PDFDataProbe.swift

PDFKit は Apple プラットフォーム専用フレームワークなので、これがある限り BefoldKit は Foundation のみで成立する層にならない。TASK-594 の Acceptance Criteria は AppKit / Cocoa / WebKit / SwiftUI の 4 つしか見ないため、この依存は AC を満たしたまま残っている。

`scripts/check-befoldkit-platform-free.sh` の ALLOWED_MODULES に PDFKit が「既知の例外」として理由つきで記録してある。**このタスクを完了したらその行を消すこと**（消した時点でスクリプトが違反として検知するので、取りこぼしは起きない）。

なぜ TASK-594 のスコープに含めなかったか: `PDFDataProbe.isReadable` の唯一の消費者が同じ BefoldKit 内の `ViewerLoadPipeline` であり、単純な移設では済まない。判定をシームとして注入する形にする必要があり、`PDFDataProbe` の doc コメントが明示している不変条件（「読み込み側と表示側が `PDFDocument(data:)` という同じ 1 つの事実を見る」）を壊さない設計が要る。これは別の設計判断なので分けた。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 BefoldApp/BefoldKit 配下のどの Swift ファイルも PDFKit を import していない
- [ ] #2 scripts/check-befoldkit-platform-free.sh の ALLOWED_MODULES から PDFKit の行が削除され、スクリプトが通る（許可一覧は Foundation / CryptoKit のみ）
- [ ] #3 「読み込み側の拒否判定と表示側の PDFDocument 生成が同じ 1 つの事実を見る」という PDFDataProbe の不変条件が保たれている（判定が 2 箇所に分かれていない）
- [ ] #4 PDF として開けないデータが拒否されることを見る既存テストが、シーム導入後も通る
<!-- AC:END -->
