---
id: TASK-564.3
title: PDF の表示位置をウィンドウの生存期間だけ記憶する
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-29 00:41'
updated_date: '2026-08-29 11:51'
labels: []
dependencies:
  - TASK-564.1
  - TASK-565
parent_task_id: TASK-564
priority: medium
type: feature
ordinal: 817000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 目的

PDF を見ている途中で別のファイルへ移り、また戻ってきたときに、離れる直前の表示位置で開く。ウィンドウを閉じたら忘れてよく、次に開いたときは 1 ページ目でよい。

## 前提

**TASK-565 が「永続化しない表示状態の置き場」を先に作る。** このタスクはその置き場へ相乗りするのが原則で、PDF 専用の記憶機構を新設しない。TASK-565 でスクロール位置と表示モードがセッション限りの記憶へ移るため、PDF の表示位置も同じ扱いに揃う。

既存の永続ストアへ相乗りしてはならない理由は TASK-565 に整理してある（`ScrollPositionStore` は UserDefaults 永続で、内容変化の検査を一切していない）。また `viewer-src/scroll.ts` の scrollTop ベースの記憶は `.viewer` か `#diagram-wrap.code-body pre code` を対象にしており、`PDFView` へ移った PDF はそもそもこの経路に乗らない。

## 論点（実装着手前に `/review-design` で詰める）

- **保持する値**: ページ番号だけでは足りず、ページ内のオフセットも要る（`PDFView.currentDestination` が `PDFDestination` としてこれを表す）。拡大縮小（TASK-564.4）と回転（TASK-564.5）の状態も同じ「戻ってきたときの見え方」に含めるべきかを決め、含めるなら 1 つの値型にまとめる。バラバラの辞書を増やさない。
- **TASK-565 の置き場との関係**: セッション記憶がウィンドウ単位なのかアプリ単位なのかは TASK-565 で決まる。その決定に従い、PDF だけ別スコープにしないこと。
- **リネーム追従**: TASK-565 でセッション記憶のリネーム追従の有無が決まる。PDF もそれに揃える。
- **ファイル監視による再描画**: 同じ PDF が外部で更新されて再描画されたとき、位置を保つのか先頭へ戻すのかを決める。ページ数が減って現在ページが範囲外になる場合の扱いも決めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PDF を途中まで見て別ファイルへ移り、戻ると離れる直前の表示位置で開く
- [x] #2 ウィンドウを閉じて同じ PDF を開き直すと 1 ページ目から表示される
- [x] #3 表示位置が UserDefaults へ書かれないことを検証するユニットテストがある（この判断が破れたら落ちるもの。分離した `UserDefaults` 上で書く）
- [x] #4 記憶した位置のページが存在しなくなった場合（ファイル更新でページ数が減った等）に範囲内へ丸められ、クラッシュしない
- [x] #5 複数のウィンドウで同じ PDF を別の位置で開いても互いの記憶を壊さない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
/review-design の結論。**PDF 専用の記憶機構を作らない**という前提をいちばん強く効かせる形を採る。

## A. 論点への結論

A1. 保持する値 → **`PDFDestination` を持たない。** あれは特定の `PDFDocument` の
    ページを参照する参照型で、ファイル監視の再描画で文書を作り直すと別文書の
    ページを指す行き先になる（`PDFDocument` / `PDFDestination` は Sendable 非準拠
    でもある）。代わりに**「文書全体に対する 0…1」という 1 つの Double** に畳む
    （`(ページ番号 + ページ内の位置) / 総ページ数`）。これは web の面が返す値と
    **同じ意味**なので、`WindowPresentationMemory` の既存の表・既存の保存経路
    （`saveScrollPositionBeforeTransition` → `applySavedScrollPositionToLiveValue`）・
    既存の復元経路（`store.scrollPositionToRestore`）がそのまま使える。
    型も経路も増えない。

A2. TASK-565 の置き場との関係 → `WindowPresentationMemory`（窓ごと・ファイル単位・
    永続化なし）へ相乗りする。PDF だけ別スコープにしない。

A3. リネーム追従 → `WindowPresentationMemory.migrate` が既に位置を引き継ぐので、
    PDF も同じ表に乗る以上そのまま追従する。追加の配線は無い。

A4. ファイル監視による再描画 → **位置を保つ。** 復元はページ数で丸めるので、
    ページが減って範囲外になっても最後のページへ収まる（AC #4）。倍率と同じく
    「同じファイルを見続けている」ときに先頭へ飛ばさない方が実用的。

## B. チェックリストで拾ったもの

B1. 項目 1（判定の真実の源）: ページの存在を「記憶した番号が有効か」で見ると、
    文書がまだ無い一瞬に false になって位置を捨てる。`pageCount` から**丸める**形に
    したので、捨てる判定そのものが無い。
B2. 項目 3（消費経路）: 位置を読む/書く経路は保存 1 本・復元 1 本しかなく、
    どちらも面の種別を見ない（`DocumentSurfaceOperating.currentScrollPosition` と
    `store.scrollPositionToRestore`）。PDF はその実装を差し替えるだけ。
B3. 項目 9（決めた粒度を守らせるもの）: 「永続化しない」は
    `WindowPresentationMemory` が `UserDefaults` を型として持たないことで既に
    構造的に守られている。AC #3 のテストはその上に、分離した `UserDefaults` が
    増えないことを実測で押さえる。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-29）

PDF の表示位置を「文書全体に対する 0…1」へ畳み、web の面と同じ記憶・同じ経路に
乗せた。新しい型もストアも増えていない（差分は `PDFSurfaceLayout` の
`documentFraction(of:)` / `restore(fraction:in:)` と、`PDFPreviewView` が
`scrollPositionToRestore` を受け取る配線だけ）。

- 保存: `PDFDocumentRenderer.currentScrollPosition` が `documentFraction` を返す。
  既存の保存経路（切替前に退場側のキーで確定保存する）をそのまま通る。
- 復元: 文書を差し替えた直後、倍率を入れた**後**に復元する（倍率でページ内の
  余地が変わるため）。
- ページ数が減っていたら最後のページへ丸める（AC #4）。`PDFDestination` を
  持ち回らないので、別文書のページを指す行き先が生まれない。

### 検証

- `swift test` 1760 件すべて成功。`PDFSurfacePositionTests` で往復・ページ数減少・
  範囲外の値・文書なし・`UserDefaults` へ書かれないこと（AC #3）を実測で固定した。
- AC #2（窓を閉じたら忘れる）と AC #5（窓ごとに独立）は
  `WindowPresentationMemory` の性質そのもので、既存の `WindowPresentationMemoryTests`
  （揮発のトリップワイヤ）が守っている。PDF はその表に乗るだけなので、
  同じ検証を二重に書いていない。
- swiftlint の main とのベースライン差分ゼロ（双方 54 件）。

### 目視が必要な残り

「別ファイルへ移って戻ると同じ位置で開く」ことの体感（ページ内オフセットの
戻り具合）は実機の目視でしか確かめられない。値としての往復は上のテストで固定済み。
<!-- SECTION:NOTES:END -->
