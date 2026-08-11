---
id: TASK-432.1
title: esbuild のビルド経路と成果物コミットの仕組みを最小構成で通す
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 12:56'
updated_date: '2026-08-11 12:53'
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
- [x] #1 npm スクリプトから esbuild でバンドルを生成できる
- [x] #2 生成された成果物がリポジトリにコミットされ、.app バンドルへ同梱される
- [x] #3 CI がソースからの再ビルド結果とコミット済み成果物の不一致を検出して失敗する
- [x] #4 swift build と xcodebuild build -scheme befold の両方が通る
- [x] #5 このサブタスクの時点で viewer.js / viewer-main.js の中身は変更されておらず、表示の振る舞いが変わっていない
- [x] #6 成果物とソースの置き場・一致検証の方法・Node バージョン固定の判断が理由つきで記録されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldApp/viewer-src/ に最小エントリ(index.js + 分割モジュール)を置く。既存 Resources/*.js には触れない
2. esbuild を devDependencies へ追加し、npm scripts build:viewer / check:viewer-bundle を用意する
3. 成果物は BefoldKit/Resources/viewer-bundle.js へ出力してコミットする（project.yml は Resources ディレクトリ指定なので追随不要、Package.swift は .copy を 1 行追加）
4. .nvmrc / engines で Node 24 を固定し CI と揃える
5. CI の js-test ジョブへ再ビルド差分検出ステップを追加する
6. swift build と xcodebuild build -scheme befold の両方を通し、.app 内に成果物が入ることを確認する
7. 判断理由を Implementation Notes に記録する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決めたこととその理由

- **ソースの置き場: `BefoldApp/viewer-src/`（ターゲット path の外）**。`BefoldKit/` 配下に置くと SPM の `exclude` と project.yml の `excludes` の両方に追随が要る（Package.swift:38 の `exclude: ["Resources/__tests__"]` / project.yml:56 の `excludes: ["__tests__/**"]` と同型の二重管理）。外に出せばどちらも不要。実測: この構成で `swift build`（unhandled resource 警告なし）と `xcodebuild build -scheme befold` の両方が成功し、生成された .app に viewer-src は含まれていない（`find befold.app -name index.js` が 0 件）。
- **成果物の置き場: `BefoldKit/Resources/viewer-bundle.js` へ直接出力**。dist/ を経由してコピーする段を挟むと、コピー漏れという新しい失敗モードが増えるだけで得がない。Package.swift へ `.copy` を 1 行追加、project.yml は Resources をディレクトリごと指定しているため変更不要。
- **成果物をコミットする理由**: macOS の build-and-test ジョブに setup-node が無く、ビルド時に Node を要求すると SPM/Xcode の全ビルド経路が Node 依存になる。ズレの検出は ubuntu の js-test ジョブで行う。
- **一致検証: `npm run check:viewer-bundle`**（再ビルド → `git diff --exit-code -- BefoldKit/Resources/viewer-bundle.js`）。CI とローカルで同一コマンド。実測: 同期時 exit 0、viewer-src/bundle-marker.js の文字列を 1 箇所変えた状態で exit 1。
- **Node バージョン固定: `.nvmrc`（24）+ package.json の `engines.node: ">=24"`**。CI が Node 24 固定なので、ローカルだけ別メジャーで esbuild の出力が変わると差分検出が誤発火する。esbuild は exact 版指定（0.28.2）。

## 検証

- `swift build`: Build complete。`.build/debug/befold_BefoldKit.bundle/` に viewer-bundle.js を確認
- `xcodebuild build -scheme befold`: BUILD SUCCEEDED。`befold.app/Contents/Frameworks/BefoldKit.framework/Versions/A/Resources/viewer-bundle.js` を確認
- `npx jest`: 417 passed / 6 suites（既存 JS 無変更）
- `git diff` 上、viewer.js / viewer-main.js に変更なし
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer-src/ のモジュールソースを esbuild でバンドルし、成果物 BefoldKit/Resources/viewer-bundle.js をコミットして .app へ同梱する経路を最小構成で通した。ソースは SPM/XcodeGen 双方の除外設定を増やさないようターゲット path の外へ置き、ズレは CI の js-test ジョブで npm run check:viewer-bundle により検出する。swift build / xcodebuild build -scheme befold の両方の成功と .app 内への同梱、staleness 検出の exit 1、既存 Jest 417 件の pass で検証した。既存 viewer.js / viewer-main.js は無変更。
<!-- SECTION:FINAL_SUMMARY:END -->
