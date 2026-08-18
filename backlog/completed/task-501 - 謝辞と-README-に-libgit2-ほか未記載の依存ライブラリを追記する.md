---
id: TASK-501
title: 謝辞と README に libgit2 ほか未記載の依存ライブラリを追記する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-16 10:52'
updated_date: '2026-08-17 14:52'
labels:
  - chore
dependencies: []
priority: high
type: chore
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
- [x] #1 THIRD_PARTY_LICENSES.md に libgit2 の節が追加され、GPLv2 with linking exception の全文と同梱第三者コードの告知が収録されている
- [x] #2 README.md:71 の謝辞表に libgit2 の行（役割: git 差分の取得、ライセンス: GPLv2 with linking exception）が追加されている
- [x] #3 配布物に含まれる第三者コードを棚卸しし、掲載対象・非対象（ビルド時のみのツールなど）とその理由が Implementation Notes に記録されている
- [x] #4 棚卸しで判明した libgit2 以外の未記載ライブラリがあれば同様に両方へ追記されている
- [x] #5 Help > OSS 謝辞パネルで追記後の内容が表示されることを実機で確認している
- [x] #6 BefoldApp/scripts/check-third-party-licenses.mjs の SWIFT_COMPONENTS に libgit2 を追加し、npm run check:third-party-licenses が版ずれを検出できる状態になっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. libgit2 の COPYING（pin 済み revision 52287b09 = v1.9.2）を取得し、同梱第三者コード（zlib / PCRE / winhttp / wildmatch / OpenSSL headers 等）の告知が COPYING に含まれることを確認する → 確認済み。COPYING 全文を再掲すれば同梱物の告知は充足する。
2. THIRD_PARTY_LICENSES.md に libgit2 の行（1.9.2 / GPL-2.0-only WITH linking-exception）と全文セクションを追加する。
3. README.md:71 の謝辞表に libgit2 の行を追加する。
4. check-third-party-licenses.mjs の SWIFT_COMPONENTS に libgit2 を追加する。exact 指定の依存なので、存在確認だけでなく Package.swift の exact 版と表の版が一致することも見る。
5. npm run check:third-party-licenses と swift test（HelpPanelResourceTests）で検証する。
6. 掲載対象外の判断を Implementation Notes に残す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査結果（起票時、2026-08-16）:
- 謝辞の実体は BefoldApp/BefoldKit/Resources/THIRD_PARTY_LICENSES.md の 1 ファイル。表 :9-17 と全文 :21-718。Help > OSS 謝辞（OSSLicensesView.swift:4-24）はこれをバンドルから読んで表示するだけなので、この 1 ファイルと README.md:71-79 の表を直せば両面に反映される。
- 整合性チェッカ BefoldApp/scripts/check-third-party-licenses.mjs は SWIFT_COMPONENTS（:37-40）に Sparkle と swift-argument-parser しか持たず、libgit2 の欠落を検出できない。ここを直さないと同じ漏れが再発する。
- libgit2 は ibrahimcetin/libgit2 を SPM のソースターゲットとして直接ビルドし、C API を import libgit2 で直接呼ぶ形（Package.swift:16, GitLibrary.swift:1-3）。SwiftGit2 等のラッパーは経由しない。ライセンス上の位置づけ（GPLv2 with linking exception、静的リンク可）は docs/adr/0006-git-integration-via-libgit2.md:127-131 に既に記録済みで、謝辞側だけが追随していない。
- 掲載対象外と判断してよいもの: SwiftLintPlugins 0.65.0 / SwiftFormat 0.61.1（ビルドツールプラグイン、配布物に非同梱）、esbuild / jest / babel / jsdom / typescript / oxlint / oxfmt（開発時のみ）、site/ の hono ^4.6.14・zod ^3.24.1（Cloudflare Worker 側でアプリには同梱されない）。site には謝辞ページ自体が存在しない。
- 自作 CGitShim は第三者コードではないため掲載不要。
- 同梱 JS/CSS 側の現行掲載（mermaid 11.15.0 / markdown-it 14.2.0 / highlight.js 11.11.1 / dompurify 3.4.12 / github-markdown-css 5.9.0）は package.json の実依存と一致しており漏れなし。

実装内容:
- THIRD_PARTY_LICENSES.md に libgit2 の行（1.9.2 / GPL-2.0-only WITH linking exception）と全文セクションを追加した。全文は Package.resolved が pin している revision 52287b09（= libgit2 v1.9.2）の COPYING をそのまま再掲。libgit2 が同梱する第三者コード（zlib / Clar / PCRE / winhttp+LGPL 2.1 全文 / wildmatch / OpenSSL ヘッダ / Team Explorer Everywhere / RFC 1320 ほか）の告知は COPYING に含まれているため、これ 1 本で足りる。節の冒頭に「静的リンクしている」「対応するソースは上流 URL から入手できる」旨を英日で添えた。
- ibrahimcetin/libgit2 は upstream の fork に Package.swift を足しただけで、独自の LICENSE ファイルを持たない（リポジトリ直下に COPYING のみ）。したがってパッケージ化部分について別立ての告知は不要。
- README.md の謝辞表に libgit2 の行を追加した。
- check-third-party-licenses.mjs の SWIFT_COMPONENTS に libgit2 を追加。exact 指定の依存なので、存在確認に加えて Package.swift の exact 版と表の版の一致も見るようにした（第 3 要素 "exact"）。from: 指定の Sparkle / swift-argument-parser は表側が "2.x" のような幅を持つ記載のため従来どおり存在確認のみ。

掲載対象外とした依存とその理由:
- SwiftLintPlugins 0.65.0 / SwiftFormat 0.61.1: ビルドツールプラグインで .app に入らない
- esbuild / jest / babel / jsdom / typescript / oxlint / oxfmt: 開発時のみ
- site/ の hono ^4.6.14 / zod ^3.24.1: Cloudflare Worker 側でアプリに同梱されない。site には謝辞ページ自体が無い
- CGitShim: 自作の C シムで第三者コードではない

検証:
- npm run check:third-party-licenses が OK（node_modules 未導入では npm ci を求めて落ちるため、npm ci 後に実行）。
- 追加した検査が実際に落ちることを確認した（表の版を 1.9.1 に書き換える → "THIRD_PARTY_LICENSES.md の 1.9.1 と Package.swift の 1.9.2 が食い違う"、行を消す → "表に行が無い"）。どちらも復元後に OK へ戻る。
- swift test --filter HelpPanelResourceTests が 3 件パス。
- xcodegen generate + xcodebuild build（Debug）が成功し、befold.app/Contents/Frameworks/BefoldKit.framework/.../THIRD_PARTY_LICENSES.md に libgit2 の行（18 行目）と節（723 行目）が入ることを確認。
- その Debug ビルドを起動して Help > オープンソースソフトウェア謝辞 を開き、表に libgit2 / 1.9.2 / GPL-2.0-only WITH linking exception の行が出ることをスクリーンショットで確認した。
- markdownlint-cli2 は 0 件（THIRD_PARTY_LICENSES.md は glob 対象外、README.md は対象で 0 件）。oxlint / oxfmt も 0 件。

実測メモ（GUI 確認の落とし穴）: /Applications/befold.app が同時に起動していると、System Events の
`window ... of application process "befold"` が別プロセスのウィンドウへ解決することがある。unix id で
プロセスを特定しても起きたため、最初は「新しいビルドなのに表が 7 行のまま」という誤った観測をした。
バンドル内の md にマーカー文字列を仕込んで撮り直し、どちらのプロセスを見ているかを確定させて解消した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
libgit2（GPL-2.0-only WITH linking exception、v1.9.2）を THIRD_PARTY_LICENSES.md と README.md の謝辞へ追記した。全文は pin 済み revision の COPYING をそのまま再掲しており、libgit2 が同梱する zlib / PCRE / winhttp(LGPL 2.1) 等の告知もこれに含まれる。あわせて check-third-party-licenses.mjs に libgit2 を登録し、exact 指定の依存については Package.swift の版と表の版の一致まで検査するようにした（同じ漏れの再発防止）。検証: npm run check:third-party-licenses が OK で、版を書き換える／行を消す操作で実際に落ちることを確認。swift test --filter HelpPanelResourceTests 3 件パス。xcodebuild で作った .app のバンドル内リソースに反映されていること、および起動して Help > オープンソースソフトウェア謝辞 に libgit2 の行が表示されることをスクリーンショットで確認。掲載対象外（SwiftLint/SwiftFormat プラグイン、開発時のみの npm 依存、site の hono/zod、自作 CGitShim）の判断理由は Notes に記録した。
<!-- SECTION:FINAL_SUMMARY:END -->
