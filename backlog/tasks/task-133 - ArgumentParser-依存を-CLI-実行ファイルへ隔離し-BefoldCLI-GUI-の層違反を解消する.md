---
id: TASK-133
title: ArgumentParser 依存を CLI 実行ファイルへ隔離し BefoldCLI/GUI の層違反を解消する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-24 22:40'
updated_date: '2026-07-25 02:02'
labels:
  - refactor
  - structural
  - cli
dependencies: []
priority: high
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldCLI/CLIOpenOptions.swift が import ArgumentParser し、OpenCLIOptions(ParsableArguments)・4 つの EnumerableFlag 実装・CLISortOrderOption の ExpressibleByArgument 適合を抱えるが、これらは befold-cli/BefoldCLICommand.swift の 1 箇所からしか使われない。共有ライブラリ BefoldCLI に CLI 専用のパース層が同居するため、GUI ターゲット befold も import BefoldCLI 経由で ArgumentParser を推移的にリンクし、さらに Package.swift/project.yml で GUI が ArgumentParser を直接依存しているが GUI コードは ArgumentParser を一切使っていない(dead dependency)。dagayn の SAP 指摘(BefoldCLI distance=1.0, pain zone)の一因。構造レビュー(2026-07-25)で検出。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OpenCLIOptions と 4 つの *Flag enum・CLISortOrderOption の ExpressibleByArgument 適合が befold-cli ターゲットへ移動している
- [x] #2 CLIOpenOptions(素の Codable 構造体)と CLISortOrderOption 本体は BefoldCLI に残り、BefoldCLI から import ArgumentParser が消えている
- [x] #3 GUI(befold)と BefoldCLI の ArgumentParser 直接依存が Package.swift / project.yml から除去され、swift build・swift test・xcodebuild が通る
- [x] #4 CLI の --help / 各フラグ挙動に回帰がない(既存 CLI テストが通る)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldCLI/CLIOpenOptions.swift から ArgumentParser 依存部を befold-cli/OpenCLIOptions.swift へ移動する（OpenCLIOptions・HiddenFilesFlag・LineNumbersFlag・SidebarVisibilityFlag・SourceModeFlag、および CLISortOrderOption の ExpressibleByArgument 適合を extension 化して移す）
2. BefoldCLI/CLIOpenOptions.swift から import ArgumentParser と ExpressibleByArgument 適合を削除する（CLIOpenOptions と CLISortOrderOption 本体は BefoldCLI に残す）
3. Package.swift の BefoldCLI ターゲットと befold(GUI)ターゲットから ArgumentParser 依存を除去する
4. project.yml の BefoldCLI と befold ターゲットから swift-argument-parser 依存を除去する
5. swift build / swift test を実行し、既存 CLI テスト(BefoldCLICommandTests の parseAsRoot 系)で回帰がないことを確認する
6. xcodegen generate + xcodebuild build でも通ることを確認する
7. befold-cli --help の出力(--sort の候補値表示を含む)が変化していないことを確認する

単純化の検討: OpenCLIOptions は参照が 1 箇所のみのため BefoldCLICommand へインライン展開する案も検討したが、EnumerableFlag 4 種と合わせて 100 行超がコマンド定義に混ざり凝集度が下がるうえ、AC #1 が移動を要求しているため型構成は変えず配置のみ移す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証結果:
- swift build: 成功（全ターゲット）
- swift test: 615 tests / 86 suites すべて成功
- xcodegen generate + xcodebuild build -scheme befold: BUILD SUCCEEDED
- befold-cli --help の出力を変更前後で diff → 差分なし（--sort の候補値 'folders-first, alphabetical' 表示も維持）
- rg 'ArgumentParser' BefoldCLI/ befold/ → 参照なし
- 生成された befold.xcodeproj の各ターゲットのリンク先を pbxproj から抽出して確認:
  befold          -> BefoldKit, BefoldRenderKit, BefoldCLI, Sparkle
  BefoldCLI       -> BefoldKit
  befold-cli      -> BefoldCLI, BefoldKit, ArgumentParser
  BefoldRenderKit -> BefoldKit
  befoldTests     -> BefoldKit, BefoldRenderKit
  → ArgumentParser のリンクが befold-cli のみに閉じ、GUI への推移的リンクが解消したことを確認

設計判断: OpenCLIOptions は参照が BefoldCLICommand の 1 箇所のみのため同コマンドへインライン展開する案も検討したが、EnumerableFlag 4 種と合わせて 100 行超がコマンド定義に混ざり凝集度が下がるため、型構成は変えず befold-cli/OpenCLIOptions.swift へ配置のみ移した。CLISortOrderOption の ExpressibleByArgument 適合は型本体から切り離し、befold-cli 側の空 extension で与えている（RawValue == String + CaseIterable のため既定実装のみで help の候補値表示も維持される）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BefoldCLI に同居していた ArgumentParser 依存のパース層（OpenCLIOptions・EnumerableFlag 4 種・CLISortOrderOption の ExpressibleByArgument 適合）を befold-cli/OpenCLIOptions.swift へ移設し、Package.swift と project.yml から GUI(befold) と BefoldCLI の ArgumentParser 直接依存を除去した。CLIOpenOptions と CLISortOrderOption 本体は共有ライブラリ BefoldCLI に残る素の Codable のままで、CLI 引数としての解釈だけが実行ファイル側に閉じる。検証は swift build / swift test（615 tests 全通過）/ xcodegen + xcodebuild（BUILD SUCCEEDED）に加え、--help 出力の変更前後 diff が差分なしであること、および生成 pbxproj のリンク先抽出で ArgumentParser が befold-cli のみにリンクされることを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
