---
id: TASK-432.5
title: 手動ベンダリングを npm 依存へ移す
status: To Do
assignee: []
created_date: '2026-08-10 12:57'
updated_date: '2026-08-10 12:58'
labels: []
dependencies:
  - TASK-432.1
parent_task_id: TASK-432
priority: low
type: chore
ordinal: 112500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
バンドル基盤ができた後、手動でコミットしているベンダーライブラリを npm 依存からのバンドルへ移す。

## 現状（実測）

`BefoldApp/BefoldKit/Resources/` にミニファイド済み成果物を直接コミットしている。生成手順はリポジトリ内に無い。

| ファイル | サイズ | バージョン | package.json への記録 |
|---|---|---|---|
| `mermaid.min.js` | 3.2 MB | 11.15.0 | **無し** |
| `highlight.min.js` | 124 KB | 11.11.1 | あり |
| `markdown-it.min.js` | 121 KB | 14.2.0 | あり |
| `dompurify.min.js` | 28 KB | 3.4.12 | あり |
| `github-markdown.css` | 30 KB | 5.9.0 | あり |
| `github.css` / `github-dark.css` | 各 2.1 KB | highlight.js のテーマと推定（**未確認**） | — |

バージョンの正は `BefoldApp/package.json` の devDependencies という設計になっているが、mermaid だけ記録が無い。唯一 mermaid の版を持つのは `BefoldKit/Resources/THIRD_PARTY_LICENSES.md:11-15` の表。

## 扱いを分けること

- **mermaid は特別扱いが要る。** 3.2 MB を遅延ロードする設計（`viewer-main.js:605-608`）を壊さないため、メインバンドルには入れず独立チャンクとして出力する必要がある。
- **`github.css` / `github-dark.css` の出所が未確認。** ファイルにバナーが無く `THIRD_PARTY_LICENSES.md` にも個別項目が無い。npm 化の前に出所を確定させること。
- **`THIRD_PARTY_LICENSES.md` の更新経路。** npm 依存から自動生成する形にできるか検討する。現在は手書きの表で、`OSSLicensesView.swift:11` がこのファイルを読んでアプリ内に表示している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ベンダーライブラリが npm 依存からバンドルされ、手動コミットされたミニファイド成果物が不要になっている（mermaid を除く）
- [ ] #2 mermaid が独立チャンクとして出力され、遅延ロードが維持されている
- [ ] #3 github.css / github-dark.css の出所が確定し、THIRD_PARTY_LICENSES.md に記載されている
- [ ] #4 THIRD_PARTY_LICENSES.md の内容が実際の依存と一致しており、ズレたら検出できる
- [ ] #5 アプリ内の OSS ライセンス表示が壊れていない
<!-- AC:END -->
