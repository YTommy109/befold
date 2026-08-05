---
id: TASK-315
title: ソース表示中に git 差分を GUI 表示する（左右分割・インラインの 2 レイアウト）
status: Done
assignee: []
created_date: '2026-08-05 14:45'
updated_date: '2026-08-05 15:46'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 513000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ソースコードモードで表示しているファイルに git の未コミット変更があるとき、一般的なエディタと同様の差分 GUI を出す。レイアウトは「左右分割（side-by-side）」と「分割せず 1 列に追加・削除を並べるインライン（line-by-line）」の 2 種類を用意し、切り替えられるようにする。

FeatureGate 配下の機能として実装する（dev/DEBUG のみ露出）。

## 方針（2026-08-05 の調査で決定）

外部ライブラリ（diff2html 等）は導入せず、`git diff` の unified diff を自前でパースし、既存のソース表示の DOM 構造へ載せる。理由:

- ソース表示は行番号 OFF のときも常に `<table class="code-table">` の 1 行 = 1 `<tr>` 構造を使っている（`BefoldApp/BefoldKit/Resources/viewer.js:310 buildLineNumberRows` / `:324 wrapWithLineNumbers` / `:334 renderCodeHtml`。行番号 OFF でもテーブルなのはインデントガイド描画のため）。差分の行種別（追加・削除・文脈）を付ける先として素直で、行番号・インデントガイド・hljs テーマ・既存の検索がそのまま効く
- diff2html（3.4.56 / MIT、`diff2html.min.js` 76K + CSS 17K）は両レイアウトを設定 1 つで出せるが、独自 DOM・独自 CSS のため上記が効かず、手動ベンダリング対象（`/check-vendored-deps` の監査対象）が 1 つ増える

## 調査で確認済みの前提

- git 実行は `GitCommandRunner`（`BefoldApp/befold/App/GitCommandRunner.swift:105`）に一元化されており、任意の引数を渡せる。無害化オプション・環境変数固定・10 秒タイムアウト・プロセスグループ SIGKILL 済み
- **差分本文を取る実装は現状 1 つも無い**。既存の 8 コマンドはすべてメタデータのみで、`git diff` も `--name-status` でパス名しか取っていない（`GitStatusReader.swift:100-102`）
- git 実行はメインアクター外が契約（`GitStatusReader.swift:26-29`）。`GitStatusStore` は detached + inFlight 畳み込み + `.git/index` の fingerprint キャッシュ（`GitStatusStore.swift:39-121`）
- ソースモードの伝達は Swift → `setViewMode('source')`（`ViewerBridge.swift:232`）→ 直後に render の二段構え。JS 側の実描画は `viewer-main.js:1657 _renderSource`
- CSP は `script-src 'self'` / `connect-src 'none'`（`viewer.html:19`）。同梱ローカル JS のみ可
- JS のユニットテストは jest（`BefoldApp/BefoldKit/Resources/__tests__/`）

## 設計上の論点（着手時に /review-design で潰す）

- 何と比較するか（作業ツリー vs HEAD / インデックス）。ステージ済みと未ステージをどう見せるか
- 未追跡ファイル・バイナリ・巨大ファイルの扱い（ソース表示はチャンク読み込みと truncation を持つ）
- QuickLook 拡張では git を叩かない（`RendererFeatures` / `allowsInteractiveBridging`）
- 差分表示の状態をどこに持つか（per-file の SourceModeStore 相当か、ウィンドウ/アプリ全体か）
- フォルダー提示中の扱い（`ViewerCapabilities` の導出に合わせる）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ソース表示中のファイルに未コミット変更があるとき、差分が GUI で表示される
- [x] #2 左右分割とインラインの 2 レイアウトを切り替えられる
- [x] #3 行番号・インデントガイド・シンタックスハイライト・検索が差分表示中も従来どおり効く
- [x] #4 FeatureGate 配下で dev/DEBUG のみ露出し、FeatureGate.swift の露出点列挙とテストが更新されている
- [x] #5 git 実行がメインアクター外で行われ、差分取得の失敗・タイムアウト時に表示が壊れない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
3 つのサブタスク（315.1 取得 / 315.2 インライン描画 / 315.3 左右分割と UI）で実装完了。実機で両レイアウトを確認済み。差分が取れない理由の表示分けは未実施（315.3 の Notes に積み残しとして記録）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ソース表示中に git 差分を GUI 表示する機能を FeatureGate 配下で実装した。外部ライブラリは導入せず、git diff HEAD の unified diff を自前でパースし、既存のソース表示と同じ code-table 構造へ載せることで、行番号・インデントガイド・シンタックスハイライト・検索がそのまま効く。インラインと左右分割の 2 レイアウトを View メニューから切り替えられ、設定はアプリ全体で永続化する。検証は swift test 1057 / jest 368 / webview-smoke PASS と、実機での両レイアウトの目視確認。
<!-- SECTION:FINAL_SUMMARY:END -->
