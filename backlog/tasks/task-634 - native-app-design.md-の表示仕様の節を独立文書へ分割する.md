---
id: TASK-634
title: native-app-design.md の表示仕様の節を独立文書へ分割する
status: To Do
assignee: []
created_date: '2026-09-17 06:24'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 831000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
docs/dev/native-app-design.md が 746 行・98KB に膨らみ、docs/dev の他文書（11〜13KB）の 8 倍近い。うち「表示仕様」の節が 327 行（44%）を占め、ファイル種別ごとの扱い（.md / .xml / PDF / CSV の数値列・表示幅）と操作 UI（ズーム・検索と文書内ジャンプの統合バー・表示モード切替・サイドバー）が同居している（実測: 2026-09-17、wc -l と見出しごとの行数）。

分割案: 表示仕様だけを切り出し、ファイル種別ごとの扱いを docs/dev/file-type-display.md、操作 UI を docs/dev/viewer-ui.md へ移す。native-app-design.md は構成・コンポーネント・監視・アップデート等を残し、「現在の仕様」の入口として 2 文書への索引を持つ（単一の情報源は「この文書から辿れる範囲」として保つ）。

付け替えが要る参照（実測: rg 'native-app-design.md#' docs/dev）: viewer-rendering-dataflow.md の derived-from #表示仕様 / #ファイル監視、quicklook.md と cli-launch.md の derived-from #モジュール構成。superpowers/specs の本文リンクはスナップショットなので書き換えない。

経緯: TASK-633 で表示幅の表を表示仕様へ足した際にユーザーが指摘。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 表示仕様の節の内容が file-type-display.md と viewer-ui.md へ移り、native-app-design.md には両文書への索引だけが残る
- [ ] #2 docs/dev 内の native-app-design.md#表示仕様 を指す derived-from が移動先を指し、markdownlint-cli2 と scripts/check-doc-citations.sh が通る
- [ ] #3 CLAUDE.md（三層構造の表）と /finish-task の手順 5 の「現在の仕様」の置き場の記述が分割後の構成を反映している
<!-- AC:END -->
