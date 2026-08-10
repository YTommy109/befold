---
id: TASK-432.1
title: esbuild のビルド経路と成果物コミットの仕組みを最小構成で通す
status: To Do
assignee: []
created_date: '2026-08-10 12:56'
labels: []
dependencies: []
parent_task_id: TASK-432
priority: medium
type: chore
ordinal: 112100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
既存の JS には触れず、「ソースをビルドして成果物を生成し、それをコミットし、ズレを CI で落とす」という経路だけを最小のエントリで先に通す。リスクの高い未知（SPM のリソース解決・成果物の配置・CI の一致検証）を、2,800 行の JS を動かす前に潰すのが目的。

## 背景（実測）

- `BefoldApp/package.json` には `test: jest` しか無く、ビルドスクリプトは存在しない。`dependencies` セクションも無い。
- `BefoldApp/Package.swift:29-40` はリソースを `.copy` で 12 個個別に列挙している。SPM のビルド時点でファイルが存在している必要がある。
- `BefoldApp/project.yml` は `BefoldKit/Resources` をディレクトリごと resources ビルドフェーズに入れている（個別列挙ではない）。両者で追随の要否が異なる点に注意。
- `project.yml` に preBuildScripts / postCompileScripts / postBuildScripts は無く、生成済み `project.pbxproj` の `PBXShellScriptBuildPhase` は 0 件。
- `.github/workflows/ci.yml:72-105` の macOS ジョブに `setup-node` は無い。Node があるのは `:107-131` の js-test（ubuntu、Node 24、`npm ci`）だけ。
- `.gitignore` に `dist` 相当の記載は無い。`node_modules` は `BefoldApp/node_modules/` と `site/node_modules/` のフルパス 2 件で指定されている。

## 決めること（実装者が判断し Implementation Notes に残す）

- **成果物の置き場**: `BefoldKit/Resources/` へ直接出すか、`dist/` 等を経由してコピーするか。`Package.swift` の個別列挙と `project.yml` のディレクトリ指定の両方で成立する形にすること。
- **ソースの置き場**: 現行の `BefoldKit/Resources/*.js` をソースのまま残すか、`src/` 等へ移すか。移す場合、`Package.swift` の `exclude` と `project.yml` の `excludes` の両方に反映が要る。
- **一致検証の方法**: 再ビルドして `git diff --exit-code` を見るのが素直。ローカルでも同じコマンドで確認できる形にする。
- **Node バージョンの固定**: `.nvmrc` / `engines` は現在存在しない。CI は Node 24 固定なので、ローカルとの整合を保つ手段を用意するか、しない判断を記録する。

## 検証の要件

`swift build` と `xcodebuild build -scheme befold` の両方が通ること。SPM 経路と Xcode 経路でリソースの入り方が違うため、片方だけの確認では足りない（`.claude/CLAUDE.md` の「swift build は通るが xcodebuild だけが落ちる」の項）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 npm スクリプトから esbuild でバンドルを生成できる
- [ ] #2 生成された成果物がリポジトリにコミットされ、.app バンドルへ同梱される
- [ ] #3 CI がソースからの再ビルド結果とコミット済み成果物の不一致を検出して失敗する
- [ ] #4 swift build と xcodebuild build -scheme befold の両方が通る
- [ ] #5 このサブタスクの時点で viewer.js / viewer-main.js の中身は変更されておらず、表示の振る舞いが変わっていない
- [ ] #6 成果物とソースの置き場・一致検証の方法・Node バージョン固定の判断が理由つきで記録されている
<!-- AC:END -->
