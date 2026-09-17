---
id: TASK-634
title: native-app-design.md の表示仕様の節を独立文書へ分割する
status: Done
assignee:
  - '@claude'
created_date: '2026-09-17 06:24'
updated_date: '2026-09-17 06:56'
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
- [x] #1 表示仕様の節の内容が file-type-display.md と viewer-ui.md へ移り、native-app-design.md には両文書への索引だけが残る
- [x] #2 docs/dev 内の native-app-design.md#表示仕様 を指す derived-from が移動先を指し、markdownlint-cli2 と scripts/check-doc-citations.sh が通る
- [x] #3 CLAUDE.md（三層構造の表）と /finish-task の手順 5 の「現在の仕様」の置き場の記述が分割後の構成を反映している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 表示仕様の節を、ファイル種別ごとの扱い（+表示幅）と操作 UI の 2 文書へ行単位で移す
2. native-app-design.md には表示仕様の見出しと索引だけを残し、冒頭のサブシステム索引にも 2 文書を足す
3. derived-from・CLAUDE.md の三層構造表・/finish-task 手順 5・development.md の関連ドキュメントを付け替える
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: 本文は書き換えず行単位で移した（file-type-display.md = 旧 301〜425 行 + 表示幅の表、viewer-ui.md = 旧 426〜600 行）。単純化の検討: 見出しの細分化や本文の整理も考えたが、移動と改稿を同じ diff に混ぜるとレビューで欠落を確かめられないため、移動だけに留めた。
native-app-design.md は 746 → 431 行。file-type-display.md 158 行、viewer-ui.md 185 行。
欠落の確認: 削除行（空行除く）と分割後 3 文書の行を突き合わせ、差は旧 H3 見出し「### ファイル種別ごとの表示幅」（新文書で H2 へ昇格）の 1 行だけ。
#表示仕様 の見出しは索引として残したので、新 2 文書の derived-from はそこを指す。viewer-rendering-dataflow.md の derived-from は file-type-display.md へ付け替えた。#モジュール構成 / #ファイル監視 を指す 3 件は見出しが残るため変更不要。
CLAUDE.md の specs バナーのテンプレートは入口として native-app-design.md を指したままにした（既存 65 件の specs は書き換えない）。
検証: markdownlint-cli2 指摘 0 件（83 ファイル）、scripts/check-doc-citations.sh と scripts/check-doc-symbols.sh は終了コード 0。コード変更なしのため、テスト・swiftformat・swiftlint・ビルドは対象外。現在仕様の反映はこのタスクそのもの。

追補: ユーザーの「viewer-ui.md が読みにくい」を受け、移動とは別コミットで構成を整えた。1 つの箇条書き（文書内ジャンプだけで約 100 行）を見出し単位に分け、役割分担・目印の種類・ショートカットの情報源・行の開き分けを表にした。記述の中身は変えていない（バッククォート内の識別子と TASK / ADR 番号を旧版と突き合わせ、欠落なし）。markdownlint 指摘 0 件。

追補 2: file-type-display.md も同じ形に組み直した（共通 / Mermaid・Markdown / XML / PDF / CSV・TSV / 表示幅）。XML は解決順・種別・描画形・変換・全量読み込み・法令標準XML、PDF は読み込み・検索・見え方・スクロール位置・記憶する状態に分け、サイズ上限と記憶する状態は表にした。スタイルシート解決順の 3 番目（japanese-law.xsl）は、元の法令XMLの段にあった「最後の候補」を一覧へ明記しただけで内容の追加ではない。識別子・TASK/ADR 番号・実測値（MB/ms/pt/秒/行）を旧版と突き合わせ、欠落なし。markdownlint 指摘 0 件、check-doc-citations 通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
native-app-design.md の表示仕様の節（327 行）を file-type-display.md と viewer-ui.md へ移し、元の節には索引だけを残した（746 → 431 行）。derived-from・CLAUDE.md・/finish-task・development.md の参照を付け替えた。削除行と分割後の行の突き合わせで欠落なし、markdownlint と文書検査スクリプトは通過。
<!-- SECTION:FINAL_SUMMARY:END -->
