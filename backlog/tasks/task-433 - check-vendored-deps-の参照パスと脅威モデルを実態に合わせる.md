---
id: TASK-433
title: check-vendored-deps の参照パスと脅威モデルを実態に合わせる
status: To Do
assignee: []
created_date: '2026-08-10 12:59'
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
- [ ] #1 check-vendored-deps.md と vendored-deps-auditor.md の参照パスがすべて実在するファイルを指す
- [ ] #2 記載されたコマンドを実行して、6 つのライブラリすべてでバージョンが取得できる（取得不能なものはその旨と代替の確認方法が書かれている）
- [ ] #3 mermaid のバージョン確認方法が記載されている
- [ ] #4 CSP に関する記述が viewer.html:17 の実際の値と一致している
- [ ] #5 初期化コードの参照先が viewer-main.js になっている
<!-- AC:END -->
