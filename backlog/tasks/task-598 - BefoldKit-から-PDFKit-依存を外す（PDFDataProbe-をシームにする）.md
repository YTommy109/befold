---
id: TASK-598
title: BefoldKit から PDFKit 依存を外す（PDFDataProbe をシームにする）
status: Done
assignee:
  - '@claude'
created_date: '2026-09-08 11:57'
updated_date: '2026-09-08 12:49'
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
- [x] #1 BefoldApp/BefoldKit 配下のどの Swift ファイルも PDFKit を import していない
- [x] #2 scripts/check-befoldkit-platform-free.sh の ALLOWED_MODULES から PDFKit の行が削除され、スクリプトが通る（許可一覧は Foundation / CryptoKit のみ）
- [x] #3 「読み込み側の拒否判定と表示側の PDFDocument 生成が同じ 1 つの事実を見る」という PDFDataProbe の不変条件が保たれている（判定が 2 箇所に分かれていない）
- [x] #4 PDF として開けないデータが拒否されることを見る既存テストが、シーム導入後も通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
方針: ユーザー確認済み（新しい小さなターゲットを作る案を選択、2026-09-08）。

1. 新ターゲット `BefoldPDFProbe` を追加し、`BefoldApp/BefoldPDFProbe/PDFDataProbe.swift` へ `PDFDataProbe` を移設（BefoldKit からは削除）。依存は PDFKit のみで BefoldKit にも依存しない（`(Data) -> Bool` に BefoldKit の型は要らない）。
2. 同時に `PDFDataProbe.makeDocument(_:) -> PDFDocument?` を足し、`isReadable` はその nil 判定へ一本化する。表示側（`befold/Viewer/PDFPreviewView.swift`）が `PDFDocument(data:)` を直接呼んでいるのをこの入口へ寄せ、AC#3 の「読み込み側と表示側が同じ 1 つの事実を見る」を doc コメントではなく型で担保する。
3. `BefoldKit/ViewerLoadPipeline.swift`: `public typealias PDFReadabilityProbe = @Sendable (Data) -> Bool` を追加し、`load` に `isPDFReadable: PDFReadabilityProbe` を **必須引数** で足す（`chunkedReaderFactory` の直後、デフォルト引数群より前）。`validated(_:isPDFReadable:)` へ引き回す。デフォルト引数は「付けない方針」ではなく **構造上置けない**（BefoldKit から PDFKit を参照できないため）ので、渡し忘れは必ずコンパイルエラーになる。
4. 本番呼び出し元 3 箇所が `PDFDataProbe.isReadable` を渡す: `befold/Viewer/ViewerLoadStarter.swift`、`BefoldCLI/CLICheckCommand.swift`、`BefoldRenderKit/OneShotRenderer.swift`。
5. テスト側の `ViewerLoadPipeline.load` 呼び出し 14 箇所にも probe を渡す（`befoldTests` は既に PDFKit を import 済み）。
6. `Package.swift` と `BefoldApp/project.yml` にターゲットと依存辺を追加（befold / BefoldCLI / BefoldRenderKit / BefoldQuickLook / befoldTests）。`xcodegen generate` を実行。
7. `scripts/check-befoldkit-platform-free.sh` の ALLOWED_MODULES から PDFKit の行とその説明コメントを削除する（許可は Foundation / CryptoKit のみ）。
8. `docs/dev/native-app-design.md` を更新（ターゲット表・モジュールツリー・「プラットフォーム非依存に保つ」節の許可一覧）。`.claude/CLAUDE.md` のターゲット表にも 1 行足す。
9. 検証: swift build / swift test / xcodebuild build -scheme befold / swiftlint ベースライン差分ゼロ / ガードスクリプトの self-test と本実行 / PDFKit を BefoldKit へ戻すと落ちることの実測。

検討して採らなかった案:
- 同じ 1 行を befold / BefoldCLI / BefoldRenderKit の 3 つに置く → AC#3 に抵触（判定が 3 箇所）。
- `PDFDataProbe` を BefoldRenderKit に置く → BefoldCLI が依存すると WebKit が CLI に入る。BefoldCLI に置く案も BefoldRenderKit が依存すると ArgumentParser が appex に入るため不可（Package.swift のコメントが両方を明示的に避けている）。
- `#if canImport(PDFKit)` で条件化して BefoldKit に残す → AC#1 に文字どおり抵触し、ガードも textual なので鳴る。
- Foundation だけで PDF を判定する → AC#3 の不変条件（`PDFDocument(data:)` と同じ 1 つの事実）を壊す。

--- /review-design の結果（2026-09-08）---
F1. [項目1・9] 「読み込み側と表示側が同じ 1 つの事実を見る」を doc コメントでしか守っていない。本番の `PDFDocument(` 生成は実測 2 箇所（`BefoldKit/PDFDataProbe.swift:17` と `befold/Viewer/PDFPreviewView.swift:54`）で、`makeDocument` へ寄せても次に直接書けば黙って戻る。→ `BefoldApp/.swiftlint.yml` の `custom_rules` に `pdf_document_creation_outside_probe` を追加する（`included` は BefoldApp 配下の本番 Swift、`excluded` は BefoldPDFProbe とテスト。テストは fixture 生成で 26 箇所使っているため対象外）。前例は同ファイルの `git_repository_open_outside_git_library`（「開くのは GitLibrary だけ」）で完全に同型。新しいスクリプトは作らない。
F2. [項目5] 新ターゲットは framework になり、`OneShotRenderer` 経由で QuickLook 拡張（appex）にリンクが要る。同梱漏れは dyld が起動時に落ちる形で、しかも QuickLook の失敗は静か（プレビューが出ないだけ）。`swift build` は通り `xcodebuild` だけが落ちる型でもある。→ 検証手順に「`.app` を作った後 appex の中身を実測して BefoldPDFProbe.framework の解決を確認する」を追加する。
F3. [項目2] `makeDocument` の追加は `PDFDataProbe` の既存の不変条件（「生成した PDFDocument はここで捨て、アクターをまたいで運ばない」）を緩める。→ `makeDocument` は nonisolated のままにし、戻り値を Sendable にしない（アクター越えが自動でコンパイルエラーになる）。doc を「`isReadable` は Bool だけ返す背景経路用 / `makeDocument` は同一アクター内専用」に書き換える。
F4. [項目7] ガードスクリプトが `BefoldApp/BefoldKit` だけを見ていること（新ターゲットは意図的に対象外）をコメントに明記する。

実測メモ:
- 本番の `PDFDocument(` 生成は 2 箇所のみ。他 26 箇所は全て befoldTests の fixture 生成。
- `PDFPreviewView.updateNSView` の `PDFDocument(data:)` は `appliedRevision != contentRevision` のガード内なので高頻度経路ではない。
- 型グループ行数（閾値 400、例外表への該当なし）: ViewerLoadPipeline 169→約175 / ViewerLoadPipelineTests 293→約304 / PDFDataProbe 19→約30 / PDFPreviewView 72→72。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装と検証（2026-09-08）

### 変更
- **新ターゲット `BefoldPDFProbe`**（`Package.swift` / `project.yml`）。`PDFDataProbe` をここへ移設し、PDFKit はこの 1 ファイルだけが import する。BefoldKit にも依存しない（判定は `(Data) -> Bool` で完結）。
- `PDFDataProbe.makeDocument(_:) -> PDFDocument?` を追加し、`isReadable` はその nil 判定へ一本化。表示側 `befold/Viewer/PDFPreviewView.swift` の `PDFDocument(data:)` 直呼びをこの入口へ寄せた。
- `BefoldKit/ViewerLoadPipeline.swift`: `PDFReadabilityProbe` typealias と `Inputs` 構造体を追加。`load` は `Inputs` を 1 つ受ける形へ。
- `befold/Viewer/LoadInputs.swift` を削除（`ViewerLoadPipeline.Inputs` へ統合。同じ束が 2 つあると片方だけに項目が増えるため）。
- `.swiftlint.yml` に `pdf_document_creation_outside_probe` を追加（F1 の担保）。
- `scripts/check-befoldkit-platform-free.sh` の ALLOWED_MODULES から PDFKit を削除。
- `docs/dev/native-app-design.md` と `.claude/CLAUDE.md` を更新。

### 途中で追加した設計判断（計画外）
`load` の必須引数が 6 個になり `function_parameter_count` の**新規違反**が出た（ベースライン差分ゼロの規約に抵触）。閾値を緩めず、`befold/Viewer/LoadInputs.swift` の doc コメントが記録していた同一状況の前例（「個別に渡すと引数 6 個で function_parameter_count に触れる。束ねたのは数合わせではなく 1 つの関心だから」）に従って `ViewerLoadPipeline.Inputs` へ束ねた。副産物として、befold 側にあった重複型 `LoadInputs` が消え、`fileReader` と `contentLoader` が別の `FileReading` を見る組み合わせを書けないようにする簡便 init を足せた。

### 検証（実測）
- **AC#1**: `grep -rn 'import PDFKit' --include='*.swift' BefoldApp/BefoldKit` → **0 件**。BefoldKit の import 一覧は `Foundation` 46 / `CryptoKit` 2 のみ
- **AC#2**: ALLOWED_MODULES は `Foundation` / `CryptoKit` の 2 つ。self-test OK、本実行 OK。PDFKit を BefoldKit へ戻すと exit 1（TASK-594 時に実測済みの経路）
- **AC#3**: 本番コードで `PDFDocument(` を生成するのは `BefoldPDFProbe/PDFDataProbe.swift:34` の **1 箇所のみ**（他のヒットはコメント）。加えて swiftlint の `pdf_document_creation_outside_probe` が担保し、`PDFPreviewView` を直呼びへ戻すと error で落ちることを実測（戻して確認後に復元）
- **AC#4**: `swift test` **1923 tests / 315 suites すべて pass**。PDF 関連 5 スイート（PDFSurfaceLoad / ViewerStoreBinaryContent / ViewerLoadPipeline / UnsupportedFileViewSnapshot / MarkdownImageEmbedderSharedInstance）とも passed
- `xcodebuild build -scheme befold` **BUILD SUCCEEDED**
- **F2（appex への同梱）**: appex の dylib が `@rpath/BefoldPDFProbe.framework/Versions/A/BefoldPDFProbe` を要求し、rpath 解決先 `befold.app/Contents/Frameworks/` に実体があることを `otool -L` で実測
- swiftlint ベースライン: main 51 / HEAD 51、生 diff **空**、真の新規 **0 件**
- swiftformat 変更なし、markdownlint（81 files）0 issues、check-doc-citations / check-doc-symbols 通過

### 途中の失敗（記録）
テスト畳み込みの正規表現がヘルパー自身の本体にも一致し、`inputs(...)` が自己再帰して `swift test` が SIGBUS（signal 10）で落ちた。要約行には `✘` が出ず落ちる箇所も毎回違ったため、クラッシュレポート（`~/Library/Logs/DiagnosticReports/`）のスタックで `ViewerLoadPipelineTests.inputs(_:_:_:contentLoader:)` の再帰と特定した。置換件数が想定 11 に対し 12 だったのが最初の兆候。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BefoldKit の最後のプラットフォーム依存だった PDFKit を、新ターゲット BefoldPDFProbe へ隔離した。BefoldKit の import は Foundation / CryptoKit の 2 つだけになり（実測 0 件の PDFKit）、ガードスクリプトの既知例外も消えた。判定は BefoldPDFProbe.PDFDataProbe の 1 箇所に閉じ、読み込み側へは既定値を持てない必須引数として注入する（BefoldKit から実装を参照できないため、渡し忘れは構造上コンパイルエラー）。表示側の PDFDocument 直呼びも同じ入口へ寄せ、swiftlint の custom rule で機械的に固定した。副産物として重複型 LoadInputs を ViewerLoadPipeline.Inputs へ統合。swift test 1923 件 pass、xcodebuild BUILD SUCCEEDED、appex の framework 解決を otool で実測、swiftlint 新規違反 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
