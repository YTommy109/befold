---
id: TASK-574.5
title: PDF 面が最終寸法を得る前に差し替えると記憶していた表示位置が捨てられる
status: Done
assignee: []
created_date: '2026-08-30 04:46'
updated_date: '2026-08-30 05:38'
labels:
  - bug
dependencies: []
parent_task_id: TASK-574
priority: low
ordinal: 837000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`PDFSurfaceLayout.isLaidOut` は **frame が 0 の面でも true を返す**（実測: `isLaidOut=true` / 余地 24045.0）。この状態で位置を復元すると成功したように見えるが、**本物の frame が付いた瞬間に位置が 0 へ戻る**（実測: 復元直後 0.5 → frame 付与後 1.06e-06 / TASK-574.1 の一時テスト、削除済み）。

`isLaidOut` が答えているのは「スクロールビューまで組み上がったか」であって「最終的な寸法で組み上がったか」ではない。この 2 つは別の問いで、後者を判定する術がまだ無い。

**既存の穴であり TASK-574.1 の退行ではない。** センチネル方式（`pendingRestoreFraction`）でも同じレイアウトパスで使い切っていたため、frame 0 で復元して捨てられる挙動は同じだった。ただし TASK-574.1 で `present(...)` の同期 1 本に畳んだことで**後のレイアウトで再試行する余地が無くなった**ので、起きたときに自力で回復しない。

## 未確認の前提

**本番で実際にこの経路を通るかは未確認。** `PDFPreviewView.updateNSView` は SwiftUI のレイアウトパスで呼ばれ、`contentRevision` のガードがあるため、実際の文書が入るのは面が寸法を得た後である可能性が高い。着手時にまずこれを測ること（確認方法: `present(...)` の入口で `bounds` を実機のログに出し、切り替え・新規ウィンドウ・別種別からの復帰の 3 経路で 0 になるか見る）。

**通らないなら塞がない。** 通らない経路のために状態を足すのは TASK-574 が撤去したばかりの仕掛けを戻すことになる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `present(...)` の入口で `bounds` が 0 になる経路が本番に存在するかを実測し、結果を Notes に残している
- [ ] #2 存在する場合、面の寸法が確定してから位置を入れる形になっている（保留状態を新設せずに済む形を優先する）
- [x] #3 存在しない場合、その実測を Notes に残したうえでクローズしている（コードは変えない）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実測（2026-08-30）— 本番にこの経路は無い

`ZoomingPDFView.present(document:rotation:zoom:scrollFraction:)` の入口と `restore` 直後に `NSLog` を仕込んだ Debug ビルド（`/run` の手順）を実機で走らせ、3 経路を通した。

| 経路 | 操作 | 観測された `bounds` |
| --- | --- | --- |
| (a) 新規ウィンドウで PDF を直接開く | `open -a befold.app 02.pdf` | `{1047.5, 897}` |
| (b) サイドバーで .md → .pdf へ切替 | 19.md の窓で ↓ | `{1142.5, 897}` |
| (c) 別種別からの復帰（PDF → md → PDF） | サイドバーで ↓ → ↑ | `{1047.5, 897}` |

**`present` 呼び出し 15 回中、`bounds` が 0 だったものは 0 件。** 観測された寸法は 2 種類（`{1047.5, 897}` / `{1142.5, 897}`）で、いずれも窓の実寸。

### 構造上の理由

`PDFPreviewView.updateNSView` の先頭に `guard isVisible else { return }` があり、**見えていない面では `present` がそもそも走らない**。SwiftUI が `NSViewRepresentable` を可視にする時点で寸法は確定しているため、寸法未確定の面へ位置を入れる契機が生まれない。

### 測れなかったこと（正直な限界）

- **`scrollFraction` は全 15 回とも 0 だった。** 記憶に非 0 の位置を作るため PDF をスクロールさせようとしたが（本文をクリック → スペースキー）、System Events 経由の入力が本文へ届かず成功しなかった。ただし**問うているのは `bounds` が 0 になるかであり、これは面の寸法の性質で `scrollFraction` の値とは独立**なので、この限界は結論を左右しない。
- 新規タブ（`OpenDisposition.newTab`）で背面に作られる窓は測っていない。ただし上記の `isVisible` ガードが同じ理由で効く。

### 結論

**コードは変えない。** 起票時に危惧した「寸法未確定の面へ位置を入れて捨てられる」経路は本番に存在しない。存在しない経路のために状態を足すのは、TASK-574 が撤去したばかりの仕掛けを戻すことになる。

なお `isLaidOut` が frame 0 の面でも true を返すこと自体（TASK-574.1 の一時テストで観測）は事実のままだが、その `isLaidOut` は TASK-574.1 で `present` が同期に組み上げる形へ変わった際に**呼び出し元が無くなっている**（`pendingRestoreFraction` の消化条件としてのみ使われていた）。判定そのものが使われていないので、誤判定が表に出る経路も無い。

## 死コードを 1 件撤去した

調査中に判明: `PDFSurfaceLayout.isLaidOut` は**呼び出し元が 0 件**だった。TASK-574.1 で `pendingRestoreFraction` の消化条件を撤去したとき、その唯一の利用者が消えたのに宣言だけ残していた（`rg` で宣言 1 箇所のみ、参照は `.build` のデバッグシンボルだけ）。

このタスクが問題視していた誤判定（frame 0 の面でも true を返す）を持つ述語そのものなので、削除した。CLAUDE.md の完了基準「タスク中に発見したリファクタリング課題は同じタスク内で完了する」に従う。`PDFSurfaceLayout` は 163 → 153 行。

## 検証

- `swift test` **1805 tests / 293 suites 緑**、`npm test` **615 tests 緑**
- swiftlint ベースライン: main 54 / head 53、**真の新規 0**
- markdownlint / `check-doc-symbols.sh` / `check-doc-citations.sh` すべて 0 件
- 一時的に入れた `NSLog` は `git checkout` で除去済み（`grep NSLog` で 0 件を確認）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
起票時に危惧した経路は**本番に存在しない**ことを実機で確認した。`present(...)` の入口に `NSLog` を仕込んだ Debug ビルドで 3 経路（新規ウィンドウで PDF を開く / サイドバーで .md → .pdf / PDF → md → PDF の往復）を通し、**15 回の呼び出しすべてで `bounds` は非ゼロ**だった（0 件）。構造上の理由は `PDFPreviewView.updateNSView` 先頭の `guard isVisible else { return }` で、見えていない面では `present` が走らないため、寸法未確定の面へ位置を入れる契機が生まれない。

したがって挙動は変えていない。存在しない経路のために状態を足すのは、TASK-574 が撤去したばかりの仕掛けを戻すことになるため。

副次的に、誤判定の当事者だった `PDFSurfaceLayout.isLaidOut` が TASK-574.1 以降**呼び出し元 0 件の死コード**になっていたので削除した（163 → 153 行）。

限界: `scrollFraction` は全 15 回とも 0 で、記憶に非 0 の位置がある状態は再現できなかった（System Events 経由の入力が PDF 本文へ届かなかった）。ただし問うているのは `bounds` が 0 になるかで、これは `scrollFraction` と独立なので結論は変わらない。
<!-- SECTION:FINAL_SUMMARY:END -->
