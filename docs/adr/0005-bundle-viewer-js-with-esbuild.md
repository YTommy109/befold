# ADR 0005: viewer の JS を esbuild でバンドルし、成果物をコミットする

- ステータス: Accepted
- 日付: 2026-08-10
- backlog decision: decision-5

<!-- derived-from ../dev/viewer-rendering-dataflow.md -->

## Context

### 現状の構造

`BefoldApp/BefoldKit/Resources/` の自前 JS は 2 ファイルで、合計 2,812 行ある。

| ファイル | 行数 | 役割 |
|---|---|---|
| `viewer-main.js` | 1,873 | DOM 操作・ブラウザ副作用・Swift ブリッジ |
| `viewer.js` | 939 | 純粋ロジック（DOM に触らない） |

どちらもモジュールシステムを使っていない。`import` / `export` は 0 件、`window.` へのグローバル
代入も 0 件、IIFE でもない。トップレベルの `var` / `function` 宣言がそのままグローバルになる。

`viewer-main.js` は全行が 2 スペースインデントされているが、それを包む関数は存在しない
（`grep -nE "^[^ \t]" viewer-main.js` が 0 件）。インデントは見た目だけで、すべての識別子は
真のグローバルである。この形は、コミット `bf50bfa`「fix: postMessage ブリッジをゲートし CSP から
unsafe-inline を削除する」で `viewer.html` のインライン `<script>` から外部ファイルへ切り出した
ときのインデントがそのまま残ったもの。

ファイル間の依存は共有グローバルスコープ経由で解決している。`viewer-main.js` は `viewer.js` が
宣言した識別子を裸の名前で参照する（`viewer-main.js` の `ZOOM_DEFAULT` / `parseStoredZoom` /
`mermaidTheme` / `highlightCode` / `sanitizeRenderedHtml` / `renderShape` ほか）。
この解決を成立させているのは `viewer.html` のスクリプト記述順だけであり、依存関係は言語機能で表現されていない。

両ファイルの末尾には jest 用の CommonJS エクスポート境界だけが置かれている
（`viewer.js` / `viewer-main.js` の末尾の `module.exports`）。ブラウザには `module` が無いため即時初期化へ落ちる。

### 分割軸が責務ではない

`viewer.js` の冒頭コメントは「テスト可能な純粋ロジック」で、分割軸が**責務ではなくテスト可能性**で
引かれている。その結果、同じ関心の 2 つの枝が離れた場所に置かれ、実際に乖離した
（TASK-414: `appendChunk` と `render` の表示モード判定、`_renderSource` の注釈呼び出し漏れ）。

変更履歴でも、この 2 ファイルは他の大きいファイルより修正の比率が高い。

| ファイル | 全コミット | うち `fix` | 比率 |
|---|---|---|---|
| `viewer-main.js` | 25 | 12 | 48% |
| `viewer.js` | 23 | 10 | 43% |
| `ViewerStore.swift` | 47 | 18 | 38% |
| `ViewerWindowManager.swift` | 67 | 19 | 28% |

### 制約 1: `file://` ではネイティブ ES モジュールが使えない

`BefoldRenderKit/ViewerWebViewFactory.swift` の `ViewerWebViewFactory.makeWebView` は viewer.html を
`webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)` で読み込む。WebKit は
`file://` の各 URL を不透明オリジンとして扱うため、`<script type="module">` は CORS で
遮断される。回避には `allowFileAccessFromFileURLs` 相当の非公開プリファレンス緩和が要る。

これは `viewer.html` の `Content-Security-Policy` meta と、それを検証しているテストに正面から反する。

```html
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; frame-src blob:; connect-src 'none'; base-uri 'none'">
```

`befoldTests/ViewerBridgeContractTests.swift` の `cspScriptSrcHasNoUnsafeInline` は、CSP の `script-src` に
`'unsafe-inline'` が無いことと、HTML にインライン `<script>` が無いことをテストしている。

つまり「モジュール境界が欲しいがネイティブ ESM は使えない」という制約が、単一の巨大な
クラシックスクリプトを生んでいる構造的な原因である。

### 制約 2: ビルド成果物を生成するフックが無い

- `BefoldApp/Package.swift` の `BefoldKit` ターゲットの `resources:` はリソースを**個別に列挙**している。
  SPM のビルド時点でファイルが存在している必要がある。
- `BefoldApp/project.yml` に `preBuildScripts` / `postCompileScripts` / `postBuildScripts` は無い。
  生成済み `project.pbxproj` の `PBXShellScriptBuildPhase` は 0 件。
- SwiftPM のビルドツールプラグインはサンドボックス内で実行されネットワークを持たないため、
  `npm ci` を挟めない（**未検証の前提**。`swift build` 中にプラグインから `npm --version` を
  実行して確認できる）。

### 制約 3: macOS の CI ジョブに Node が無い

`.github/workflows/ci.yml` の `build-and-test`（macos-26）と `thread-sanitizer`（macos-26）に
`setup-node` は無い。Node があるのは js-test ジョブ（ubuntu-latest、`npm ci`、`npx jest`）だけ。

### 既存の前例

`site/` は既に TypeScript + vitest + esbuild（wrangler 経由）で動いており、リポジトリに
TS ツールチェーンの前例がある（`site/package.json`、`site/vitest.config.ts`）。

`BefoldApp/package.json` の devDependencies には、同梱ベンダーライブラリと同じバージョンが
既にピン留めされている（dompurify 3.4.12 / github-markdown-css 5.9.0 / highlight.js 11.11.1 /
markdown-it 14.2.0）。mermaid だけは記録が無い。

## Decision

viewer の JS を **esbuild で単一の IIFE バンドルへまとめ、その成果物をリポジトリへコミットする**。

### バンドラに esbuild を選ぶ

- `format: 'iife'` の出力は `file://` + `script-src 'self'` にそのまま適合する。CSP を緩めずに
  モジュール境界が手に入る、現実的に唯一の経路である。
- 同梱済みの `mermaid.min.js` 自体が esbuild の ESM バンドル出力である
  （先頭が `"use strict";var __esbuild_esm_mermaid_nm;`）。
- TypeScript を追加ツールなしで扱える。

### 成果物をコミットし、一致を CI で検証する

制約 2 と 3 より、`.app` のビルド経路に npm を挟むことはできない。成果物をリポジトリに置き、
`.github/workflows/ci.yml` の js-test ジョブ（Node がある側）で「コミットされた成果物が
ソースからの再ビルド結果と一致するか」を検証してズレを落とす。

これは既存の `swift package plugin ... swiftformat -- --lint`（生成物を持ち、ズレを CI で落とす）
と同じ形であり、`project.pbxproj` を xcodegen の生成物として扱う既存の運用とも整合する。

### mermaid はバンドルに含めない

`viewer-main.js` の mermaid 遅延ロード（現在は `viewer-src/mermaid.ts` の
`_mmdEnsureMermaidLoaded`）に設計意図が記録されている。

> mermaid.min.js（3.2MB）は CSV・ログ・コード・SVG・HTML ソース等の mermaid 不使用
> プレビューでは無駄なパース/評価コストになるため、mermaid を実際に描画する瞬間まで
> ロードを遅延する。

`script.src = 'mermaid.min.js'` による DOM 挿入ロードは維持する。

### TypeScript は段階移行にする

バンドル基盤が入った後、`allowJs` でファイル単位に移行する。ただし **ESM 化の段階から型検査
（または同等の未定義参照検出）を有効にする**。裸のグローバル参照を import へ置き換える作業で
付け忘れた識別子は、バンドル時にエラーにならず実行時に初めて落ちるためである。この移行の
いちばん危険な部分を無検証にしない。

### 責務分割はモジュール境界を得てから行う

TASK-420（viewer-main.js を責務ごとに分割）は、その受け入れ条件 #3 が
「viewer.html からの読み込み順が壊れず」であるとおり、暗黙の読み込み順契約を保ったままの分割を
前提にしている。これはバンドル導入後にやり直しになるため、TASK-420 は本 ADR に基づく
サブタスクへ統合し、二度手間を避ける。

## Consequences

### 得られるもの

- 依存が `import` で明示され、`viewer.html` の記述順という暗黙の契約が消える。
- 分割軸を「テスト可能性」から「責務」へ引き直せる。TASK-414 で起きた乖離の再発経路が減る。
- 未定義参照が機械検出できる。現状はグローバル名前空間の衝突も取りこぼしも静かに通る。
- 行数の肥大化に対して分割が自然な操作になり、TASK-428 のラチェットを JS へ広げる意味が出る。
- 手動ベンダリングを npm 依存へ移す道が開く（`package.json` に既に 4 つがピン留め済み）。

### 受け入れるコスト

- **生成物をリポジトリに持つ。** 差分レビューにノイズが乗り、マージコンフリクトの原因になる。
  ズレは CI の一致検証で落とすが、コミット漏れの手戻りは発生する。
- **Node が開発の前提に加わる。** 現状 `swift build` / `xcodebuild` は Node 非依存で完結する。
  JS を触る開発者は `npm ci` が必要になる。ローカルの Node バージョンを固定する仕組み
  （`.nvmrc` / `engines`）は現在存在せず、併せて用意する必要がある。
- **既存テストの移行。** `__tests__/` は 6 ファイル 3,716 行・370 ケースあり、すべて CommonJS
  `require()` で書かれている。`support/viewerMainHarness.js`（144 行）は jsdom へ
  `viewer.html` を読み込み、`window.eval` で `viewer.js` → `viewer-main.js` の順に評価して
  グローバル共有を再現している。ESM 化でこのハーネスは成立しなくなるため書き換えが要る。
- **`ViewerBridgeContractTests` の向き先変更。** このテストは JS を文字列として読んで
  Swift ↔ JS の契約を検証しており、`viewer.html` / `viewer.js` / `viewer-main.js` への
  リテラル参照が 11 箇所ある。バンドル後は成果物を見るよう向け直す。実際に配布される物を
  検証する形になるため、方向としては改善である。
- **`Package.swift` のリソース列挙の更新。** `BefoldKit` のリソースを個別に列挙しているため、
  成果物の追加・旧ファイルの削除に追随が要る（`project.yml` 側は
  `BefoldKit/Resources` をディレクトリごと resources ビルドフェーズに入れているため追随不要）。

### 却下した代替案

**ネイティブ ES モジュールを使う。** `file://` の不透明オリジンにより CORS で遮断される。
非公開プリファレンスでの緩和は、ローカルの信頼できないファイルを描画する本アプリの脅威モデルと
CSP 設計に反する。

**成果物をコミットせず CI と各開発者のビルド時に生成する。** macOS の CI ジョブへ Node の
セットアップが必要になるうえ、SPM のリソース解決がビルド開始時点でファイルの存在を要求する。
プラグインのサンドボックス制約（制約 2）を踏まえると、SPM のビルド内で生成する手段が無い。

**素の JS のまま責務分割を続ける（TASK-420 の当初方針）。** 分割はできるが、依存解決が
`viewer.html` の読み込み順という暗黙の契約に載ったままになる。ファイル数が増えるぶん、
順序の制約はむしろ壊れやすくなる。
