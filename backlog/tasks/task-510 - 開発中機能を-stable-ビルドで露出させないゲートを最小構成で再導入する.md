---
id: TASK-510
title: 開発中機能を stable ビルドで露出させないゲートを最小構成で再導入する
status: To Do
assignee: []
created_date: '2026-08-17 08:38'
labels: []
milestone: m-6
dependencies: []
priority: medium
type: task
ordinal: 710500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

`FeatureGate` 機構は `9a1ef1fc chore: 配布サイトを独自ドメインへ移行し FeatureGate 機構を撤去する (#518)` で撤去された。撤去理由はコミットメッセージに「stable リリースを行わない方針のため、ゲートによる『stable では露出しない』場合分けはコード・テスト・規約の三重の維持コストだけが残っていた」と記録されている。

その後 stable リリースを行う運用に戻っており（`CHANGELOG.md` の v1.14.0、`project.yml:31 MARKETING_VERSION: "1.14.0"`）、TASK-485（文書内ジャンプ）を「安定稼働するまで stable に載せない」形で進めるための土台が現在は無い。

## このタスクでやること

撤去前の `FeatureGate`（`git show 9a1ef1fc^:BefoldApp/befold/App/FeatureGate.swift` で読める）を**最小構成で**復活させる。撤去理由だった維持コストのうち、コード以外の 2 つ（swiftlint custom rule / commit-msg フックの `(gate)` スコープ規定）は**復活させない**。

- 判定の中身は撤去前と同じでよい: `isDebugBuild || AppVersion.isPrerelease(version)`。`AppVersion.isPrerelease` は現存する（`BefoldApp/BefoldCLI/AppVersion.swift:14`）
- ゲート対象は当面 TASK-485 の文書内ジャンプ 1 つだけ。機能ごとの名前付きプロパティを経由する形は踏襲する
- 撤去前にあった `FeatureGateEnumerationTests`（doc コメントの露出点列挙とソース走査の突き合わせ）を戻すかは、露出点が少ないうちは過剰になりうるため実装時に判断し、判断理由を Implementation Notes に残す

## 未確認の前提

現在の `MARKETING_VERSION` は `1.14.0` でプレリリース接尾辞が無い。したがって **Release ビルドではゲートが閉じる**。develop チャンネル向けの配布ビルドが `v1.x.y-dev.N` タグから MARKETING_VERSION を注入しているか（`AppVersion.swift:12-14` のコメントは `release.yml` がそうすると書いている）を、実装前に `.github/workflows/release.yml` で裏取りすること。ここが成立していないと「dev ビルドでだけ有効」が実現しない。

## JS 側へ伝える経路

viewer-src 側でゲートが必要になる場合、現存する唯一の経路は `ViewerBridge.hostFeaturesScript(...)` → `window._mmdHostFeatures` → `viewer-src/bridge.ts:54 isHostFeatureEnabled`。キーを足す場合は契約テスト `befoldTests/ViewerBridgeContractTests.swift:57` と同じ形で担保する。ただし Swift 側でメニュー・コマンドを塞げば JS へ届かないため、**JS 側までゲートを伸ばす必要があるかは実装時に判断する**。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 撤去前と同じ判定（DEBUG ビルド または プレリリースバージョン）でゲートの可否が決まる
- [ ] #2 純粋判定関数にユニットテストがあり、stable 相当のバージョン + 非 DEBUG で false になることを検証している
- [ ] #3 develop チャンネル向け配布ビルドでゲートが開くことが、release.yml のバージョン注入経路の確認をもって示されている（成立しない場合はその事実と代替案が Notes にある）
- [ ] #4 swiftlint custom rule と commit-msg フックの (gate) スコープ規定は復活していない
<!-- AC:END -->
