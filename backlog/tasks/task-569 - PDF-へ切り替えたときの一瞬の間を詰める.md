---
id: TASK-569
title: PDF へ切り替えたときの一瞬の間を詰める
status: To Do
assignee: []
created_date: '2026-08-29 22:23'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 826000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーをカーソルキーで送って .md から .pdf へ切り替えると、1.15.1 (1640) と比べて一瞬の間がある（ユーザー報告 / 2026-08-30）。実用上の問題は無いが、旧バージョンのほうが快適という評価。

TASK-567 で「切り替え直後の 1 フレームがフィット前の倍率で描かれ、縮む過程が見える」問題は解消済み（倍率を最初の描画より前に確定させた）。**残っているのは描画の前後にある間**であり、原因は未特定。

実測で分かっている、原因**ではない**もの（TASK-567 で測定済み）:

- 面そのものの描画は PDFKit のほうが速い。231 ページ / 800x900 で 1 フレーム描くまで、WebKit 内蔵プラグイン 49〜122ms に対し PDFKit 7〜8ms
- フィット倍率の計算は 1 回 0.024ms（231 ページ）。縦フィットにしたことのコストではない
- 読み込み経路は 1.2MB の PDF で読み込み 0ms・ハッシュ 0ms・PDFDocument 生成 0ms。`PDFDataProbe` だけ初回 22ms（PDFKit の遅延初期化。2 回目以降は 0ms）
- ページの影は 1 フレームあたり約 30ms 掛かるが、TASK-567 で無効化済み

未確認の候補:

- 読み込みが非同期タスクを一往復する区間（`ViewerStore.loadContent` → `apply`）
- SwiftUI の状態反映が 1 フレーム挟まる区間（`showsPDF` の切り替えと面の可視化）
- `PDFDataProbe` と表示側で `PDFDocument` を 2 回作っている点（probe はバックグラウンド、表示は MainActor。PDFDocument が Sendable でないため意図的に分けてある）

進め方: 推測で手を入れず、一時ログで区間ごとの時刻を取り、どこに間があるかを特定してから対処する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーで .md から .pdf へ送ったときの、操作から最初の PDF フレームまでの時間が区間ごとに実測され、どこに間があるかが特定されている
- [ ] #2 特定した区間に対する対処が入り、対処の前後の実測値が記録されている（対処不要と判断した場合はその根拠が実測付きで記録されている）
<!-- AC:END -->
