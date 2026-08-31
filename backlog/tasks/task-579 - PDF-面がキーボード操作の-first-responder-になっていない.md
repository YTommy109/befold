---
id: TASK-579
title: PDF 面がキーボード操作の first responder になっていない
status: To Do
assignee: []
created_date: '2026-08-30 14:14'
updated_date: '2026-08-31 01:42'
labels:
  - pdf
dependencies: []
priority: high
type: bug
ordinal: 843000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PDF を開いた直後、面をクリックせずにスペースキーを押してもスクロールしない。

## 実測（2026-08-30 / TASK-578.2 の作業中に判明）

- CLI で 20 ページの PDF を開き、何も操作せずスペースを送っても表示は 1 ページ目のまま。
- 同じ状態で `NSApp.keyWindow?.firstResponder` を記録すると `ZoomingPDFView` だった
  （＝面が first responder ではあるが、合成キー入力が届いていない可能性もある）。
- **これは TASK-577（キーボードスクロールの整備）以前からの挙動**で、TASK-577 の
  変更が原因ではない。TASK-577 のキー割り当て自体はユニットテストで固定されている。

## 併せて確認したいこと

検索バー（`PDFFindOverlay`）の入力欄も同じ事情でフォーカスを取れていない可能性がある。
実測では AX 上 `focused = false` のままで、合成キー入力では文字が入らなかった。
TASK-578.2 ではページ番号入力を AppKit の `NSTextField`（`PageNumberField`）へ置き換え、
窓へ入った 1 周後に `makeFirstResponder` を呼ぶことで解決した。同じ手当てが検索バーにも
要るかを確かめる。

**未確認**: 合成キー入力（System Events）が SwiftUI / PDFView へ届かないだけで、人が
実際にキーを打てば動く可能性がある。まず人手でスペースキーを試し、再現するかを
確かめてから着手すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PDF を開いた直後、面をクリックせずにスペース・矢印・j/k でスクロールできる
- [ ] #2 検索バーの入力欄が開いた直後にキー入力を受け付ける（同じ問題があれば PageNumberField と同じ手当てをする）
- [ ] #3 人手での再現確認の結果（再現する／しない）を Notes に記録している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 追加の実測（2026-08-31 / TASK-578.2 の作業中）

**原因はサイドバーのファイル一覧が first responder を握っていること。** ページ番号の
入力欄を出した瞬間の first responder を記録すると `SwiftUI.SwiftUIOutlineListView`
だった。この状態でスペースや矢印を押すと PDF ではなくサイドバーが反応する（実測: ↓ を
1 回押すと選択が動いて別のファイルが開いた）。

つまりこのタスクの本体は「PDF を開いたときの first responder をサイドバーから面へ移す」。
参考実装として `PDFPageIndicatorModel.focusSurface()` が
`window.makeFirstResponder(pdfView)` を 1 周待ってから呼ぶ形を持っている（実測で
`moved=true` / first responder が `ZoomingPDFView` になり、その後スペースで PDF が送られた）。

**未確認のまま残ること**: 人が実際にキーを打った場合にも再現するか。合成キー入力
（System Events）でしか試していない。

## TASK-581 と正面から競合する（2026-08-31）

ユーザー報告「サイドバーを矢印で流し読み中に PDF を開くとフォーカスを奪われる」を
TASK-581 として起票し、**PDF を開いてもフォーカスはサイドバーに残す**方針をユーザーが
選択した。TASK-581 では `.PDFViewDocumentChanged` 経由のフォーカス移動を外している。

したがって**このタスクの AC #1「PDF を開いた直後、面をクリックせずにスペース・矢印・j/k で
スクロールできる」は、そのままでは実装できない**（実装すると TASK-581 の回帰テストが落ちる）。

前の Notes に書いた「このタスクの本体は PDF を開いたときの first responder を
サイドバーから面へ移すこと」という結論は、この判断で**否定された**。

### 着手する場合に先に決めること

「開いた瞬間に奪う」以外で面へフォーカスを渡す手段を選ぶ必要がある。候補:
- 面を 1 回クリックしたら移る（現状でも効くはずだが未確認）
- 明示的なキー（Tab / Cmd+↓ など）でサイドバーと面を行き来する
- サイドバーの矢印操作**由来でない**オープン（クリック・CLI・Quick Open）でだけ面へ移す

**着手前にユーザーへ方針を確認すること。** AC #1 / #2 もその判断に合わせて書き換える。

なお AC #2（検索バーの入力欄がキー入力を受け付けない）は今回の判断と独立で、
そのまま有効。
<!-- SECTION:NOTES:END -->
