---
id: TASK-315.3
title: 左右分割の差分レイアウトと表示切り替え UI を追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-05 14:46'
updated_date: '2026-08-05 15:46'
labels: []
dependencies:
  - TASK-315.2
parent_task_id: TASK-315
priority: medium
type: task
ordinal: 516000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 の 3 段目。インライン差分（2 段目）に加えて左右分割（side-by-side）を実装し、ユーザーが切り替えられるようにする。

論点:

- 切り替えの入口（表示メニュー / ツールバー / ショートカット）。既存のソース表示・行番号は `MainMenuBuilder.swift:177,181-182` と `ViewerToolbarController.swift` に入口がある
- 状態の持ち方（per-file の `SourceModeStore` 相当か、ウィンドウ/アプリ全体か）
- フォルダー提示中に操作が届かないこと。能力判断は `ViewerCapabilities` に集約済み（TASK-271）で、validateMenuItem・ツールバー・実行側がすべて同じ導出を見る
- FeatureGate: 機能ごとの別名プロパティを足し、`FeatureGate.swift` の露出点列挙コメントを更新する。`FeatureGateEnumerationTests` がソース走査と列挙を突き合わせるため、更新漏れはテストで落ちる
- コミットには `(gate)` スコープを付ける
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 左右分割レイアウトで、対応する行が左右で揃って表示される
- [x] #2 左右分割とインラインをユーザーが切り替えられ、切り替え結果が意図した粒度で永続化される
- [x] #3 フォルダー提示中は差分表示の操作がメニュー・ツールバーのいずれからも実行されない
- [x] #4 FeatureGate 配下で dev/DEBUG のみ露出し、露出点列挙と FeatureGateEnumerationTests が更新されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-06）

TASK-315.2 から移した Swift 配線と、左右分割・トグル UI をまとめて実装した。

### JS
- `viewer.js`: `pairDiffLines`（連続する削除と追加を対にし、数が揃わない側は空マスで埋める）、`renderSideBySideDiffHtml`、レイアウト選択を閉じる `renderDiffHtml`
- `viewer-main.js`: `setDiffLayout(layout)`（`setDiff` と同じく状態を持つだけ）
- `style.css`: 左右 2 マス + 入れ子テーブルで桁を揃える。対応行が無い側は `--diff-empty-bg` で薄く塗る

### Swift
- `ViewerBridge+Diff.swift`（新規）: `DiffLayout` と `setDiff` / `setDiffLayout` のスクリプト生成。差分本文は render と同じ JSON エンコードでエスケープする
- `ViewerRenderer`: `diffState`（本文 + レイアウト）をレンダラの設定として持ち、描画済みミラーと違うときだけ 2 つのスクリプトを送る
- `DiffDisplayPreference.swift`（新規）: ON/OFF とレイアウトを UserDefaults へ。粒度はアプリ全体（per-file の SourceModeStore には載せない）
- `ViewerWindowController+Diff.swift`（新規）: 差分取得（`GitDiffLoader`）とトグル。取得は非同期のため、着地時に URL 一致を確認してから store へ反映する
- `ViewerCapabilities.canToggleDiff` を追加し、メニュー検証・実行ガードの双方がそこだけを見る
- `MainMenuBuilder`: 「変更を表示」(⌃⌘J) / 「差分を左右に並べる」(⇧⌃⌘J)。ゲート無効時は項目を足さない
- `FeatureGate.isSourceDiffEnabled` を追加し、露出点 3 箇所を doc コメントへ列挙（`FeatureGateEnumerationTests` が突合）

### 単純化（当初案からの変更）
`updateContent` の再描画判定は、当初 `|| diffState != rendered.diffState` を足す形にしたが SwiftLint の関数長を超えた。フィールドを並べる比較をやめ、**描画済みミラーと同じ形の値を組んで丸ごと比較**する形へ置き換えた（`RenderedStateMirror: Equatable`）。列挙だと、ミラーへフィールドを足したときに判定側の追加だけ漏れて「状態は変わったのに再描画されない」穴が空く。

## 検証

- `swift test` 1057 green / jest 368 green / markdownlint 0 件 / `webview-smoke` PASS
- swiftlint: 新しい違反の種類・ファイルはゼロ。既存違反の行数カウントのみ増減（ViewerBridge の file_length 超過と MainMenuBuilder の関数長増は、`ViewerBridge+Diff.swift` 分離と `addDiffItems` 抽出で解消済み）
- **実機で両レイアウトを確認**（dev ビルド、`sample/diff-demo.swift` を編集した状態）。インライン: ハンクヘッダー・2 本のガター・+/- 記号・緑/赤のティント・シンタックスハイライトが同時に成立。左右分割: 対応する行が左右で揃い、片側にしか無い行は反対側が空マスになる
- **@Observable の要否を実測で確認**: `DiffDisplayPreference` を `@Observable` にしないと、レイアウトを切り替えても UserDefaults は `side-by-side` になるのに描画はインラインのままだった（SwiftUI が再評価しない）。付けると切り替わる。doc コメントにこの理由を記録した
- 目視確認に使ったサンプルファイルはコミットに含めていない（差分を出すには編集済みである必要があり、リポジトリに置いても再現しないため）

## 積み残し（次段の候補）

差分が取れない理由（未追跡・バイナリ・大きすぎる・変更なし）は現状すべて通常のソース表示へ落としており、理由の表示分けはしていない。ユーザーが「差分を表示」を ON にしたのに何も変わらないケースが残る。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
左右分割レイアウトと表示切り替え UI を追加し、TASK-315.2 から移した Swift 配線（ブリッジ・レンダラ・設定・取得）も併せて実装した。左右分割は連続する削除と追加を対にして並べ、片側にしか無い行は空マスで埋める。トグルは ViewerCapabilities.canToggleDiff だけを見るため、フォルダー提示中はメニューからも実行側からも効かない。設定はアプリ全体の粒度で UserDefaults に永続化する。再描画判定はフィールドの列挙をやめ、描画済みミラー同士の比較へ単純化した。検証は swift test 1057 / jest 368 / webview-smoke PASS に加え、実機での両レイアウトの目視確認と、@Observable が無いと描画が切り替わらないことの実測。
<!-- SECTION:FINAL_SUMMARY:END -->
