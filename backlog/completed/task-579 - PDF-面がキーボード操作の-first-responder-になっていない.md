---
id: TASK-579
title: PDF 面がキーボード操作の first responder になっていない
status: Done
assignee: []
created_date: '2026-08-30 14:14'
updated_date: '2026-09-01 05:05'
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
- [x] #1 検索バーの入力欄が、開いた直後にキー入力を受け付ける（実機で確認する）
- [x] #2 検索バーを閉じたら、フォーカスが PDF 面へ戻る（閉じた直後にキーで送れる）
- [x] #3 PDF を開いた直後にサイドバーからフォーカスを奪わない（TASK-581 の決定を保つ）
- [x] #4 この面に置く入力欄が 1 つの型に寄っており、同じ穴を 3 回開けない構造になっている
- [x] #5 実測の結果（何が再現し、何が設計判断で「やらない」ことになったか）を Notes に記録している
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

## 着手時に AC を書き換えた（2026-09-01）

元の AC #1「PDF を開いた直後、面をクリックせずにスペース・矢印・j/k でスクロールできる」は
**TASK-581 の決定（PDF を開いてもフォーカスはサイドバーに残す）と正面から競合する**ため、
そのままでは実装できない（実装すると TASK-581 の回帰テストが落ちる）。ユーザーが選んだ
挙動を優先し、AC を実態へ書き換えた。元の AC #2（検索バー）は独立に有効なので残した。

## 調査で分かったこと

**PDF 面と web 面で「フォーカスを得る仕組み」に実装差は無い。** どちらも AppKit 既定の
クリック昇格に頼っており、面を first responder にするコードはリポジトリに存在しない
（`acceptsFirstResponder` / `becomeFirstResponder` / `nextKeyView` / `initialFirstResponder`
はプロダクトコードに 0 件）。`makeFirstResponder` を呼ぶのは 3 箇所だけで、いずれも
サイドバーか PDF の入力欄まわり。

つまり元の題名「PDF 面が first responder になっていない」は PDF 固有の欠陥ではなく、
**サイドバーが first responder を握り続ける**という一般の話だった。サイドバーが明示的に
手放すコードも存在しない（`SidebarTableFocuser.cancelPendingFocus` は未成立の「要求」を
捨てるだけ）。

## 直したもの: 同じ穴が 2 回開いたので構造で塞いだ

「この面（AppKit がホストする PDFView に重なる SwiftUI）で `TextField` + `@FocusState` は
first responder を取れない」という同型の欠陥が 2 回出た。

1. ページ番号入力（TASK-578.2）— `PageNumberField` を作って個別に解決
2. 検索バー（`PDFFindOverlay`）— `@FocusState` + `.task { isInputFocused = true }` のまま
   放置されていた。コメント自身が「実機で確定できていない」と書いていた

CLAUDE.md「同型のバグが 2 回目に出たら、個別修正をやめて構造で塞ぐ」に従い、
`PageNumberField` を `FocusClaimingTextField` へ一般化して**両方をそこへ寄せた**
（`PageNumberField.swift` は削除）。面へ戻す処理も `PDFViewProxy.focusSurface()` の
1 箇所へ集約した（以前は `PDFPageIndicatorModel` に private で 1 つだけあった）。

検索バーを閉じたときの戻し先も追加した。`PDFFindModel.close()` の呼び出し元は
検索バーの × と Esc だけで、文書の差し替えは `documentChanged()` を通るため、
TASK-581 と同じ罠（操作していない契機でフォーカスを奪う）は踏まない。

## 実機での実測（2026-09-01 / 20 ページの PDF）

| 操作 | 測定結果 |
| --- | --- |
| ⌘F で検索バーを開く | `AXFocusedUIElement` の role が `AXTextField` になる |
| そのまま文字を打つ | 打った文字がそのまま入る（`AXValue` に反映） |
| Esc で閉じる | フォーカスが `AXGroup`（説明「書類」＝ PDF 面）へ戻る |

**修正前は入力欄がフォーカスを取れていなかった**（TASK-578.2 の実測で
`firstResponder=ZoomingPDFView` / `focusState=false`）。AC #1・#2 はこれで満たした。

## テストが空振りしないことを 2 通りの破壊で確認

- `close()` で面へ戻さない → 「検索バーを閉じるとフォーカスが面へ戻る」が落ちる
- `documentChanged()` でも面へ移す（TASK-581 の回帰を再現）→ 「文書が差し替わっても
  フォーカスは動かない」が落ちる

## 残る論点（実装していない / ユーザーの判断が要る）

**PDF を開いた直後にスペースを押しても、まだ何も起きない。** フォーカスはサイドバーに
あり、サイドバーはスペースに割り当てを持たないため。面へ渡すには今のところ
**面を 1 回クリックする**必要がある（クリックでの昇格は AppKit 既定に委ねられており、
`PDFView.acceptsFirstResponder` は true・`hitTest` は `PDFDocumentView` を返すことを
実測済み。ただし実際のクリックでの昇格は未確認）。

これを解消するなら「開いた瞬間に奪う」以外の手段を選ぶ必要がある（Tab で行き来する、
メニュー項目とショートカットを足す、サイドバーの矢印操作由来でないオープンのときだけ
面へ移す、など）。**どれもユーザー体験の判断なので、着手前に方針を決めること。**
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PDF 面に重なる入力欄が first responder を取れない問題を、構造で塞いだ。同型の欠陥が 2 回出ていた（ページ番号入力 / 検索バー）ため、CLAUDE.md の規定に従い個別修正をやめ、PageNumberField を FocusClaimingTextField へ一般化して両方を寄せた（PageNumberField.swift は削除）。面へ戻す処理も PDFViewProxy.focusSurface() へ集約し、検索バーを閉じたときの戻し先を追加した。実機で ⌘F 直後にフォーカスが AXTextField になり文字が入ること、Esc で PDF 面（AXGroup「書類」）へ戻ることを確認。swift test 1851 件通過、swiftlint 差分ゼロ。元の AC #1（開いた直後にクリックせずスクロール）は TASK-581 の決定と競合するため実装せず、AC を実態へ書き換えたうえで、残る論点として「面へフォーカスを渡す手段の選択」を Notes に記録した。
<!-- SECTION:FINAL_SUMMARY:END -->
