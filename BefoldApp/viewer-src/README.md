# viewer-src

viewer 用 JS のモジュールソース（ESM）。`npm run build:viewer` が esbuild で
`BefoldKit/Resources/viewer-bundle.js` へバンドルし、**成果物もリポジトリへコミットする**。

<!-- derived-from ../../backlog/tasks/task-432.1 - esbuild-のビルド経路と成果物コミットの仕組みを最小構成で通す.md -->

## ファイル構成

モジュールは**関心ごとに 1 つ**で、その中に純粋な計算と DOM 操作が同居する。
以前の `viewer.js`（純粋）/ `viewer-main.js`（DOM）という分け方は責務ではなく
テスト可能性で引いた境界で、同じ関心の 2 つの枝が離れて置かれ実際に乖離した
（ソース表示中の追記が別判定に育った = TASK-414）。テスト可能性は
ファイル境界ではなく `export` で担保する。

| ファイル | 責務 |
|---|---|
| `index.ts` | バンドルのエントリ。`exposeGlobals()` で公開関数をグローバルへ載せ、`_mmdInit()` を呼ぶ |
| `main.ts` | 公開面の barrel。エントリもテストハーネスもここだけを見る |
| `expose.ts` | barrel の export を反復して `globalThis` へ公開する `exposeGlobals()` |
| `init.ts` | 読み込み時の初期化（リスナ登録・注入値の反映）を 1 箇所に集約する |
| `bridge.ts` | Swift ホストとの境界。`postMessage` の送信口とホスト機能フラグ |
| `render.ts` | 描画の入口とチャンク追記のディスパッチ。「いま何の形を描いたか」の記録を持つ |
| `renderers.ts` | 表示種別ごとの `#diagram-wrap` 組み立て |
| `document-state.ts` | 直近に描画した内容とチャンク境界を保持する |
| `view-options.ts` | 表示モード・行番号・差分の設定を保持する |
| `doc-path.ts` | いま DOM に出ている文書のパスを追跡する |
| `scroll.ts` | スクロール対象の決定・位置の復元・位置変化の通知 |
| `keyboard.ts` | キーボード操作の配線と、キーからスクロール量を決める規則 |
| `zoom.ts` | 全体ズームとダイアグラム個別ズームの倍率保持と DOM への適用 |
| `find.ts` | 検索バーの状態・ハイライト・件数表示 |
| `path-refs.ts` | 本文中のパス参照の注釈付けと Swift への解決要求 |
| `reference-clicks.ts` | リンク/パス参照のクリック・コンテキストメニューを Swift へ伝える |
| `truncation.ts` | 段階読み込みバナーと「続きを読み込む」 |
| `markdown.ts` | markdown-it インスタンスの構成 |
| `vendor.ts` | npm 依存のベンダー（markdown-it / highlight.js / DOMPurify）の取り込み口 |
| `mermaid.ts` | mermaid の遅延ロード・設定・実行 |
| `color-scheme.ts` | ダークモードの現在値と変更通知 |
| `fonts.ts` | Swift が注入したフォント設定を CSS 変数へ反映する |
| `code-html.ts` | ソースコードのハイライトと行単位 HTML の組み立て |
| `diff-html.ts` | unified diff の解析とインライン/左右分割の HTML 組み立て |
| `csv-html.ts` | CSV/TSV の解析とテーブル/ソース表示の HTML 組み立て |
| `encoding.ts` | HTML エスケープと data URI / base64 の変換 |
| `viewer-globals.d.ts` | Swift が `window` へ注入する値の型宣言（値の一致は `ViewerBridgeContractTests` が担保） |

依存は `import` で表現し、**循環させない**（`npm run check:viewer-cycles`）。
循環するとモジュール評価順が壊れ、別モジュールのトップレベル値を `undefined` の
まま掴む。実際に `scroll.ts` は評価時に `doc-path.ts` の `_mmdDocPath` を読む。

Swift 側は `evaluateJavaScript("_mmdZoomIn()")` のような裸の呼び出しで到達するため、
バンドル（IIFE）の中身は `exposeGlobals()` でグローバルへ載せ直す。`export` した
時点で載るので、公開関数を増やすときの追記漏れは起きない。

`viewer.html` が body 末尾で読む script は **viewer-bundle.js 1 本だけ**。
markdown-it / highlight.js / DOMPurify は npm 依存としてこのバンドルに含まれる
（TASK-432.5）。取り込み口は `vendor.ts` の 1 箇所で、他のモジュールは
そこから import する（`window.hljs` のようなグローバル参照はしない）。
これらは常に構成済みなので「ベンダー未ロード」の縮退経路は存在しない。

mermaid（3.2MB）だけはバンドルへ入れない。CSV・ログ・コード等の mermaid 不使用
プレビューで無駄なパース/評価コストになるため、描画が必要になった時点で
`mermaid.ts` が `<script src="mermaid.min.js">` を挿して遅延ロードする。
その `mermaid.min.js` と 3 つのベンダー CSS は npm パッケージから
`npm run build:viewer-vendor`（`scripts/copy-viewer-vendor.mjs`）でコピーした
生成物で、バンドル同様コミットする。CSP は `script-src 'self'` のままで変わらない。

## TypeScript

<!-- derived-from ../../backlog/tasks/task-499 - viewer-src-の残り-22-本の-JS-を-TypeScript-へ移行しきる.md -->

**viewer-src のモジュールはすべて `.ts`**（TASK-432.4 で始めた段階移行を TASK-499 で
完了した）。`tsconfig.json` は `allowJs: false` で、`.js` を足すと import が解決
できずその場で落ちる。「解決対象には入るが型検査は受けない」という穴を残さないため。

- 型検査は `npm run typecheck:viewer`（`tsc --noEmit`）が単独で担当する。
  esbuild も babel も型注釈を落とすだけで検査しない。
- `tsconfig.json` の `include` はファイルの列挙ではなくディレクトリ全体。
  列挙にすると、追記漏れたモジュールが「型が付いた見た目のまま一度も
  検査されない」状態で静かに残る。
- Oxlint は `.ts` で `no-undef` を使わない。未定義参照の担保は `tsc` 側にある
  （型宣言を未定義と誤検知するため）。viewer-src 向けの緩和は TASK-499 で
  撤去済みで、いま残るのは `no-underscore-dangle`（`_mmd` 接頭辞が Swift との契約）と
  `prefer-query-selector`（`getElementById` は意図した選択）の 2 つだけ。
- Jest は `moduleFileExtensions` を `ts` → `js` の順にしてある。esbuild の
  既定の解決順と同じにすることで、同名の `foo.js` と `foo.ts` が並んだ場合でも
  テストと本番が同じファイルを見る。

`import` 指定子の拡張子は `./bridge.js` のまま書く（esbuild も tsc も `.js` 指定を
`.ts` へ解決する）。**ただしエントリだけは拡張子解決が効かない。** `index.ts` の
パスは `package.json` の `build:viewer` と `scripts/check-viewer-cycles.mjs` が
直接持っているので、エントリを動かすときは両方を併せて変える。

### バンドルが strict mode になる

`tsconfig.json` を置いた時点で、esbuild は成果物の先頭に `"use strict"` を出す
（`strict: true` が含む `alwaysStrict` を尊重するため）。実測では、これは移行済み
`.ts` の有無とは無関係で、`.js` だけのグラフでも付く。

これは意図した状態である。ソースは ESM（常に strict）として書かれ、Jest 側は
babel が CommonJS へ落とす際に `"use strict"` を付けるため、**テストは以前から
strict で走っていた**。付けないと、出荷される成果物だけが sloppy mode という
テストと本番のずれが残る。

`alwaysStrict: false` を書けば抑止できるが、そうしないこと。抑止は上のずれを
復活させる。

## なぜここに置くか

`BefoldKit/` 配下に置くと、SPM（`Package.swift` の `exclude`）と XcodeGen
（`project.yml` の `sources` / `excludes`）の両方で除外設定が要る。ターゲットの
`path` の外に置けばどちらも触らずに済むため、`BefoldApp/viewer-src/` を採用した。

## なぜ成果物をコミットするか

`swift build` / `xcodebuild` に Node 依存を持ち込まないため。macOS の CI ジョブには
`setup-node` が無く、ビルド時に Node を要求すると全ビルド経路が Node に依存する。
代わりにコミット済み成果物とソースのズレを CI（ubuntu の js-test ジョブ）で検出する。

## コマンド

```bash
npm run build:viewer         # ソースからバンドルを生成する
npm run build:viewer-vendor  # npm から mermaid.min.js / ベンダー CSS をコピーする
npm run check:viewer-bundle  # 再ビルドしてコミット済み成果物との差分を検出する
npm run check:third-party-licenses  # THIRD_PARTY_LICENSES.md と実際の依存を突き合わせる
npm run lint:viewer          # ESLint（no-undef で未定義参照を機械検出する）
npm run typecheck:viewer     # tsc --noEmit（型検査。対象は .ts のみ）
npm run check:viewer-cycles  # モジュール間の循環 import を検出する
npx jest                     # Jest テスト（BefoldKit/Resources/__tests__/）
```

`check:viewer-bundle` はローカルでも CI と同じコマンドで確認できる。差分が出たら
`npm run build:viewer` の結果をコミットする。

テストは成果物ではなくこのディレクトリのソースを対象にする。DOM を要さない純粋関数は
`main.ts` を直接 require し、DOM 側は `__tests__/support/viewerMainHarness.js` が
esbuild でテスト用エントリを IIFE にまとめて jsdom の `window.eval` で評価する。

## Node バージョン

`.nvmrc` と `package.json` の `engines.node` で 24 に揃える（CI の js-test ジョブが
Node 24 固定のため）。esbuild は `package.json` で exact 指定しており、同一版なら
出力はバイト単位で決まる。
