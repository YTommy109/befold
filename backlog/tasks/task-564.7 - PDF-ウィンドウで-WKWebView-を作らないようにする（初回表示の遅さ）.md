---
id: TASK-564.7
title: PDF ウィンドウで WKWebView を作らないようにする（初回表示の遅さ）
status: To Do
assignee: []
created_date: '2026-08-29 12:42'
labels:
  - performance
dependencies: []
parent_task_id: TASK-564
ordinal: 822000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 目的

PDF を開いたときの初回表示が体感で遅い（ユーザー報告: 約 1 秒）。実測すると、時間の大半は
**PDF とは無関係な WKWebView の生成と viewer.html の読み込み**に食われている。
PDF は `PDFView` で描くようになった（TASK-564.1 / ADR 0009）のに、同じ窓に
描画面がもう 1 枚作られ、viewer.html + バンドル（816KB）を読み込んでいる。

## 実測（2026-08-29 / Debug ビルド / 一時的な NSLog 計測）

窓が 2 つ復元される起動での内訳（`openViewer` を 0ms とした相対時刻）:

| 経過 | 出来事 |
| --- | --- |
| 0.0ms | `openViewer` 開始 |
| 51.4ms | `ViewerWebView.makeNSView`（**WKWebView の生成**） |
| 121.7ms | `loadContent` 開始 |
| 293.5ms | 読み込みパイプラインが実際に走り始める（**この間 172ms、メインスレッドが窓の組み立てで詰まっている**） |
| 294.9ms | ファイル読み込み + PDF の検証まで完了（**1.4ms**） |
| 313.2ms | 表示状態の確定 |
| 323.3ms | `PDFView` へ文書を設定し終わる |
| +約 180ms | `PDFView` の初回描画（画素が出るまで） |

PDF 自体の処理は速い。別プロセスでの計測では 1.2MB / 231 ページの PDF でも
読み込み 0.2ms・SHA256 0.4ms・`PDFDocument(data:)` 0.1ms（遅延パースのため）で、
初回の描画だけが約 115ms。**既に開いている窓でファイルを PDF へ切り替える場合は
読み込みから描画設定まで 26ms** で終わる。つまり遅いのは窓を新しく作る経路。

## やること

PDF を表示する窓では WKWebView を作らない（遅延生成にする）。

## 論点（実装着手前に `/review-design` で詰める）

- **TASK-266 との整合**: 「描画面は破棄・再生成しない」は白フラッシュと stale な初期倍率を
  避けるための決定で、**まだ作っていないものを作らない**こととは別。ただし PDF → md の
  切替時に生成コストを払うことになるので、その瞬間の見え方を確認すること。
- **どこで判断するか**: 種別による分岐は `DocumentSurfaces` / `DocumentSurfaceStack` に
  閉じている（ADR 0009）。生成の遅延もそこへ閉じられるか。
- **`WebViewProxy` の nil 期間**: 面がまだ無い間に届く設定反映（`applyCodeFont` 等）は
  現在も no-op で耐える設計だが、遅延生成すると「まだ作っていない面へ配った値」を
  生成時に適用し直す必要が出る。取り残しの事故（TASK-401）を再発させないこと。
- **測り方**: 改善の確認は上と同じ NSLog 計測でよい。数値を Implementation Notes に残す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PDF だけを開いた窓で WKWebView が生成されない
- [ ] #2 PDF → 他種別への切替で描画面が生成され、白フラッシュや倍率の取り残しが起きない
- [ ] #3 初回表示までの時間を改善前後で実測し、数値が Implementation Notes に記録されている
- [ ] #4 設定反映（フォント・CSV 数値表示・ジャンプ可否）が遅延生成した面にも取り残しなく入る
<!-- AC:END -->
