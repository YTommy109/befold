---
id: TASK-432.4
title: viewer の JS を TypeScript へ段階移行する
status: To Do
assignee: []
created_date: '2026-08-10 12:57'
updated_date: '2026-08-10 12:58'
labels: []
dependencies:
  - TASK-432.3
parent_task_id: TASK-432
priority: low
type: chore
ordinal: 112400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
バンドル基盤とモジュール分割が済んだ後、`allowJs` を使ってファイル単位で TypeScript へ移行する。

## 型付けの価値が高い箇所

- Swift ↔ JS のブリッジ契約。`BefoldKit/ViewerBridge.swift`（374 行 + `+Diff.swift` / `+PayloadKeys.swift`）が単一情報源で、JS→Swift の 7 メッセージ、Swift→JS の引数なし関数 9 個、注入グローバル 8 個（`_mmdInitialZoom` / `_mmdHostFeatures` / `_mmdBannerStrings` / `_mmdInitialFindOptions` ほか）を定義している。JS 側は `viewer-main.js:2-8` の `_MSG_*` 定数と `:75, 84, 93, 102, 185, 889, 977, 985, 1360` の読み取りで対応しており、現状は文字列の一致を `ViewerBridgeContractTests` がソーステキストの照合で担保している。
- 表示モード・レンダラの分岐（TASK-414 の乖離が起きた箇所）。

## 決めること

- ブリッジ契約の型を手書きするか、`ViewerBridge.swift` から生成するか。生成なら生成物のズレ検証が要る（TASK-432.1 で入れる一致検証と同じ仕組みに乗せられる）。
- strict の度合いと、移行途中の混在をどう扱うか。
- `site/` は TypeScript 5.7 + vitest を使っている。バージョンや設定を揃えるか、独立させるか。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TypeScript のビルドと型検査が npm スクリプトから実行できる
- [ ] #2 型検査が CI で実行され、エラーで落ちる
- [ ] #3 少なくともブリッジ契約に関わるモジュールが TypeScript へ移行されている
- [ ] #4 ブリッジ契約の型を手書きするか生成するかの判断が理由つきで記録されている
- [ ] #5 既存テストが通り、ケース数が減っていない
<!-- AC:END -->
