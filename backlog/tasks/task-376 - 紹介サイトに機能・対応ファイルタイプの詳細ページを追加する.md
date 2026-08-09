---
id: TASK-376
title: 紹介サイトに機能・対応ファイルタイプの詳細ページを追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 11:47'
updated_date: '2026-08-08 20:57'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 615750
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在の紹介サイト（site/）は `/` の 1 ページのみで、機能の記述も LP 内の「機能」セクションに要約が並ぶだけになっている。そのため「Mermaid ビューア mac」「.mmd プレビュー」のような具体的なロングテール検索や、LLM 経由での参照に対して、拾われる語が不足している。

対応ファイルタイプ・機能・キーボードショートカット・FAQ を網羅した詳細ページを 1 枚追加し、検索と AI 双方からの入口を増やす。

方針:
- AI 専用ページ（llm.txt 等）ではなく、人間が読んで有用な通常ページとして作る。薄いコンテンツ扱いを避けるため。
- 既存の LP（`site/src/views/landing.tsx`）はコンバージョン用としてそのまま残し、詳細は新ページへ内部リンクする。
- LP と同じく日英併記とする。
- 対応ファイルタイプ表は BefoldKit の `FileType` が単一の情報源。ページに手書きした一覧は実装とずれるため、生成するか、ずれたら落ちるテストで担保する。

参考: TASK-360 で JSON-LD / robots.txt / sitemap.xml を導入済み。新ページもその仕組みに載せる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 詳細ページが公開ルートとして配信される（機能一覧・対応ファイルタイプ表・キーボードショートカット・FAQ を含む）
- [x] #2 ページの本文が LP と同じく日英併記になっている
- [x] #3 対応ファイルタイプ表が BefoldKit の FileType 定義とずれた場合に落ちるテストがある（または表が FileType から生成されている）
- [x] #4 FAQ セクションに FAQPage の JSON-LD が出力される
- [x] #5 sitemap.xml に新ページの URL が含まれる
- [x] #6 LP から詳細ページへの内部リンクがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
（/review-design 反映後）

1. site/src/lib/file-types.ts を新設する。
   - FILE_TYPE_GROUPS: 種別ごとの表示用データ（ja/en ラベル・拡張子配列・レンダリング/ソース表示の可否）。詳細ページの対応ファイルタイプ表はこれだけを情報源にする。
   - parseSwiftFileTypes(source): FileType.swift のテキストから 'public static let <name> = [...]' / '[String: String]' 宣言を**総当たりで**拾い、{ グループ名 -> 拡張子 Set } を返す純関数。既知の定数名を決め打ちで読まない（レビュー指摘 A）。
2. vitest.config.ts で BefoldApp/BefoldKit/FileType.swift を config 時に読み、TEST_FILE_TYPE_SWIFT バインディングでテストへ渡す（readD1Migrations と同じ手口。workers pool は node:fs を持たないため）。読めなければ **その場で throw** する（空文字で素通りさせない。レビュー指摘 B）。test/env.d.ts に型を追加。
3. site/test/file-types.test.ts:
   - FILE_TYPE_GROUPS の拡張子集合 == Swift 由来の全拡張子集合（AC#3）
   - パースで拾ったグループ名の集合 == 期待リスト → FileType.swift に新グループが増えたら落ちる（指摘 A）
   - 各グループが 1 件以上 → パーサ破損時に空集合で素通りしない（指摘 A）
   - landing.tsx の『多彩なフォーマット対応』文言に現れる拡張子が FILE_TYPE_GROUPS に含まれる（指摘 C: 手書き一覧の二重管理を残さない）
4. site/src/views/shared.tsx へ REPO_URL / DOWNLOAD_URL / LANG_SCRIPT / Feature 型 / FEATURES / MORE_FEATURES / 言語切替ヘッダを切り出し、**landing.tsx 側の定義は削除する**（複製しようがない構造で共有を担保。指摘 D）。
5. site/src/views/features.tsx: 詳細ページ。日英併記（既存の lang+hidden 方式・/style.css を流用）。構成は 機能一覧 / 対応ファイルタイプ表 / キーボードショートカット / FAQ。
   - 表の下に『これ以外の拡張子はプレーンテキストとして開きます / Any other extension opens as plain text』を日英で置く（指摘 E: 表は allExtensions であって開ける全部ではない）。
   - head に canonical(/features)・OGP・FAQPage JSON-LD を出力（AC#1,2,4）。
6. site/src/routes/public.tsx: GET /features を追加（recordEvent は呼ばない / Cache-Control: public, max-age=3600）。sitemap.xml に <loc>{origin}/features</loc> を追加（AC#5）。
7. landing.tsx: 機能セクションから /features への内部リンクを追加（AC#6）。
8. site/public/style.css: 表・FAQ・ショートカット一覧のスタイルを追加。
9. site/test/public.test.ts: /features が 200 で日英両方の本文を含む・FAQPage JSON-LD が妥当・sitemap に含まれる・LP にリンクがある。
10. site/ で npm test / npm run typecheck。

判断メモ:
- /features では recordEvent を呼ばない。events スキーマ（src/schema.ts）に path 列がなく、visit を計上すると LP からの新規獲得の指標に別ページの訪問が混ざるため（robots.txt / sitemap.xml と同じ扱い）。計測しないので CDN キャッシュ可能で、Cache-Control を付けられる。
- キーボードショートカット表と MainMenuBuilder の同期テストは本タスクの範囲外（AC#3 は対応ファイルタイプ表のみ）。別タスクとして起票する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 検証（実測）

- `cd site && npx vitest run` → 7 files / 104 tests passed（追加分: test/file-types.test.ts 8 件、test/public.test.ts の GET /features 5 件・LP 導線 1 件・sitemap 1 件）
- `cd site && npm run typecheck` → エラーなし
- ずれ検知が実際に落ちることを変異注入で確認（いずれも確認後 git checkout で復元）:
  - FileType.swift の pdfExtensions に "xps" を追加 → 「表の拡張子が FileType.swift の全拡張子と一致する」が失敗
  - FileType.swift に archiveExtensions を新設 → 宣言一覧・リテラルグループ・拡張子集合の 3 件が失敗（新グループの取りこぼしを検知できる）
  - ContentLoader.maxFileSizeBytes を 50→64MB に変更 → 「表のサイズ上限が Swift 側の定数と一致する」が失敗
- `npx wrangler dev --local` で実描画を確認。GET /features は 200・Cache-Control: public, max-age=3600、sitemap.xml に / と /features の 2 件。

## 実装上の判断

- **サイズ上限も表に載せ、ずれ検知の対象にした。** 実装を読むと上限は 1 つではなく 3 系統ある（NormalizedTextCache.maxFileSizeBytes=100MB / ContentLoader.maxTextFileSizeBytes=10MB / ContentLoader.maxFileSizeBytes=50MB）。LP の「最大 100MB」はチャンク対応形式だけに当てはまる値で、Mermaid・SVG・HTML は 10MB、画像・PDF は 50MB。詳細ページで誤解を招かないよう 3 系統を明示し、vitest.config が該当 2 ファイルも読んで定数と突き合わせる。
- **共有は構造で担保した。** REPO_URL / DOWNLOAD_URL / LANG_SCRIPT / FEATURES / MORE_FEATURES / ヘッダ・フッタは src/views/shared.tsx が唯一の定義箇所で、landing.tsx 側の定義は削除した（複製できない形にする）。動作要件の文字列も REQUIRED_OS / REQUIRED_OS_JA に寄せ、LP の JSON-LD・本文と同じ定数を使う。
- **/features は visit として記録しない。** events テーブル（src/schema.ts）がページを区別する列を持たず、計上すると LP からの新規獲得の指標に混ざるため。計測しない代わりに Cache-Control を付けられる。
- **キーボードショートカットは stable ビルドで必ず存在するものだけを載せた。** 表示モードの ⌘1〜⌘4 は MainMenuBuilder.addDisplayModeItems がフィーチャーゲートで項目数を変えるため除外。⌃⌘G（変更ファイルのみ表示）も同様に除外。実装とのずれ検知は TASK-384。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
紹介サイトに /features（機能・対応ファイルタイプ・キーボードショートカット・FAQ）を日英併記で追加した。対応ファイルタイプ表は BefoldKit の FileType.swift とサイズ上限の定数（ContentLoader / NormalizedTextCache）を vitest.config 経由で読み込み、拡張子集合・宣言一覧・上限値がずれたら test/file-types.test.ts が落ちる。LP・詳細ページで重複していた定数と機能リストは src/views/shared.tsx へ集約し、LP 側の定義を削除して複製できない形にした。sitemap.xml に /features を追加し、FAQ には FAQPage の JSON-LD を出力、LP からの内部リンクを設置。site の vitest 104 件と tsc が通ることと、変異注入 3 種でずれ検知が実際に落ちることを実測で確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
