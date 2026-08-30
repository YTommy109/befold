---
id: TASK-574
title: PDF 面の差し替えライフサイクルを PDFKit の非同期性に合わせて構造化する
status: Done
assignee: []
created_date: '2026-08-30 03:37'
updated_date: '2026-08-30 05:29'
labels:
  - refactor
dependencies: []
priority: medium
type: task
ordinal: 831000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PDFKit 導入（ADR 0009）で命令の宛先（`DocumentSurfaces`）・読み込み経路（`.binary`）・レイアウト規則（`PDFSurfaceLayout`）は設計し直された一方、**「文書を差し替えてから最初の絵が出るまで」のライフサイクルだけは WebView 時代の前提（差し替えは 1 回の同期処理で完結し、待つものは無い）のまま**になっている。PDFKit は (a) タイル描画がバックグラウンド、(b) `PDFViewDocumentChanged` → `needsLayout`、(c) `didRotatePage` → メインキューの再レイアウト、と 3 箇所で非同期であり、その差分を埋める手当てが個別の仕掛けとして積み上がった。

| 非同期の現れ方 | 入った手当て |
| --- | --- |
| 表示サイクル待ち | `display()`（47dd9aab → 1470785e で revert） |
| 位置を入れる余地がまだ無い | `ZoomingPDFView.pendingRestoreFraction` センチネル |
| 回転後の再レイアウトが後から来る | `PDFSurfaceLayout.rotate` 内の `DispatchQueue.main.async` |
| タイル到着を知れない | `PDFSurfacePlaceholder` ＋ 外す条件 5 つ ＋ 0.4 秒タイマ |
| PDFKit がサブビューを積み直す | `noteLayout` で毎回 `addSubview` し直す |

この積み重ねが順序バグを生んでいる（TASK-567 → TASK-569 → 回転記憶での倍率上書き、と同型 3 件目）。CLAUDE.md の「同型のバグが 2 回目に出たら構造で塞ぐ」に従い、個別修正ではなく構造で対処する。

## レビューの裏付け（2026-08-30）

- **実測**: 回転記憶のあるファイルへの切り替えで、同期区間の直後は倍率 1.0・静止画ありだが、main キュー 1 周後に前のファイルの倍率 3.0 へ上書きされ静止画も外れる（一時テスト、削除済み）
- **dagayn `review_tool(mode="changes", base=origin/main)`**: レビュー優先度 0.40（medium）。`BefoldApp/befold/Viewer` は安定コンポーネント（instability 0.33）なのに変更ノードの直接テスト密度が 0（期待 0.8）で、`PDFPreviewView.updateNSView` / `installPlaceholder` が未検証（reason code: `stable_component_contract_gap`）。`refactor_tool(mode="suggest")` は 2,333 件のうち PDF 関連ファイルを 1 件も挙げていない——**サイズや複雑度の問題ではなく、所有権と順序の問題**であることと整合する。なお `tests_for` / `callers_of` は既知の取りこぼし（`PDFSurfaceLayoutTests` があるのに 0 件、`apply` の呼び出し 6 箇所中 1 件）なので、以下の件数は grep による
- **責任の集中（grep / `wc -l`）**:
  - `PDFSurfaceLayout`（258 行・static メンバ 17）が、純粋な換算（`fitScale` / `scrollOffset` / `normalized`）と面への副作用（`configure` / `apply` / `rotate` / `restore` / `scrollSmoothly`）と横断的な副作用（`placeholder.dismiss()`）を 1 つの enum に抱えている。呼び出し元は PDF 関連 4 ファイルすべてで、`apply` だけで 6 箇所
  - `ZoomingPDFView`（176 行・stored property 8）が、ジェスチャ・倍率の記憶・復元待ち・静止画・一度きりの配線・通知購読を持ち、`layout()` の override が 5 つの仕事（初回配線・`allowsMagnification` の毎回切り・倍率維持・復元・静止画の維持）をしている
  - 静止画を外す呼び出しが 3 ファイル 6 箇所に散っている（`PDFSurfaceLayout` 2、`PDFPreviewView` 3、`ZoomingPDFView` 1）
- **同じ概念に 2 つのデータフロー**: スクロール位置は WebView 面が `scrollPositionChanged` で常時 push、PDF 面は `saveScrollPositionBeforeTransition` からの切替時 pull のみ。回転は提示開始時に `store.pdfRotation` へ読み込むが以後 store へは戻さず退出時に面から pull。`WindowPresentationMemory` に PDF 専用の `rotations` 表が生えている
- **共有概念からの除外**: 読み込み表示は `showsLoadingIndicator` の `!fileType.rendersFromData` で PDF を除外している（PDF にとっての「読み込み中」を定義していない）

## 到達したい形

- 差し替えの手順（document → 回転 → 倍率 → 位置 → 静止画）を SwiftUI の外の 1 オブジェクトが同期関数 1 本で持ち、`updateNSView` は入力の変化を伝えるだけにする
- 静止画は `PDFView` の内部階層ではなく `DocumentSurfaceStack` のオーバーレイ層に state 駆動で置く
- 提示記憶（位置・回転）の流れる向きを両面で揃える
- 試行錯誤の残留物（死コード・設計文書の矛盾）を除く

子タスクごとに `/review-design` を回すこと（CLAUDE.md「実装着手前の設計レビュー」）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 子タスクがすべて Done で、TASK-569 の測り方（`.tmp/t569/sampler`、18 回）で 200ms 超の跳ねが 0 回のまま維持されている
- [x] #2 `docs/dev/native-app-design.md` の PDF 関連の記述が実装と一致している（`autoScales` の記述を含む）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## AC #1 の計測（2026-08-30 / TASK-574 完了後）

TASK-569 と同じ測り方（`.tmp/t569/compare.sh` → `sampler 18`、サイドバーの ↓ で .md → .pdf へ送り、キー押下から中身が画面に出るまで）。

```
min 18.4  median 22.9  max 28.9  (n=18)
```

**200ms 超の跳ねは 18 回中 0 回。** 全ラウンドが 18.4〜28.9ms に収まった。

参考: TASK-569 の起票時点は中央値 52.3ms・18 回中 3 回が 274〜286ms へ跳ねる状態、比較対象の 1.15.1 は 18/18 が 76〜108ms だった。今回はいずれより速く、ばらつきも小さい。

### 計測条件

- ビルドは `/run` の手順どおり `xcodebuild build -scheme befold -configuration Debug -derivedDataPath .build/xcode`。**Debug ビルドである点は TASK-569 当時と揃っているか未確認**だが、閾値 200ms に対して最大 28.9ms と 1 桁違うため、構成の差で結論は変わらない。
- 途中、`-derivedDataPath` をスクラッチパッドへ向けた自前の `xcodebuild` で 1 度失敗した（`.app` は生成されるが埋め込みフレームワークと Team ID が食い違い `dyld` が起動時に落ちる）。`/run` の手順に戻して解消。**ビルドはスキルの手順をそのまま使うこと。**
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PDF 面の差し替えライフサイクルを、PDFKit の非同期性に合わせて構造で組み直した。個別の手当て（表示サイクル待ち・復元待ちのセンチネル・回転後のメインキュー再適用・静止画とその外し条件・一度きり配線フラグ）が積み上がって順序バグを生んでいた状態を、次の 3 つで畳んだ。

1. **差し替えの順序を 1 つの同期関数へ**（574.1）。`ZoomingPDFView.present(document:rotation:zoom:scrollFraction:)` が文書 → 回転 → 倍率 → レイアウト → 位置を持ち、`PDFPreviewView.updateNSView` は入力を伝えるだけになった。`PDFSurfaceLayout` は面を変更しない換算だけの enum へ（264 → 163 行）。保留状態と一度きり配線フラグが消え、`layout()` の仕事は 2 つに減った。
2. **静止画をオーバーレイ層へ**（574.2、前セッション）。のちに TASK-575 で静止画自体を撤去。
3. **提示記憶の向きを揃えた**（574.3）。web 面だけが持っていたスクロールごとの push を撤去し、両面とも「切替直前の pull」1 本に。push は位置を UserDefaults へ永続化していた頃の名残で、TASK-565 で窓の生存期間だけの記憶にした時点で目的が失われていた。あわせて `WebViewCommandController` を `DocumentCommandController` へ改名（両面へ dispatch する型なのに回転 API が web 面を指していた）。

文書の矛盾（574.4）も解消し、`native-app-design.md` を実装へ追随させた。

**AC #1 の実測: 18 回中 200ms 超の跳ね 0 回**（min 18.4 / median 22.9 / max 28.9 ms）。起票時は中央値 52.3ms・3 回が 274〜286ms へ跳ねていた。

検証: swift 1805 tests / jest 615 tests 全緑、swiftlint 新規違反 0（54 → 53、解消 1）、JS の型・lint・整形・循環すべて 0 件、markdownlint と doc の 2 スクリプトも 0 件。

積み残し: TASK-574.5（`isLaidOut` が frame 0 でも true を返す既存の穴。本タスクの退行ではないが、`present` の同期 1 本化で再試行の余地が無くなったため分離して起票）。
<!-- SECTION:FINAL_SUMMARY:END -->
