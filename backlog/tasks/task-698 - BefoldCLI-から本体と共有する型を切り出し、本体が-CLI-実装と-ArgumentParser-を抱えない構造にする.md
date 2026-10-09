---
id: TASK-698
title: BefoldCLI から本体と共有する型を切り出し、本体が CLI 実装と ArgumentParser を抱えない構造にする
status: To Do
assignee: []
created_date: '2026-10-09 13:29'
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
- [ ] #1 本体(`befold` ターゲット)が `BefoldCLI` にも ArgumentParser にも依存しない。`rg "import BefoldCLI" BefoldApp/befold` が 0 件
- [ ] #2 CLI と本体の間でやり取りする型(Wire 形式を含む)の互換性が `CLIRequestWireTests` などで保たれている
- [ ] #3 依存関係を破ると落ちる仕組み(本体から BefoldCLI への import を禁じる検査スクリプトなど。`scripts/check-befoldkit-platform-free.sh` が前例)を同じタスクに含める
- [ ] #4 `swift test` と `xcodebuild build -scheme befold` が通る(`xcodegen generate` 実施)
<!-- AC:END -->
