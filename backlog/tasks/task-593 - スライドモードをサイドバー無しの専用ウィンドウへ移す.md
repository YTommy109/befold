---
id: TASK-593
title: スライドモードをサイドバー無しの専用ウィンドウへ移す
status: To Do
assignee: []
created_date: '2026-09-06 09:25'
labels:
  - sidebar
  - slide-mode
dependencies: []
documentation:
  - docs/superpowers/specs/2026-09-06-slide-window-design.md
priority: medium
type: feature
ordinal: 858000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-585 / 587 のスライドモードは「今の窓のサイドバーを 54pt に細めて行をマスクする」形で、プレゼン中に映すものとしてはサイドバー自体が不要なのに細めた列を残し、マスクの穴（TASK-588 のツールチップ漏れ、TASK-589 の再描画）を生み続ける。

サイドバーのコンテキストメニューの「スライドモードで開く」で、サイドバーの無い新しい窓（スライド窓）を開く形へ置き換える。スライド窓では Space / ↓ で次、Backspace / Shift+Space / ↑ で前のファイルへ移り、並びは開いた時点の元サイドバーの表示順（並び順・不可視・変更のみ・ツリーの展開状態）を引き継ぐ。⌘S と ⌘← は効かず、タブに合流せず、ツールバーを持たず、セッション復元の対象外。ソース表示・差分表示は従来どおり。旧モードは撤去する。

設計の経緯・不採用案・決定事項は spec（2026-09-05 のヒアリングで確定）を参照。実装は既存のビューア窓に窓種別 `.slide` を足す案 A。専用コントローラの新設（案 B）と Bool フラグ（案 C）は spec の「案の比較」で退けた。

サブタスク 3 件を依存順に進める（撤去 → 窓種別と入口 → 前後移動キー）。各サブタスクは着手前に /review-design を回す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーのコンテキストメニュー「スライドモードで開く」でサイドバー無しの新しい窓が開き、Space / ↓ で次、Backspace / Shift+Space / ↑ で前のファイルへ移る
- [ ] #2 旧スライドモード（幅の固定・行のマスク・View メニューの切替・ヘッダーの解除アイコン）がコードから消えている
- [ ] #3 docs/dev/native-app-design.md がスライド窓の仕様を記述し、旧モードの記述が残っていない
<!-- AC:END -->
