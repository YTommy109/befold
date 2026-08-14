---
id: TASK-446
title: ViewerRenderer の pendingUpdate 単一スロット上書きで描画要求が消えうる
status: Done
assignee: []
created_date: '2026-08-11 11:01'
updated_date: '2026-08-13 04:22'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 674000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ViewerRenderer.handleNavigationFailure`(BefoldApp/BefoldRenderKit/ViewerRenderer.swift:358-368) が `exitDirectHTMLMode` → `reloadViewerHTML`(ViewerRenderer+RenderHelpers.swift:214-228) を呼び、`pendingUpdate` を**無条件に上書き**する。`pendingUpdate` はスロットが 1 つしかない（ViewerRenderer.swift:130、消費は :299-300）。

再現順序:

1. `.html` ファイルで直接 HTML モードへ入る（ViewerRenderer+ContentUpdate.swift:134 で `isReady = false`、`loadFileURL` 開始）
2. その間に別ファイルへ切り替わると、更新は `pendingUpdate` に積まれるだけ（ContentUpdate.swift:235）
3. ここで 1 のナビゲーションが失敗すると（ファイル削除・読めない・policy cancel 由来の "Frame load interrupted" 等）`handleNavigationFailure` が走り、**積まれていた描画要求が空 completion に置き換わって消滅**する。同時に `rendered.reset()`（:351）
4. 以後 SwiftUI 側の値は変わらないため updateContent を呼び直す契機が無く、空の viewer.html のまま残る

`.cancel` を返すローカルファイルリンクのクリック（ViewerRenderer+DirectHTMLLinkPolicy.swift:40-47）は 2→3 の順序を作りやすい経路。

TASK-445 の調査中に発見した。TASK-445 の報告事象（切替元が .swift / .sh）とは前提が異なるため別タスクとする。世代番号でもミラー比較でもなく単一スロットの上書きが原因なので、既存のガードのどれにも掛からない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 pendingUpdate に積まれた描画要求が、ナビゲーション失敗による viewer.html 再ロードで失われない
- [x] #2 .html を直接 HTML モードで読み込み中に別ファイルへ切り替え、元のナビゲーションが失敗しても、切替先の内容が表示される
- [x] #3 上記を破ると落ちるユニットテストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手時点でコードは ViewerReadinessGate へ分離済みだったが、保留は依然 1 スロット(pendingWork: (() -> Void)?)で、後から来た run が前の保留を上書きする形が残っていた。ナビゲーション失敗 → DirectHTMLModeController.exit → reloadViewerHTML の readiness.run(completion) が、直接ロード中に積まれた描画要求を置き換えて消していた。

まず単純化を検討した: reloadViewerHTML の保留処理は「倍率再適用 + completion」だったが、唯一の呼び出し元 exit が appliedPageZoom を nil にしてから呼ぶため、ロード完了時の didFinish → applyInitialPageZoomIfReady が同じ倍率を当て直す。保留側の evaluateJavaScript は二重適用かつ appliedPageZoom の記録を経由しない重複だったので削除した。ただしこれだけでは completion が保留を上書きする構図は残るため、根本はゲート側で塞ぐ。

修正: ViewerReadinessGate.pendingWork を配列にし、markReady で積まれた順に全て流す。スロットを空にしてから実行するため、実行中に markNotReady + run で積み直された分は次の準備完了へ持ち越される。

検証(実測): swift test で 231 suite / 1467 テスト全通過。新規 ViewerReadinessGateTests の 3 件は、ゲートを 1 スロットへ戻すと 2 件が実際に落ちることを確認済み(順序テストは log == ["second"]、失敗経路テストは didRender が false)。swiftlint は変更ファイルに指摘なし、swiftformat は再整形なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerReadinessGate の保留スロットを 1 個から FIFO 配列へ変え、viewer.html 読み直し時の run が保留中の描画要求を上書きして消す経路を塞いだ。併せて reloadViewerHTML の重複した倍率再適用(didFinish 側で当たる)を削除した。ViewerReadinessGateTests 3 件で担保し、修正を戻すと 2 件が落ちることを確認。swift test 1467 件全通過。
<!-- SECTION:FINAL_SUMMARY:END -->
