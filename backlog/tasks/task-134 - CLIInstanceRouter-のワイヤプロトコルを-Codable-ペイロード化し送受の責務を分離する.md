---
id: TASK-134
title: CLIInstanceRouter のワイヤプロトコルを Codable ペイロード化し送受の責務を分離する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:40'
updated_date: '2026-07-25 06:47'
labels:
  - refactor
  - structural
  - cli
dependencies: []
priority: medium
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIInstanceRouter.forward(送信)が CLIOpenOptions の各フィールドを showHiddenFiles/showLineNumbers/sourceMode/showSidebar/sortOrder の文字列キーへ手写しで詰め、decode(userInfo:)が同じ文字列キーを手で読み戻す。CLIOpenOptions は Codable なのにワイヤ表現で活用されず、フィールド追加時に forward/decode/AppDelegate/ViewerWindowManager/SessionRestorer を同時修正する shotgun surgery になる(過去 TASK-82/87 の転送取りこぼしの温床)。加えて CLIInstanceRouter enum が インスタンス探索・送信リトライ+busy-wait・受信/ACK ワイヤプロトコル の異質な 3 責務を同居させ、CLI 側と GUI 側が半分ずつしか使わないのに双方が enum 全体(AppKit/DistributedNotificationCenter 依存)をリンクする。dagayn SAP 指摘(BefoldCLI distance=1.0)の中核。ACK タイミングの TASK-85/88/89 とは別関心で、本タスクは責務分割・依存方向とペイロード表現を対象とする。構造レビュー(2026-07-25)で検出。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLIOpenOptions が JSONEncoder/Decoder で単一キーのペイロードとして送受され、文字列キーの手写しミラーが解消している
- [x] #2 CLIOpenOptions へのフィールド追加が構造体定義のみの変更で完結する(送受のドリフト面がない)
- [x] #3 ワイヤプロトコル(通知名+encode/decode/sendAck)が受信側と共有する薄い型に切り出され、送信側の探索/リトライ/busy-wait が送信専用の配置へ寄っている
- [x] #4 GUI 側が受信プロトコルのみをリンクし、送信専用の探索・リトライ・AppKit 起動依存を負わない
- [x] #5 CLI→GUI のファイルオープン転送が全オプション込みで回帰なく動作する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLIRequest を BefoldCLI/CLIRequest.swift へ切り出し Codable 適合させる(enum の associated value を合成 Codable で扱う)。
2. BefoldCLI/CLIRequestWire.swift を新設し、受信側と共有する薄いワイヤ層(通知名・userInfo(for:requestID:)・decode・requestID・sendAck)だけを置く。ペイロードは JSONEncoder で 1 キー(request)へ集約し、フィールドごとの文字列キー手写しを廃止。AppKit 非依存にする。
3. 送信専用の探索・リトライ・busy-wait(runningInstance/forward/forwardBookmark/postAwaitingAck)を befold-cli/CLIRequestForwarder.swift へ移す。AckWaiting/DistributedAckWaiter も送信側専用なので befold-cli へ移設。BefoldCLI/CLIInstanceRouter.swift は削除。
4. 呼び出し側を更新: AppDelegate は CLIRequestWire のみ参照、CLIAppLauncher/CLIBookmarkRouter は CLIRequestForwarder を参照。
5. テスト整理: befoldTests/CLIInstanceRouterTests.swift を befoldCLITests/CLIRequestForwarderTests.swift へ移設(GUI テスト側から送信ロジック依存を外す)。重複していた befoldTests/StubAckWaiter.swift を削除。CLIInstanceRouterDecodeTests は CLIRequestWireTests として encode→decode の往復検証へ書き換え、全フィールドを埋めた CLIOpenOptions が == で一致することを固定する(フィールド追加時に送受のドリフト面がないことの担保)。
6. swift build / swift test / SwiftLint を通し、CLI→GUI の実転送を全オプション付きで手動確認する(AC#5)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装内容:
- CLIRequest を BefoldCLI/CLIRequest.swift へ切り出し Codable/Sendable 適合(enum の associated value は合成 Codable で扱える)。
- BefoldCLI/CLIRequestWire.swift を新設。受信側と共有する薄いワイヤ層(通知名・userInfo(for:requestID:)・decode・requestID・sendAck・ackRequestID)のみを持ち、要求本体は JSON 文字列 1 キー(request)に集約。フィールドごとの文字列キーの手写しを廃止。AppKit 非依存。
- 送信専用の責務(runningInstance / forward / forwardBookmark / 再送 + ACK busy-wait)を befold-cli/CLIRequestForwarder.swift へ移設。AckWaiting/DistributedAckWaiter も送信側専用なので befold-cli へ移設。BefoldCLI/CLIInstanceRouter.swift は削除。
- 呼び出し側更新: AppDelegate は CLIRequestWire のみ、CLIAppLauncher/CLIBookmarkRouter は CLIRequestForwarder。
- テスト整理: befoldTests/CLIInstanceRouterTests.swift → befoldCLITests/CLIRequestForwarderTests.swift へ移設(GUI テスト側から送信ロジックを外す)。重複していた befoldTests/StubAckWaiter.swift を削除。CLIInstanceRouterDecodeTests → CLIRequestWireTests として往復検証へ書き換え。実 DistributedNotificationCenter を通す CLIRequestWireIntegrationTests を追加(userInfo の plist 直列化を越えられることの確認。通知名は本番値ではなくテスト専用値を使い、開発機の起動中インスタンスに影響させない)。

依存方向の確認(AC#4):
- grep で befold/(GUI)配下に CLIRequestForwarder / AckWaiting / NSRunningApplication の参照が 0 件。
- 共有ターゲット BefoldCLI/ に import AppKit が 0 件(旧 CLIInstanceRouter.swift が唯一の AppKit 依存だった)。

実機での CLI→GUI 転送確認(AC#5):
xcodebuild で .app をビルドし起動、バンドル同梱の befold-cli から
--hidden-files --line-numbers --source --sidebar --sort alphabetical を付けて転送。
- Distributed Notification の観測用リスナで、5 オプション全てが JSON ペイロードに載って届き、GUI が 2-13ms で ACK を返していることを確認。
- GUI が要求を処理してファイルを開き、--no-hidden-files → ShowHiddenFiles=0、--hidden-files → 1 とオプションが反映されることを確認(新ペイロードが受信側で正しく解釈されている証拠)。
- ただし CLI プロセス側が ACK を観測できず exit 1 + 'Failed to forward to the running instance.' を出す既存の問題がある。git stash して変更前のコード(旧 userInfo 形式)で同じ手順を実施したところ、まったく同じ症状(要求は届き GUI は ACK、CLI は観測できず exit 1)となったため、本タスクの変更による回帰ではない。ACK タイミングは本タスクのスコープ外(TASK-85/88/89 系)。ユーザー向けの症状としては別途 Issue 化を検討する。

検証: swift build 成功 / swift test 642 tests in 91 suites 全緑 / SwiftLint 0 serious(55 violations、いずれも既存) / SwiftFormat lint 差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ワイヤ表現と責務配置を分けた。CLIRequest を Codable にし、BefoldCLI/CLIRequestWire が要求本体を JSON 1 キーとして送受する薄い共有層になったので、showHiddenFiles などのフィールド単位キーの手写しミラーは送受どちらにも無くなった(CLIOpenOptions への追加は構造体定義だけで完結)。送信専用の探索・再送・ACK busy-wait と AckWaiting は befold-cli/CLIRequestForwarder へ移し、共有ターゲット BefoldCLI から AppKit 依存が消えた(GUI は受信ワイヤのみをリンク)。検証: swift test 642 tests 全緑、SwiftLint 0 serious。実機では .app をビルドして起動し、同梱 CLI から 5 オプション全付きで転送し、通知リスナで全オプションが JSON ペイロードに載って届き GUI が ACK していること、--no-hidden-files/--hidden-files でオプションが実際に反映されることを確認。CLI が ACK を観測できず exit 1 になる症状は変更前コードでも同一に再現したため回帰ではなく既存問題(スコープ外)。
<!-- SECTION:FINAL_SUMMARY:END -->
