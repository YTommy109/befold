---
id: TASK-270
title: ウィンドウを開いた最初のファイルで保存倍率が復元されない（TASK-266 の回帰）
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-03 15:21'
updated_date: '2026-08-04 00:08'
labels:
  - bug
  - regression
dependencies: []
priority: high
type: bug
ordinal: 461000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review high で CONFIRMED。TASK-266 で ViewerWebView を常駐させたことにより、makeNSView が store.openFile より前に走るようになった。

## 経路
変更前は、ウィンドウ構築時点では entries が空でプレビュー対象が .folder(parentDir) になるため ViewerWebView が存在せず、makeNSView は一覧が届いた後（= store.filePath が入った後）まで遅延していた。現在は filePreview が opacity 0 で常に階層にあるため、ViewerWindowController.swift:252 の `window.contentViewController = makeSplitViewController(...)` の時点で ViewerWebView が作られる。これは同 :277 の `store.openFile(fileURL)` より前で、store.filePath はまだ nil。

その結果 ViewerContentView.currentZoom が ZoomStore.defaultZoom を返し、ViewerRenderer.makeWebView が atDocumentStart の user script に initialZoomScript(1.0) を焼き込む。以後の再適用は applyStoredZoom()（performFileSwitch からのみ）と reloadViewerHTML（直接 HTML モードの離脱）だけで、**ウィンドウを開いた最初のファイルには一度も走らない**。

## ユーザー影響
ファイルを 150% にして閉じ、同じファイルを開き直すと 100% で表示される。その状態でズームすると、誤った基準から保存値が上書きされる。

## 方針の候補
- store.filePath が確定した時点で保存倍率を適用する経路を用意する（applyStoredZoom を初回にも通す）
- または initialZoom を user script への焼き込みではなく updateNSView 経由の適用に寄せる
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ファイルを任意の倍率にして閉じ、同じファイルを開き直すとその倍率で表示される
- [x] #2 フォルダー→ファイルの切替、ファイル→ファイルの切替でも従来どおり保存倍率が復元される
- [x] #3 回帰を捉えるテストがある（倍率の適用経路が初回ファイルでも通ることを検証する）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ADR 0002 の段 3（representable を投影に徹させ、初期値を updateNSView へ移す）として実施する。段 1（TASK-275）の提示状態が入った後に着手する。

## 実装（2026-08-04・ADR 0002 段 3）

倍率を「生成時に焼き込む値」から「状態の投影」に変えた。ViewerRenderer.initialPageZoom の didSet と viewer.html の準備完了(didFinish)の双方で適用し、適用済みの値を記録して同一値の再評価は避ける。直接 HTML モードへの出入りでは viewer.js の状態が作り直されるため記録も破棄する。

## 実測（dev ビルド・保存値の差分で判定）
倍率 1.5 のファイルを閉じて開き直し、⌘+ を 1 回押す:
- 修正後: 保存値 1.5 → **1.75**（1.5 から始まった＝復元されている）
- 修正前: 1.0 から始まるため 1.25 になるはずの経路

## 検証中に見つけた別のバグ（同じコミットで修正）
/tmp のようなシンボリックリンク経由の別表記で開くと、**文書ではなくフォルダー一覧が表示され**、ズーム・ソース表示・行番号・ブックマークがすべて無効になっていた。

原因は照合基準の食い違い。SidebarNavigator.refreshFileList は正規化パスキーで「選択は有効」と判断して選択を保持する一方、PreviewTargetResolver は生の URL（entry.id）で照合するため一致せず、.folder へフォールバックしていた。ADR 0002 が指摘した「同じ概念の真実の源が複数ある」の実害そのもの。ID で外れたときだけ正規化キーで照合し直すようにして揃えた（正規化は syscall を伴うため、一致する通常経路では走らせない）。

macOS では存在するファイルのみ /private 接頭辞が外れる（存在しないパスでは正規化が働かない）ため、テストは実ファイルを作って別表記を作る形にしてある。

## 確認済み
- swift test 1031 tests / 155 suites green（レンダラの倍率適用 3 件、別表記の照合 1 件を追加）
- swiftlint: 新規警告なし（既存 3 件の行数カウントのみ）
- GUI: /tmp 経由で開いても文書が表示され、拡大・ソース表示が有効
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
初期倍率を生成時の焼き込みから状態の投影へ変え、ウィンドウを開いた最初のファイルでも保存倍率が復元されるようにした。実測で、倍率 1.5 のファイルを開き直して ⌘+ を 1 回押すと保存値が 1.75 になる（1.5 から始まった証拠）。検証中に、シンボリックリンク経由の別表記で開くと文書ではなくフォルダー一覧が出る別バグ（照合基準の食い違い）を発見し、同じコミットで解消した。swift test 1031 green / swiftlint 新規警告なし。
<!-- SECTION:FINAL_SUMMARY:END -->
