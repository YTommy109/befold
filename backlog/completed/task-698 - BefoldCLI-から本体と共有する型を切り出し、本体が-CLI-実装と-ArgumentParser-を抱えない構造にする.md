---
id: TASK-698
title: BefoldCLI から本体と共有する型を切り出し、本体が CLI 実装と ArgumentParser を抱えない構造にする
status: Done
assignee: []
created_date: '2026-10-09 13:29'
updated_date: '2026-10-12 12:37'
labels:
  - refactor
dependencies: []
references:
  - BefoldApp/Package.swift
  - BefoldApp/project.yml
priority: low
ordinal: 887000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
本体アプリは `CLIOpenOptions` などを使うために `BefoldCLI` framework 全体に依存している。そのため ArgumentParser(`Package.swift` のコメントに「本体にも乗る」と明記)と、`NSAppleScript` を使う `CLIInstaller` まで本体のバイナリに入る。本体が使う型(`CLIOpenOptions`、`CLIRequest` など、`import BefoldCLI` している `AppDelegate`・`DocumentOpener` 等が触るもの)だけを BefoldKit 側へ移せば、コマンド定義とインストーラは CLI 側に閉じる。App Store 掲載調査(2026-10-09)で、将来 MAS 版から CLI 関連を完全に外すための構造的な障害として挙がった。MAS をやらなくても依存の整理になる。着手前に `/review-design` を回すこと(既存の共通経路に触るため)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 本体(befold ターゲット)が BefoldCLI にも ArgumentParser にも依存しない。rg "import BefoldCLI" BefoldApp/befold が 0 件
- [x] #2 CLI と本体の間でやり取りする型(Wire 形式を含む)の互換性が CLIRequestWireTests などで保たれている。固定 JSON のデコードテストを含む
- [x] #3 依存関係を破ると落ちる仕組み(本体から BefoldCLI への import と Package.swift/project.yml の依存宣言を禁じる検査スクリプト。scripts/check-befoldkit-platform-free.sh が前例)を同じタスクに含め、pre-commit と CI に組み込む
- [x] #4 swift test と xcodebuild build -scheme befold が通る(xcodegen generate 実施)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計レビュー(/review-design、2026-10-12)の結論を反映した計画。

前提と裏付け:
- 実測: import BefoldCLI している本体ファイルは befold/App 配下の 11 件。本体が使う BefoldCLI のシンボルは CLIOpenOptions / CLISortOrderOption / CLIRequest / CLIRequestWire / CLIInstaller(CLIInstallError) / AppVersion の 6 系統(rg で確認)。
- 実測: 移動対象 6 型の同名型は BefoldApp 内に無い(rg "struct|enum ..." で BefoldCLI の定義のみ)。CLIOpenOptions / CLIRequest を UserDefaults やセッションへ保存する箇所は befold 配下に無い(rg 0 件)。
- コード参照: ArgumentParser を import するのは BefoldCLICommand.swift / OpenCLIOptions.swift。Package.swift の BefoldCLI ターゲットのコメントが『本体にも乗る』と明記。
- 実測: 型グループ最大は ViewerWindowManager 335 行、AppDelegate 308 行。import の書き換えのみで増減しない。
- 未確認: befoldTests が xcodebuild 上で BefoldCLI をどう解決するか。テスト移動後に xcodebuild build-for-testing で確認する。

設計判断:
1. CLIInstaller / CLIInstallError / ShellQuoting は本体(befold/App)へ移す。NSAppleScript を使い本体メニューの実体で、CLI は使わない。タスク文の『インストーラは CLI 側に閉じる』は前提誤りだったため AC を書き換える(ユーザー承認済み)。
2. BefoldKit へ移す: CLIOpenOptions, CLISortOrderOption, CLIRequest, CLIRequestWire, AppBundle, AppVersion。import は Foundation のみで check-befoldkit-platform-free の allowlist 内。CLIRequestWire は送受で ackNotificationName 等を共有するため 1 ファイルのまま移す(private enum Key のファイルスコープ対策)。AppVersion は fallback の二重化を避けるため分割せず丸ごと移し、scripts/bump.sh の APP_VERSION_SWIFT パスを追従させる。
3. ArgumentParser 適合(extension CLISortOrderOption: ExpressibleByArgument)は BefoldCLI 側に残す。
4. 公開 API は public のまま。@testable で隠れる internal 漏れは swift build で確認。
5. 守らせる仕組み: scripts/check-app-no-cli-dependency.sh(--self-test 付き)で (a) BefoldApp/befold と BefoldRenderKit に import BefoldCLI / ArgumentParser が無い、(b) Package.swift の befold ターゲットと project.yml の befold ブロックに BefoldCLI が無い、を検査。pre-commit(setup-git-hooks.sh)と ci.yml(on.push.paths / on.pull_request.paths / 判定 grep の 3 箇所 + ステップ)に組み込む。
6. Wire 互換: 型名はワイヤに出ない。固定 JSON 文字列のデコードテストを CLIRequestWireTests に追加し、往復テストだけではフィールド名の変更を検知できない穴を塞ぐ。通知名・userInfo キー・rawValue は変更しない。
7. テスト移動: CLICheckCommand* / CLIBookmarkCommandTests は BefoldCLI の型のテストなので befoldCLITests へ。CLIInstaller*/ShellQuotingTests/AppVersionTests は移し先に合わせて import を変更。CI は befoldCLITests を別段で回す点に注意。

実装順: 型の移動と import 更新 → Package.swift/project.yml → xcodegen generate → テスト追従 → 検査スクリプト・CI・文書。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
計画からのずれ: CLICheckCommand*Tests / CLIBookmarkCommandTests は befoldCLITests へ移せなかった。DirectoryLister.resolveFileToOpen(本体)と InMemoryFileReader(befoldTests 内)を使い、移すには BefoldTestSupport に BefoldKit 依存を足す必要があり『Foundation と Testing のみ』の規約に反するため。befoldTests に残し、project.yml / Package.swift の befoldTests 依存に BefoldCLI を明示した(以前は befold 経由の推移依存)。検査スクリプトは befold ターゲットと BefoldApp/befold・BefoldRenderKit のソースだけを禁じ、テストターゲットは対象外。xcodebuild build-for-testing で befoldTests の解決を確認済み。検証: swift test --skip befoldCLITests 2040 件・336 スイート通過、swift test --filter befoldCLITests 75 件通過(私も再実行)、xcodebuild build -scheme befold BUILD SUCCEEDED、各 check-*.sh 通過、swiftlint ベースライン差分に真の新規ゼロ。既知: 初回の swift test --skip befoldCLITests が FuzzyMatcher 系テストの後で約 28 分応答せず kill した。未完了の 8 スイートの個別再実行と全体再実行は通ったが、原因は未特定(flaky か変更起因かは未確認)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
本体 befold が BefoldCLI / ArgumentParser に依存しない構造にした。共有型(CLIOpenOptions・CLISortOrderOption・CLIRequest・CLIRequestWire・AppBundle・AppVersion)を BefoldKit へ、CLIInstaller と ShellQuoting を本体へ移した。固定 JSON のデコードテストで Wire 互換を担保し、scripts/check-app-no-cli-dependency.sh(--self-test 付き)を pre-commit と CI に組み込んだ。swift test・xcodebuild build -scheme befold・各検査スクリプトで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
