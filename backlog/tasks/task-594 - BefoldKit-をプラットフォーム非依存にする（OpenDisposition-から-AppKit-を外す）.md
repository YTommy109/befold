---
id: TASK-594
title: BefoldKit をプラットフォーム非依存にする（OpenDisposition から AppKit を外す）
status: Done
assignee:
  - '@claude'
created_date: '2026-09-07 14:59'
updated_date: '2026-09-08 12:00'
labels: []
dependencies: []
ordinal: 865000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldKit はコアロジック層だが、47 ファイル中 1 ファイルだけが AppKit に依存している（OpenDisposition.swift の `init(modifiers: NSEvent.ModifierFlags)`）。判定規則そのものは同ファイルの `init(commandKey:shiftKey:)` に閉じており、NSEvent 版はその薄いラッパーでしかない。

依存が 1 箇所しか残っていないため、いま外せば BefoldKit は Foundation のみで成立する層になる。これは将来の Windows 版検討（AppKit / SwiftUI / WebKit が存在しないため UI 層は書き直しになる一方、コア層は再利用したい）で最も再利用価値が高い部分だが、Windows 版を作るかどうかとは独立に、層の責務としても素直になる。逆に AppKit 依存を放置したまま BefoldKit へ機能を足し続けると、依存が 1 から増えて外せなくなる。

NSEvent 版の呼び出し元は AppKit を既に import している呼び出し側（リンククリックの修飾キー解釈）なので、変換をそちら側へ寄せれば済む想定。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 BefoldKit 配下のどの Swift ファイルも AppKit / Cocoa / WebKit / SwiftUI を import していない（`grep -rl 'import AppKit\|import Cocoa\|import WebKit\|import SwiftUI' --include='*.swift' BefoldApp/BefoldKit` が 0 件）
- [x] #2 修飾キーから OpenDisposition を決める規則が BefoldKit の init(commandKey:shiftKey:) 1 箇所に閉じたままで、既存の OpenDispositionTests がテスト本体を変えずに通る（Swift は他モジュールの extension を暗黙には見ないため、import BefoldRenderKit の 1 行追加だけは避けられない。起票時の「変更なし」を実態に合わせて書き換えた）
- [x] #3 NSEvent からの変換を行う新しい入口が、AppKit を既に使っている層（befold / BefoldRenderKit のいずれか）に置かれている
- [x] #4 この依存が再び入ったら落ちる担保がある（テストか、BefoldKit へ AppKit が入らないことを検査する仕組み）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldKit/OpenDisposition.swift から init(modifiers:) を除き import AppKit を落とす（enum 本体は import 不要）。判定規則 init(commandKey:shiftKey:) は動かさない。
2. BefoldRenderKit/OpenDisposition+NSEvent.swift を新設し public extension で init(modifiers:) を置く。中身は init(commandKey:shiftKey:) への委譲のみ（規則は BefoldKit の 1 箇所に閉じたまま）。置き場を BefoldRenderKit にするのは、呼び出し元が befold(FileListView) と BefoldRenderKit(DirectHTMLLinkPolicy) の両方にあり、両者から見える最下層が BefoldRenderKit であるため。
3. 呼び出し側: DirectHTMLLinkPolicy は同ターゲットなので変更不要。befold/Viewer/FileListView.swift に import BefoldRenderKit を足す。
4. befoldTests/OpenDispositionTests.swift に import BefoldRenderKit を 1 行足す（AC#2 の「変更なし」から逸脱するのはこの 1 行のみ。Swift は他モジュールの extension を暗黙には見ないため不可避）。
5. 担保(AC#4): scripts/check-corekit-platform-free.sh を追加（--self-test 付き、grep ベース）。pre-commit(scripts/setup-git-hooks.sh) と .github/workflows/ci.yml へ配線する。
6. xcodegen generate → swift build → swift test → swiftlint ベースライン差分ゼロ。
7. docs/dev/native-app-design.md に「BefoldKit は Foundation のみで成立する層」を追記。

--- /review-design の結果（2026-09-08）---
R1. [項目1・7] Description の「Foundation のみで成立する層になる」は成り立たない。実測: BefoldKit は PDFKit も import している（BefoldApp/BefoldKit/PDFDataProbe.swift）。AC#1 の grep は AppKit/Cocoa/WebKit/SwiftUI の 4 名前しか見ないため、通っても非依存にはならない。→ AC#4 の担保を denylist ではなく **allowlist**（BefoldKit が import してよいモジュールの列挙）にし、PDFKit を理由つきの既知例外として script 内に記録する。PDFKit の除去自体は別タスクへ起票する（唯一の消費者が同じ BefoldKit 内の ViewerLoadPipeline.swift でシーム注入という別の設計判断が要るため）。
R2. [項目9] OpenDisposition.slide の doc コメントが「下の 2 つの初期化子」と書いている。移設後は 1 つになるので同時に直す（同期漏れ型）。
R3. [項目7] pre-commit だけでは scripts/setup-git-hooks.sh 未実行のクローンで素通りするので CI にも配線する。self-test は「検知できること」自体を証明する（check-no-detached-blocking.sh が rg 不在で 0 件になった前例）。
R4. [項目3] 置き場は BefoldRenderKit 一択。befold へ置くと BefoldRenderKit の DirectHTMLLinkPolicy から見えない（Package.swift の依存は befold → BefoldRenderKit → BefoldKit の一方向）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装と検証（2026-09-08）

### 変更
- `BefoldKit/OpenDisposition.swift`: `import AppKit` → `import Foundation`、`init(modifiers:)` を削除。判定規則 `init(commandKey:shiftKey:)` は不変。`.slide` の doc が「下の 2 つの初期化子」と書いていたのを移設後の実態に合わせた（/review-design の R2）。
- `BefoldRenderKit/OpenDisposition+NSEvent.swift`（新規）: `public extension OpenDisposition { init(modifiers: NSEvent.ModifierFlags) }`。中身は `init(commandKey:shiftKey:)` への委譲のみ。
- `befold/Viewer/FileListView.swift` / `befoldTests/OpenDispositionTests.swift`: `import BefoldRenderKit` を 1 行ずつ追加（それ以外の変更なし）。
- `scripts/check-befoldkit-platform-free.sh`（新規）+ pre-commit（`scripts/setup-git-hooks.sh`）と CI（`.github/workflows/ci.yml` の type-group-size ジョブ）への配線。
- `docs/dev/native-app-design.md`: 「BefoldKit はプラットフォーム非依存に保つ」節を追加（現在仕様の層へ吸収）。

### 担保を allowlist にした理由（/review-design の R1）
起票時の AC#1 は denylist（AppKit / Cocoa / WebKit / SwiftUI の 4 名前）だったが、実測で BefoldKit は PDFKit も import していた（`BefoldKit/PDFDataProbe.swift`）。denylist だと `Carbon` / `CoreGraphics` / `UIKit` も素通りするため、スクリプトは **許可するモジュールの列挙** にした。PDFKit は理由つきの既知例外として ALLOWED_MODULES に記録し、除去は TASK-598 へ切り出した。修飾つき import（`import class AppKit.NSEvent`）も拾う。

### 検証（実測）
- AC#1: `grep -rl 'import AppKit\|import Cocoa\|import WebKit\|import SwiftUI' --include='*.swift' BefoldApp/BefoldKit` → **0 件**
- AC#2: `git diff -- BefoldApp/befoldTests/OpenDispositionTests.swift` は **+1 行（import のみ）**。`swift test` で OpenDispositionTests / OpenDispositionSlideTests とも pass
- AC#4: `--self-test` 3 ケース（素の import / 修飾つき import を検知、許可モジュールでは鳴らない）に加え、**BefoldKit へ `import AppKit` を戻すと exit 1 で該当ファイルを名指しして落ちることを実測**（戻して確認後に復元）
- `swift build` 成功。`xcodebuild build -scheme befold -derivedDataPath .build/xcode` **BUILD SUCCEEDED**（xcodegen generate 済み。appex 側も通る）
- `swift test`: **1917 tests / 314 suites すべて pass**（39.7s）
- swiftlint ベースライン: main 51 件 / HEAD 51 件、生 diff **空**、真の新規 **0 件**
- swiftformat（fix モード）: 変更なし。`scripts/swiftformat-lint.sh` 出力なし
- `markdownlint-cli2`（81 files）0 issues、`check-doc-citations.sh` / `check-doc-symbols.sh` 通過
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BefoldKit の唯一の AppKit 依存だった OpenDisposition(modifiers:) を BefoldRenderKit の extension へ移し、判定規則は BefoldKit の init(commandKey:shiftKey:) 1 箇所に残した。BefoldKit の AppKit / Cocoa / WebKit / SwiftUI import は 0 件（grep で実測）。再発防止は scripts/check-befoldkit-platform-free.sh（import の allowlist、pre-commit と CI の両方）で、AppKit を戻すと落ちることを実測で確認済み。起票時の前提「外せば Foundation のみの層になる」は成り立たず、PDFKit が残ることが実測で判明したため既知例外として記録し TASK-598 へ切り出した。swift test 1917 件 pass、xcodebuild BUILD SUCCEEDED、swiftlint 新規違反 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
