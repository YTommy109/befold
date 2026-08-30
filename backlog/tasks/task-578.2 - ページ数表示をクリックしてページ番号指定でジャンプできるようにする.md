---
id: TASK-578.2
title: ページ数表示をクリックしてページ番号指定でジャンプできるようにする
status: In Progress
assignee: []
created_date: '2026-08-30 11:57'
updated_date: '2026-08-30 14:02'
labels: []
dependencies:
  - TASK-578.1
parent_task_id: TASK-578
priority: medium
ordinal: 842000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ページ位置表示をクリックすると、その場が数字入力エリアに変わり、入力したページ番号へジャンプする。入力を確定/取り消した後は通常の表示に戻る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ページ数表示をクリックすると数字入力エリアに切り替わる
- [ ] #2 ページ番号を入力して確定すると当該ページへジャンプする
- [x] #3 範囲外・非数値の入力ではジャンプせず、表示が壊れない
- [ ] #4 Esc など取り消し操作で入力を破棄して通常表示へ戻る
- [ ] #5 確定/取り消しの後、現在ページ表示が実際の表示位置と一致する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー（/review-design）の結論

### 面への書き込みは既存の口を通す（項目 2）
ジャンプは `PDFViewProxy` 越しに `ZoomingPDFView` のメソッドを呼ぶ（`PDFFindModel` と同じ形）。
PDFKit の `go(to:)` をモデルから直接叩かない（面への書き込み口を 1 つに保つ / TASK-574.1）。
実測: `PDFView.go(to: page)` は縦フィットでも 3 倍拡大でも狙ったページちょうどへ着地する
（`currentPageIndex` が target と一致 / 10 ページ文書で 0・3・7・9 と 2・8 を確認）。AC #5 はこれで満たす。

### 編集状態はモデルに置く（項目 7・項目 5）
View の `@State` に置くと SwiftUI の外から触れず、入力の検証がテストできない。
モデルに `isEditing` / `draft` を持たせ、`beginEditing()` / `commit()` / `cancel()` を
検証可能な入口にする。**文書が差し替わったら編集を閉じる**——PDF から別の PDF へ
切り替えると View は消えないので、編集中の値が残って古い番号で飛びうる。

### 入力の検証は純関数（項目 1・項目 7）
`pageJumpTarget(from:pageCount:)` を静的な純関数にする。判定は入力文字列の形ではなく
**パース結果と実際の総ページ数**で行う。空白を落として `Int` へ通し、1...pageCount の
外は nil（＝ジャンプしない）。全角数字・小数・非数値はすべて nil。

### 新しい状態の表示（項目 4）
確定できない入力は**ジャンプせずに編集を閉じるだけ**にする。常時表示の場所に
エラー表示を出すのは過剰で、AC #3 の「表示が壊れない」を満たすには戻すだけで足りる。

### 追随の経路は増やさない（項目 3）
ジャンプ後のページ番号は TASK-578.1 の bounds 通知でそのまま追随する。新しい経路を作らない。
兄弟の判断（検索の「次へ」）も同じ通知経路に既に乗っている。

## 手順
1. `ZoomingPDFView.go(toPageAt:)` を足す（型グループ 382 行なので追加後の行数を測る）。
2. `PDFPageIndicatorModel` に編集状態と `pageJumpTarget(from:pageCount:)` を足す。
3. `PDFPageIndicator` をクリックで `TextField` に差し替える。Esc で取り消し、Enter で確定。
4. テスト: 純関数の表（非数値・範囲外・境界）、`commit()` が実位置を動かすこと、
   取り消しで動かないこと、文書差し替えで編集が閉じること。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- `PDFPageIndicatorModel` に編集状態（`isEditing` / `draft`）と
  `pageJumpTarget(from:pageCount:)`（純関数）、`beginEditing()` / `commit()` / `cancel()` を追加。
- `ZoomingPDFView.go(toPageAt:)` を追加。面への書き込みはここを通す（TASK-574.1）。
- `PDFPageIndicator` をクリックで `TextField` へ差し替える。Enter で確定、Esc で取り消し。
- `viewer.pdf.pageJump` を Localizable.xcstrings へ追加。

## 実測で分かって設計を変えた点

- **`onTapGesture` では反応しない。** 実機で合成クリックでも `AXPress` でも発火せず、
  編集に入れなかった。右上の回転コントロールが `Button` で動いているので `Button`
  （`.plain`）へ変えたところ、`AXPress` で `AXTextField` が現れることを確認した。
- **入力欄には地を敷いた。** 敷かないと通常表示とほぼ同じ見た目で、打ち込めるのかが
  画面から分からなかった（実機で確認）。
- **`(1 ... pageCount)` は総ページ数 0 で落ちる**（`Range requires lowerBound <= upperBound`
  でテストプロセスが signal 5 で死んだ）。範囲を作らず `number >= 1, number <= pageCount` で比べる。
- **入口で読み直す。** `beginEditing()` / `commit()` が溜めた `pageCount` で可否を決めていて、
  通知がまだ届いていない間に「ページが無い」と誤判定した。モデルの「値を溜めない」方針に合わせた。
- `PDFView.go(to:)` の着地は倍率によらず狙ったページ（実測: 10 ページ文書で縦フィットと
  3 倍拡大の両方で `currentPageIndex` が一致）。AC #5 はこれで満たす。

## 検証

- `swift test`: 1848 tests / 300 suites 通過
- **テストが空振りしないことを 3 通りの破壊で確認**: ジャンプを実行しない → 「確定すると
  当該ページへ飛び…」が落ちる / 範囲チェックを外す → 「受け付ける入力と受け付けない入力」が
  落ちる / 文書差し替えで編集を閉じない → 「文書が差し替わると編集が閉じる」が落ちる
- swiftlint: `origin/main` とのベースライン差分ゼロ。型グループ・doc チェックも通過
- 実機: クリック（AXPress）で入力欄が現れること、AX 経由で値を入れるとモデルの
  `draft` へ届くことを確認

## 未検証（手動確認が要る）

**Enter による確定と Esc による取り消しを実機で確かめられていない。** 合成キー入力が
SwiftUI の `TextField` へ届かず（`focused` が false のまま）、打った文字が入らない。
**これは今回の変更に固有ではない**——出荷済みの検索バー（`PDFFindOverlay`）を同じ方法で
調べても `focused` は false で "abc" が入らなかった。つまり合成キー入力側の限界であり、
`PDFFindOverlay` の doc が TASK-570 の時点で「`@FocusState` だけで first responder が
移るかは実機で確定できていない」と書き残しているのと同じ論点。

したがって AC #2 / #4 / #5 は**ユーザーによる実機の手動確認が要る**（コード上は
ユニットテストで固定済み）。もし実機で打った文字が入らない場合、直すべきはこの View
ではなく responder の移動で、検索バーと共通の手当てになる。
<!-- SECTION:NOTES:END -->
