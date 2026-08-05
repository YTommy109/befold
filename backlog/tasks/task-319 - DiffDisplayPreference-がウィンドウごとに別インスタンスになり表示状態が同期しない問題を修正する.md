---
id: TASK-319
title: DiffDisplayPreference がウィンドウごとに別インスタンスになり表示状態が同期しない問題を修正する
status: Done
assignee: []
created_date: '2026-08-05 16:07'
updated_date: '2026-08-05 17:09'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: medium
type: bug
ordinal: 503000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

DiffDisplayPreference はアプリ全体で共有する設計（doc コメントにも「同じファイルを 2 窓で開いたときの不整合を防ぐ」旨の記載）だが、ViewerWindowManager.openViewer（ViewerWindowManager.swift:233-252）は ViewerWindowController の init へ diffDisplayPreference を渡しておらず、デフォルト引数（ViewerWindowController.swift:147 の DiffDisplayPreference()）がウィンドウごとに別インスタンスを生成している。対照的に sidebarDisplayPreference は同じ init 呼び出しで manager の共有インスタンスが明示的に渡されている。

症状: 同じ変更ありファイルを 2 窓で開き、片方で「変更を表示」（Cmd+Ctrl+J）をトグルしてももう片方に反映されない。各窓で独立にトグルすると UserDefaults への永続化が last-write-wins になり、次回起動時に復元される状態が不定になる。

修正: ViewerWindowManager に共有インスタンスを持たせ、openViewer で明示的に渡す（sidebarDisplayPreference と同じ形）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 2 窓で同じファイルを開いた状態で片方の差分表示トグルを切り替えると、もう片方にも反映される
- [x] #2 差分表示状態の永続化・復元が窓の数によらず一意に定まる
- [x] #3 共有インスタンスが渡ることを検証するテストを追加し、修正を戻すと失敗することを確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 修正

ViewerWindowManager に `diffDisplayPreference` を持たせ（init 引数 + 保持）、openViewer が全コントローラへ渡すようにした。sidebarDisplayPreference と同じ形。マネージャは 1 つなので、省略時のデフォルト引数でもマネージャ内で 1 インスタンスに揃う。

## 決めた粒度を守らせるもの（TASK-326 の項目 9）

doc コメントだけでは守られなかったのが今回の原因なので、テストを足した。ViewerWindowControllerDiffTests に「生成したウィンドウは差分表示設定を共有する」を追加し、共有インスタンスの isEnabled を直接動かして両ウィンドウが同じ答えを返すこと、および各コントローラの参照が共有インスタンスと同一（===）であることを見る。

**メニュー操作（toggleSourceDiff）経由の検証は空振りだった**: フィーチャーゲート無効ビルドでは canToggleDiff が false でトグルが効かず、両ウィンドウとも false のまま一致するため、共有していなくても通ってしまう。配線を外して落ちることを確かめる過程で発覚し、共有インスタンスを直接動かす形へ書き換えた。

## 検証

- `swift test` 1149 green
- **テストが空振りしていないことを確認**: openViewer から `diffDisplayPreference: diffDisplayPreference,` を外すと当該テストの 2 つのアサートが落ちる（`(enabled.count → 0) == (controllers.count → 2)`、`(shared.count → 0) == …`）。戻して再度 green
- swiftformat --lint: 0 件
- swiftlint: origin/main を git archive で展開して変更 4 ファイルを個別に比較し、ベースライン差分ゼロ。当初テストを ViewerWindowManagerTests へ置いたところ Type Body Length 違反が新規発生したため、関心の近い ViewerWindowControllerDiffTests へ移した

## 副産物

全体実行で CLIRequestWireIntegrationTests が落ちる事象に遭遇した。一時は本タスクの ViewerStore 変更が原因に見えたが（消すと通った）、同一ツリーで 3 回連続通過したため偶然の一致と判断し、TASK-327 として別途起票した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DiffDisplayPreference をアプリ全体で共有する設計が配線されていなかった問題を、ViewerWindowManager に保持させ openViewer で全コントローラへ渡す形で修正した（sidebarDisplayPreference と同じ形）。doc コメントだけでは守られなかったのが原因なので、共有されていることを固定するテストを追加した。検証は swift test 1149 green と、配線を外すと当該テストの 2 アサートが落ちることの実測、swiftlint ベースライン差分ゼロ。メニュー操作経由の検証はゲート無効時に空振りすると分かり、共有インスタンスを直接動かす形へ書き換えた。
<!-- SECTION:FINAL_SUMMARY:END -->
