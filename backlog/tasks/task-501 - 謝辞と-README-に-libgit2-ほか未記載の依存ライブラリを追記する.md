---
id: TASK-501
title: 謝辞と README に libgit2 ほか未記載の依存ライブラリを追記する
status: To Do
assignee: []
created_date: '2026-08-16 10:52'
updated_date: '2026-08-16 10:53'
labels:
  - chore
dependencies: []
priority: high
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold は git 差分表示のために libgit2 を静的リンクして配布しているが、Help > OSS 謝辞（BefoldApp/BefoldKit/Resources/THIRD_PARTY_LICENSES.md）にも README.md の謝辞表にも libgit2 が載っていない。libgit2 は GPLv2 with linking exception であり、バイナリ配布時にライセンス全文と告知を同梱する必要がある（現状は告知が欠けた状態で配布している）。

依存の実体:
- libgit2 本体（SPM パッケージ https://github.com/ibrahimcetin/libgit2.git exact 1.9.2 経由。C ソースをそのままビルドする）— BefoldApp/Package.swift:17
- libgit2 が同梱する第三者コード（zlib / PCRE / llhttp 等）— libgit2 の COPYING に含まれる範囲を確認する
- ibrahimcetin/libgit2 のパッケージ化部分そのもののライセンス

あわせて、現在の謝辞表（README.md:71-79 と THIRD_PARTY_LICENSES.md の 8 節）が実際の依存と一致しているかを棚卸しする。ビルド時のみ使う SwiftLintPlugins / SwiftFormat は配布物に入らないため掲載対象外とする判断を Notes に残すこと。site/ 側の配布物に第三者コードが載っているかも確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 THIRD_PARTY_LICENSES.md に libgit2 の節が追加され、GPLv2 with linking exception の全文と同梱第三者コードの告知が収録されている
- [ ] #2 README.md:71 の謝辞表に libgit2 の行（役割: git 差分の取得、ライセンス: GPLv2 with linking exception）が追加されている
- [ ] #3 配布物に含まれる第三者コードを棚卸しし、掲載対象・非対象（ビルド時のみのツールなど）とその理由が Implementation Notes に記録されている
- [ ] #4 棚卸しで判明した libgit2 以外の未記載ライブラリがあれば同様に両方へ追記されている
- [ ] #5 Help > OSS 謝辞パネルで追記後の内容が表示されることを実機で確認している
- [ ] #6 BefoldApp/scripts/check-third-party-licenses.mjs の SWIFT_COMPONENTS に libgit2 を追加し、npm run check:third-party-licenses が版ずれを検出できる状態になっている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査結果（起票時、2026-08-16）:
- 謝辞の実体は BefoldApp/BefoldKit/Resources/THIRD_PARTY_LICENSES.md の 1 ファイル。表 :9-17 と全文 :21-718。Help > OSS 謝辞（OSSLicensesView.swift:4-24）はこれをバンドルから読んで表示するだけなので、この 1 ファイルと README.md:71-79 の表を直せば両面に反映される。
- 整合性チェッカ BefoldApp/scripts/check-third-party-licenses.mjs は SWIFT_COMPONENTS（:37-40）に Sparkle と swift-argument-parser しか持たず、libgit2 の欠落を検出できない。ここを直さないと同じ漏れが再発する。
- libgit2 は ibrahimcetin/libgit2 を SPM のソースターゲットとして直接ビルドし、C API を import libgit2 で直接呼ぶ形（Package.swift:16, GitLibrary.swift:1-3）。SwiftGit2 等のラッパーは経由しない。ライセンス上の位置づけ（GPLv2 with linking exception、静的リンク可）は docs/adr/0006-git-integration-via-libgit2.md:127-131 に既に記録済みで、謝辞側だけが追随していない。
- 掲載対象外と判断してよいもの: SwiftLintPlugins 0.65.0 / SwiftFormat 0.61.1（ビルドツールプラグイン、配布物に非同梱）、esbuild / jest / babel / jsdom / typescript / oxlint / oxfmt（開発時のみ）、site/ の hono ^4.6.14・zod ^3.24.1（Cloudflare Worker 側でアプリには同梱されない）。site には謝辞ページ自体が存在しない。
- 自作 CGitShim は第三者コードではないため掲載不要。
- 同梱 JS/CSS 側の現行掲載（mermaid 11.15.0 / markdown-it 14.2.0 / highlight.js 11.11.1 / dompurify 3.4.12 / github-markdown-css 5.9.0）は package.json の実依存と一致しており漏れなし。
<!-- SECTION:NOTES:END -->
