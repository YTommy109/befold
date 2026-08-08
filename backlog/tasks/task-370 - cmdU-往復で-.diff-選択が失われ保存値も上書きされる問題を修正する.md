---
id: TASK-370
title: cmd+U 往復で .diff 選択が失われ保存値も上書きされる問題を修正する
status: Done
assignee: []
created_date: '2026-08-08 11:22'
updated_date: '2026-08-08 12:15'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/ViewerWindowController.swift
priority: medium
type: bug
ordinal: 511000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) 指摘。FeatureGate 配下（diff 表示）。旧実装は cmd+U が isSourceMode のみをトグルし、app-global の diff 設定は ON のまま残ったため source → rendered → source の往復で diff オーバーレイが復元された。新実装の toggleSourceView は .diff から setDisplayMode(.rendered) を永続化し、2 回目の cmd+U は .source に落ちるため、そのファイルの保存値 .diff が上書きで消える。

再現: diff 表示中（cmd+3）→ cmd+U でレンダリング表示を確認 → cmd+U で戻る → diff の無い plain source に落ち、再起動後もそのファイルは diff 無しで開く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 diff 表示中に cmd+U → cmd+U で diff 表示に戻る
- [x] #2 往復操作で DisplayModeStore の保存値 .diff が失われない
- [x] #3 ユニットテストで担保する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化の検討: 戻り先を保存値から導出する案は成立しない(離脱側の cmd+U が保存値を .rendered で上書きするため、戻る側は必ず .source になる)。cmd+U を非永続の「覗き見」にする案は、既存テスト switchFileRestoresSavedSourceModeForTargetFile が担保する「cmd+U での選択もファイル単位に記憶される」挙動を壊すため不採用。applyDisplayMode 側で最後のソース系モードを常時追跡する案は、ファイル切替(URL 更新前に applyDisplayMode を呼ぶ)で別ファイルへ漏れるため不採用。結果、記憶と消費が toggleSourceView に閉じる形(ファイルパスをキーに持つ 1 タプル)を採った。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowController.toggleSourceView に「離れる直前のソース系モード」の記憶(ファイルパスをキーに持つ private タプル)を持たせ、cmd+U でレンダリング表示から戻るときはその値(差分表示なら .diff)へ戻すようにした。記憶はソース系モードへ入った時点で setDisplayMode が捨てるため、往復の間に cmd+2 で source を選び直した後は .source へ戻る。検証: befoldTests に 3 件のテストを追加(往復で .diff と保存値が保たれる / 明示選択で記憶が消える / 別ファイルへ漏れない)。修正前の実装へ戻すと往復テストが .source == .diff で 2 件失敗することを実測で確認済み。swift test は 1210 tests 全件 pass、swiftlint は当該 2 ファイルで新規指摘なし(既存の file_length 等のみ)。
<!-- SECTION:FINAL_SUMMARY:END -->
