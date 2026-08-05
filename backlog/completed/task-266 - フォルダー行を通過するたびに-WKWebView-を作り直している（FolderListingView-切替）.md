---
id: TASK-266
title: フォルダー行を通過するたびに WKWebView を作り直している（FolderListingView 切替）
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-03 13:32'
updated_date: '2026-08-03 15:00'
labels:
  - performance
dependencies: []
priority: medium
ordinal: 457000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-265 の GUI 実測（sample 1ms）で判明した残コスト。サイドバーの選択が file 行と folder 行の間で切り替わるたび、ViewerContentView がプレビュー領域を差し替え、ViewerWebView.makeNSView が呼ばれて WKWebView を作り直している。backlog/ で tasks 行を 24 回往復した 4 秒のサンプルで、メインスレッドの 209 サンプルがここに出た（同サンプルの FileListEntryRow.body は 189）。

TASK-265（URL の正規化ハッシュ）とは別原因で、そちらの修正後も残る。フォルダー選択時に WKWebView を破棄せず保持したまま隠す等で避けられる見込み。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フォルダー行と file 行を往復しても WKWebView が作り直されない
- [x] #2 同一手順の sample で ViewerWebView.makeNSView のメインスレッド占有が有意に減ることを実測で示す
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装と実測（2026-08-03）

### 変更
ViewerContentView.body の switch をやめ、ViewerWebView を常にビュー階層に置いたまま、フォルダー表示のときだけ FolderListingView を上に重ねる（filePreview を opacity 0 / accessibilityHidden / allowsHitTesting(false) にする）。テキスト↔バイナリ切替で既に採っていた「ビュー同一性を保つ」やり方をフォルダー切替にも広げた形で、専用の状態は増やしていない。分岐は PreviewTarget.folderURL に集約。

### 実測 1: 切り替え反映のレイテンシ（AX でサイドバー行を 20 回切替、web area の有無が反転するまでの実時間）
| | median | p90 | max |
|---|---|---|---|
| 修正前 | 201.6 / 195.3 ms | 220 ms | 228 ms |
| 修正後 | 78.1 / 76.2 ms | 85 ms | 90 ms |

（各 2 回実行。約 2.6 倍速い）

### 実測 2: sample（5 秒・24 回切替・各 3 回実行）
ViewerWebView.makeNSView / ViewerRenderer.makeWebView のメインスレッド占有: **440〜470 サンプル → 0**。

注意: 同じ sample のメインスレッド busy 合計は 999 → 1423 サンプルと**増えて見える**が、これは測定の artifact。駆動側が 150ms 固定間隔で選択を変えるのに対し、修正前は 1 回の切替に約 200ms かかって追従できず、更新が畳まれて仕事が減っていたため。ユーザーが待たされる量は実測 1 のレイテンシが表す。

### 常駐化に伴う挙動の作り込み（サブエージェント調査で発見）
フォルダー表示中に印刷・検索・ズームが効かなかったのは、WKWebView が破棄されて weak proxy が nil になる**偶然の no-op** に依存していた。常駐化するとこれが消え、見えていない前ファイルが印刷される等が起きる。WebViewCommandController に isPreviewingFolder を注入して canOperateOnVisibleDocument に判断を集約し、print / find / zoom を止め、ViewerWindowController.validateMenuItem も同じ判断で無効化する（グレーアウトして見える）。設定反映（applyStoredZoom / applyCodeFont）は止めない — 止めるとフォルダーを見ている間の設定変更が常駐 WebView に入らないまま取り残されるため。

### 確認済み
- swift test 1011 tests / 151 suites green（フォルダー表示中に文書操作を許さないテスト、PreviewTarget.folderURL のテストを追加）
- swiftlint: main とのベースライン差分は既存 2 件の行数カウントのみで新規警告なし
- xcodebuild build -scheme befold 成功
- AX でフォルダー行選択時に一覧（4 行）が描画されることを確認済み
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWebView を常駐させ、フォルダー一覧を上に重ねる形に変更した。AX による 20 回切替の実測でレイテンシ中央値 201.6ms → 78.1ms（p90 220 → 85ms）、5 秒 sample の makeNSView 占有は 440〜470 サンプル → 0（各 3 回実行）。常駐化で復活してしまう「フォルダー表示中の印刷・検索・ズーム」は WebViewCommandController の canOperateOnVisibleDocument に判断を集約して止め、メニューの有効状態も揃えた。swift test 1011 green / swiftlint ベースライン差分なし / xcodebuild 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
