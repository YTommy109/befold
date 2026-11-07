---
paths:
  - "**/*.{ts,tsx,js,mjs}"
  - "**/.oxlintrc.json"
  - "**/.oxfmtrc.json"
---

# JS/TS コーディング規約（Oxlint / Oxfmt）

方針は **リポジトリルートの `.oxlintrc.json` と `.oxfmtrc.json` が単一の情報源**。
`site/.oxlintrc.json` と `BefoldApp/.oxlintrc.json` がそれを `extends` して、
検査対象（`ignorePatterns`）と面ごとの緩和だけを持つ。

- カテゴリは correctness / suspicious / perf / pedantic を error。style と
  restriction は入れない（`no-magic-numbers`・`sort-keys`・`no-null` のように、
  このコードベースが意図して選んでいる書き方を否定するため）
- **ルールを個別に無効化するときは必ず理由を書く。** 理由の無い無効化は、次に
  そのルールが必要になったときに「意図して外したのか、たまたま鳴って外したのか」を
  区別できなくする。設定ファイル内の既存の無効化はすべて理由つきになっている
- **`viewer-src/` は全モジュールが TypeScript（TASK-499）。** TASK-498 で入れていた
  暫定緩和の override は撤去済みで、`BefoldApp/.oxlintrc.json` に残る**緩和**は
  `no-underscore-dangle`（`_mmd` 接頭辞が Swift との契約）と
  `prefer-query-selector`（`getElementById` は意図した選択）の 2 つだけ。
  どちらも移行と無関係な恒久的な選択で、TS 化しても消えない。
  `viewer-src/**` にはもう 1 つ override があるが、そちらは緩和ではなく
  **type-aware ルールの再有効化**（TASK-508。下の `no-unsafe-*` の項を参照）
- **`site/` と `BefoldApp/` の両方で型情報を使う lint（`oxlint --type-aware`）を回している。**
  目的はどちらも `no-floating-promises` / `no-misused-promises` / `await-thenable` の
  3 つ。site/ は await し忘れた D1 書き込みがリクエスト終了で黙って消えるため（TASK-505）、
  BefoldApp/ は描画の完了を待たない Promise が「たまに古い内容が残る」形で出るため
  （TASK-499）。導入時の実測で viewer-src の 2 箇所が引っかかり、どちらも意図した
  fire-and-forget だったので `void` を置いて明示した
- **`no-unsafe-*` はプロジェクトレベルでは両面とも off。** BefoldApp の
  `no-unsafe-*` は実測（TASK-623.4、2026-09-15）で viewer-src 0 件・`viewer-test` 47 件・
  `scripts/*.mjs` 94 件。viewer-test はテストも support もすべて .ts（TASK-623）で、
  残る 47 件のうち 39 件は `no-unsafe-type-assertion`（DOM の取得結果やブリッジの
  payload を `as` で絞る書き方）。scripts は型情報の無い .mjs で、その TS 化は別の判断。
  件数のある面で error にしないため、プロジェクトレベルでは off にする
- **プロジェクトレベルの off の一覧は `site/.oxlintrc.json` と
  `BefoldApp/.oxlintrc.json` で揃える**（片方だけ緩めると、どちらの面が厳しいのか
  分からなくなる）。一方で、**型情報が揃っているディレクトリでの再有効化は
  override 側で行い、両面で揃えない**。実際 `BefoldApp/viewer-src/**` では
  `no-unsafe-*` ほか 12 ルールを error に戻してあるが（TASK-508）、site/ は外部
  JSON（GitHub API・Access の JWKS）を any から絞る箇所で `no-unsafe-*` が
  100 件超残るため同じことができない。**override へルールを足すときは、その
  ディレクトリでの実測件数を必ずコメントに書く**。件数のあるルールを持ち込むと、
  override が「直すべき指摘の置き場」に変わってしまう
- 整形のセミコロンは面ごとに違う（`site/` は無し、`BefoldApp/` は有り）。
  どちらも既存の慣習をそのまま固定したもので、揃えようとしない
- oxfmt の対象は **JS/TS だけ**。Markdown は markdownlint-cli2 が持っている
  （既定のままだと oxfmt が backlog と docs の .md 812 件まで書き換える）
- CI（`ci.yml` の js-test / `site.yml` の test）と pre-commit（`scripts/oxc-lint.sh`）の
  両方で落とす。lint も整形もその場で機械的に直せるので、警告に留めない
