---
id: TASK-260
title: バイナリ判定でファイルを拒否したとき理由がユーザーに伝わらない
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-08-02 15:07'
updated_date: '2026-08-03 01:48'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 454000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
テキストファイル中に生の NUL バイト（0x00）が含まれていると、befold はバイナリと判定して内容を表示しない。この判定自体は妥当だが、画面には「このファイル形式はプレビューに対応していません」としか出ないため、ユーザーは何が原因で開けないのかを推測する手掛かりを得られない。

## 経緯（当初の起票内容からの方針転換）

起票時は「NUL を数個含むテキストは表示できるようにすべき」という前提だったが、これは誤りと判断して方針を変更した。

きっかけになった実例（site/src/lib/visitor.ts）は、コミット b928a2a1 で `${ip}\0${ua}` と書いたつもりの `\0` がエスケープ表記ではなく実際の 0x00 バイトとしてファイルに書き込まれた、生成側の事故だった（commit 778a0051 で修正済み）。ソースコードに生 NUL が入るのは異常であり、befold は壊れたファイルを壊れていると正しく検知していた。

NUL 入りテキストをそのまま表示する方向に変更していた場合、画面には U+FFFD が 2 個表示されるだけで、Worker の重複排除キーが壊れていることに誰も気づかないままだった。検知する振る舞いには価値があるため維持する。

## 真の欠陥

拒否理由が `unsupportedFormat` に丸められており、「形式が非対応」なのか「NUL を含むためバイナリと判定した」のか区別できない。後者だと分かれば、今回のケースはその場で生成事故に気づけた。

判定経路: DefaultFileReader.isBinary（BefoldKit/FileReading.swift:75）が true を返すと、ViewerLoadPipeline.swift:58 が .unsupportedFormat を返し UnsupportedFileView が汎用メッセージを表示する。この経路は GUI・QuickLook 拡張・CLI --check の 3 ホスト共通。

## 補足（対象外）

「NUL が先頭 8KB の内か外かで検知結果が割れる」非一貫性が別に存在する（8KB 以降の NUL は黙って通る）。本タスクの対象外とし、必要なら別タスクとする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 NUL バイトを含むファイルを開いたとき、NUL バイトが理由でバイナリとして扱われたと分かるメッセージが表示される
- [x] #2 バイナリ判定のロジック自体は変更されておらず、真のバイナリ（PNG・実行ファイル等）と BOM なし UTF-16 の判定が退行していない
- [x] #3 読み込み失敗・missing など従来から unsupportedFormat だった経路のメッセージが変わっていない
- [x] #4 GUI・QuickLook 拡張・CLI --check の 3 ホストすべてで新しい理由が表示される（cliMessage / localizedMessage の両方に対応する）
- [x] #5 新しい RejectReason の分岐を網羅するユニットテストがあり、日英の翻訳漏れがない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. RejectReason に case binaryContent を追加し、Localizable.xcstrings に viewer.unsupported.binary（ja/en）を追加する
2. cliMessage にも binaryContent の英語固定文言を追加する
3. ViewerLoadPipeline.swift:58 の isBinary 分岐が返す理由を .unsupportedFormat から .binaryContent に変更する（判定ロジックは無変更）
4. 既存テストのうちバイナリ判定経路の期待値を .binaryContent に更新する（ViewerRendererOneShotIntegrationTests / ViewerStoreTests / CLICheckCommandTests / BefoldCLICommandTests）。読み込み失敗・missing 経路は .unsupportedFormat のまま据え置く
5. RejectReasonTests に binaryContent の localizedMessage / cliMessage が他と異なり空でないことを検証するケースを追加する
6. swift test と /l10n-check で日英の翻訳漏れがないことを確認する

TDD: 5 のテストを先に書いて Red を確認してから 1〜3 を実装する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 方針転換の経緯

当初は「NUL を数個含むテキストを表示できるようにする」方針で Plan 調査まで実施した（案 A: 閾値差し替え / 案 B: TextEncoding へ判定一本化 / 案 C: isBinary 廃止）。実測では案 B が有力で、PNG・mach-o・ランダムバイトは従来どおり拒否されることまで確認済みだった。

しかしユーザーの指摘「visitor.ts は生成されたテキストファイルなので NUL が入っているのがおかしいのでは」を受けて前提を再検証し、方針を破棄した。実際 commit b928a2a1 で `${ip}\0${ua}` の `\0` が実バイトとして書き込まれた生成事故であり、befold は壊れたファイルを正しく検知していた。表示できるようにしていた場合、画面に U+FFFD が 2 個出るだけで Worker の重複排除キーが壊れていることを誰も検知できなかった。

したがって判定ロジックは一切変更せず、拒否理由の伝達のみを改善した。

## 実装

- RejectReason に case binaryContent を追加（unsupportedFormat から分離）
- Localizable.xcstrings に viewer.unsupported.binary を追加（ja/en）
- ViewerLoadPipeline の isBinary 分岐が返す理由を .binaryContent に変更
- DefaultFileReader.isBinary と TextEncoding は無変更

## 検証

- swift test: 997 tests / 149 suites すべて通過（Integration 含む）
- CLI 実機: NUL 入り .ts → "Reason: This file contains NUL bytes and is treated as binary." / exit 1。NUL なしの同内容 .ts → "Can open" / exit 0
- GUI 実機（Debug ビルド）: NUL 入り .ts を開くと「NUL バイトを含むため、バイナリファイルとして扱いました」を表示（スクリーンショットで確認）
- QuickLook: 実機確認は取れず（qlmanage のウィンドウを捕捉できない・dev appex の登録が不確実）。共通経路の ViewerRendererOneShotIntegrationTests で loadOneShot が .binaryContent を返すことを検証して担保
- l10n: 両 xcstrings で en/ja の欠落・空値・state 異常・プレースホルダ不一致なし
- swiftlint: origin/main と同一（78 件、diff 完全一致）

## 対象外として残した論点

「NUL が先頭 8KB の内か外かで検知結果が割れる」非一貫性（8KB 以降の NUL は黙って通る）は未対応。既存テスト utf8WithNulBeyondSniffWindowReadsAsUTF8 がその挙動を固定している。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
バイナリ判定で拒否したファイルの理由が汎用の unsupportedFormat に丸められていたため、RejectReason に binaryContent を追加して「NUL バイトを含むため、バイナリファイルとして扱いました」と具体的に伝えるようにした。判定ロジック（DefaultFileReader.isBinary / TextEncoding）は無変更で、壊れたファイルを検知する振る舞いはそのまま維持している。検証: swift test 997 件通過、CLI と GUI の実機で新メッセージを確認、l10n 漏れなし、swiftlint は origin/main と完全一致。
<!-- SECTION:FINAL_SUMMARY:END -->
