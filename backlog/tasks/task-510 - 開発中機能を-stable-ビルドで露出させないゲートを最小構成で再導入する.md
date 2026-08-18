---
id: TASK-510
title: 開発中機能を stable ビルドで露出させないゲートを最小構成で再導入する
status: Done
assignee: []
created_date: '2026-08-17 08:38'
updated_date: '2026-08-17 08:41'
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
- [x] #1 撤去前と同じ判定（DEBUG ビルド または プレリリースバージョン）でゲートの可否が決まる
- [x] #2 純粋判定関数にユニットテストがあり、stable 相当のバージョン + 非 DEBUG で false になることを検証している
- [x] #3 develop チャンネル向け配布ビルドでゲートが開くことが、release.yml のバージョン注入経路の確認をもって示されている（成立しない場合はその事実と代替案が Notes にある）
- [x] #4 swiftlint custom rule と commit-msg フックの (gate) スコープ規定は復活していない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- `BefoldApp/befold/App/FeatureGate.swift` を新規追加。判定は撤去前と同じ `isDebugBuild || AppVersion.isPrerelease(version)`。
- `BefoldApp/befoldTests/FeatureGateTests.swift` を撤去前の内容そのまま復元（3 テスト）＋ 名前付きプロパティが共通判定と一致することを確かめる 1 テストを追加。
- ゲート対象は `isDocumentJumpEnabled`（TASK-485 の文書内ジャンプ）1 つのみ。露出点は 485.1 以降で配線する。

## dev ビルドでゲートが開くことの裏取り（実測: ワークフローの記述）

- `.github/workflows/release.yml:104` が `MARKETING_VERSION="${GITHUB_REF_NAME#v}"` を xcodebuild へ注入する。
- 同 `:216` が `prerelease: ${{ contains(github.ref_name, '-') }}` で prerelease を判定する。
- よって `v1.15.0-dev.1` タグのビルドは `1.15.0-dev.1` を名乗り `AppVersion.isPrerelease`（`BefoldApp/BefoldCLI/AppVersion.swift:14`）が true になる。stable タグ `v1.15.0` では false。
- 現在の `project.yml:31 MARKETING_VERSION: "1.14.0"` はプレリリースではないため、手元の Release ビルドではゲートは閉じる（DEBUG ビルドでのみ開く）。これは意図どおり。

## FeatureGateEnumerationTests を戻さない判断

撤去前は doc コメントの露出点列挙とソース走査を突き合わせるテストがあったが、戻していない。理由は、露出点が現時点で 0、当面も文書内ジャンプの数箇所に留まり、列挙を機械照合する利得より維持コストが上回るため。露出点が 3 機能・10 箇所規模へ戻った時点で再検討する。

## 撤去理由（#518）との関係

撤去コミット `9a1ef1fc` は「stable リリースを行わない方針のため」ゲートが不要と判断していた。その後 stable リリースを行う運用に戻っている（`CHANGELOG.md` の v1.14.0）ため、前提が変わったことによる再導入である。撤去時に挙げられた三重の維持コストのうち、swiftlint custom rule と commit-msg フックの `(gate)` スコープ規定は復活させていない。

## 検証

- `swift build` 成功。
- `swift test --filter FeatureGate` → 2 suites / 4 tests すべて passed。
- swiftlint（プラグイン同梱バイナリを `BefoldApp/` を CWD にして実行）54 件。FeatureGate 由来の指摘は 0 件。既存ファイルは 1 つも変更していないため main とのベースライン差分はゼロ。
- swiftformat（fix モード）で整形差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FeatureGate を最小構成（共通判定 + 文書内ジャンプ用の名前付きプロパティ 1 つ）で再導入し、撤去前のテスト 3 件を復元して 1 件追加した。dev ビルドで開くことは release.yml のバージョン注入経路（:104 / :216）で裏取り済み。swift test --filter FeatureGate が 4 件 passed、swiftlint は新規ファイル由来 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
