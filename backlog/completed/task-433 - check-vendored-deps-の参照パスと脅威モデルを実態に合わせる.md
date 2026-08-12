---
id: TASK-433
title: check-vendored-deps の参照パスと脅威モデルを実態に合わせる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 12:59'
updated_date: '2026-08-11 11:50'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 107000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
同梱ライブラリの棚卸し手順（`.claude/commands/check-vendored-deps.md` と `.claude/agents/vendored-deps-auditor.md`）が実態とずれており、**実行しても大半が空振りする**。セキュリティ監査の手順が黙って何も検査しない状態になっている。

## 実測した不整合

1. **参照パスが 6 件中 5 件で壊れている。** 手順は `BefoldApp/befold/Resources/` を見るが、`markdown-it.min.js` / `github-markdown.css` / `mermaid.min.js` / `highlight.min.js` はそこに存在しない（実体は `BefoldApp/BefoldKit/Resources/`）。正しいのは dompurify の行だけ。この 4 コマンドは `head: No such file` か grep 空振りになる。
2. **mermaid が `BefoldApp/package.json` に記録されていない。** devDependencies は dompurify / github-markdown-css / highlight.js / jest / jsdom / markdown-it の 6 つ。手順の「package.json の記録と同梱ファイルの実バージョンが一致するか確認する」が mermaid については成立しない。
3. **mermaid.min.js から版を機械的に取れない。** パスを直しても `grep -o "\"version\":\"[0-9.]*\""` はヒット 0（実測）。ファイル先頭は `"use strict";var __esbuild_esm_mermaid_nm;` でバナーコメントも無い。唯一の記録は `BefoldApp/BefoldKit/Resources/THIRD_PARTY_LICENSES.md:11-15` の表（Mermaid 11.15.0）だが、両ドキュメントはこれを参照していない。
4. **CSP の脅威モデル記述が古い。** 両ドキュメントは「CSP が `script-src unsafe-inline` を許可しているため DOMPurify が唯一の XSS 防御」と書くが、実際の `viewer.html:17` は `script-src self` で、`unsafe-inline` が付くのは `style-src` のみ。`ViewerBridgeContractTests.swift:179-191` がこれを検証している。前提が誤っていると監査の重み付けを誤る。
5. **初期化コードの参照先が違う。** 手順は `viewer.html` の初期化コードを見よと指示するが、`viewer.html` は L56-60 でスクリプトを読むだけで `markdownit({...})` の初期化は `viewer-main.js` 側にある。mermaid も `viewer.html` から読まれず `viewer-main.js:605-616` で遅延ロードされる。

## 注意

TASK-432.5（手動ベンダリングを npm 依存へ移す）が完了すると、この棚卸し手順の前提自体が変わる（`npm audit` と `npm outdated` で足りるようになる可能性が高い）。ただし TASK-432.5 は着手時期が未定であり、それまで監査手順が空振りし続けるのは望ましくないため、先に実態へ合わせる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 check-vendored-deps.md と vendored-deps-auditor.md の参照パスがすべて実在するファイルを指す
- [x] #2 記載されたコマンドを実行して、6 つのライブラリすべてでバージョンが取得できる（取得不能なものはその旨と代替の確認方法が書かれている）
- [x] #3 mermaid のバージョン確認方法が記載されている
- [x] #4 CSP に関する記述が viewer.html:17 の実際の値と一致している
- [x] #5 初期化コードの参照先が viewer-main.js になっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 実測で不整合 5 点を確認する（完了: 4 は viewer.html:17 が script-src 'self'、5 は viewer-main.js:646/609-620。3 は Description と異なり version:"11.15.0" で抽出可能）
2. 単純化: 抽出コマンドの二重管理をやめ、scripts/vendored-deps-versions.sh に一本化する。パス消失・版抽出失敗で非ゼロ終了させ、空振りを構造的に潰す
3. check-vendored-deps.md と vendored-deps-auditor.md をスクリプト呼び出し + 正しい脅威モデル（script-src 'self'、DOMPurify は多層防御の一層）+ viewer-main.js の初期化参照へ書き換える
4. スクリプトを実行して 6 ライブラリ全ての版が出ることを確認し、markdownlint-cli2 を通す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Description の指摘 5 点のうち 4 点は実測で確認。1 点は誤りだった: mermaid の版は抽出可能で、キーが引用符なしの `version:"11.15.0"` 形式のため `"version":"…"` の grep が外れていただけ（実測: grep -o 'version:"[0-9]\+\.[0-9]\+\.[0-9]\+"' mermaid.min.js → 11.15.0 の 1 件のみ）。

単純化の判断: 抽出コマンドを 2 文書に重複記載していたことが「片方だけ直って再びずれる」原因だったため、scripts/vendored-deps-versions.sh へ一本化し、両文書はこれを呼ぶだけにした。スクリプトは package.json / THIRD_PARTY_LICENSES.md との突き合わせまで行い、パス消失・版抽出失敗・記録との食い違いで非ゼロ終了する。github.css を退避して実行し exit=1 とエラー行が出ることを確認済み（'黙って空振りする' 状態を構造的に潰す担保）。

mermaid だけ記録先が THIRD_PARTY_LICENSES.md（package.json に devDependency が無い）である点はスクリプトと両文書に明記した。TASK-432.5 で npm 依存へ移す際はこのスクリプトごと撤去できる。

検証: ./scripts/vendored-deps-versions.sh → 5 ライブラリの版が同梱・記録とも一致、exit=0。markdownlint-cli2 → 0 issues。ViewerBridgeContractTests.swift:179 に CSP script-src の検証テストが実在することを確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
同梱ライブラリ棚卸し手順（.claude/commands/check-vendored-deps.md / .claude/agents/vendored-deps-auditor.md）の壊れた参照パス・古い脅威モデル・誤った初期化コード参照を実態に合わせた。版抽出コマンドの二重管理を scripts/vendored-deps-versions.sh へ一本化し、パス消失・版抽出失敗・package.json / THIRD_PARTY_LICENSES.md の記録との食い違いを非ゼロ終了で検出させることで、手順が黙って空振りする経路を塞いだ。検証: スクリプト実行で 5 ライブラリの版が一致し exit=0、github.css 退避時に exit=1 とエラー行、markdownlint-cli2 0 issues。
<!-- SECTION:FINAL_SUMMARY:END -->
