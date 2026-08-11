# viewer-src

viewer 用 JS のモジュールソース（ESM）。`npm run build:viewer` が esbuild で
`BefoldKit/Resources/viewer-bundle.js` へバンドルし、**成果物もリポジトリへコミットする**。

<!-- derived-from ../../backlog/tasks/task-432.1 - esbuild-のビルド経路と成果物コミットの仕組みを最小構成で通す.md -->

## ファイル構成

| ファイル | 責務 |
|---|---|
| `index.js` | バンドルのエントリ。`exposeGlobals()` で公開関数をグローバルへ載せ、`_mmdInit()` を呼ぶ |
| `viewer.js` | 純粋ロジック（DOM 非依存）。トークナイザ・HTML 組み立て・ズーム計算など |
| `viewer-main.js` | DOM 描画と type ディスパッチ。`viewer.js` から `import` する |
| `expose.js` | 名前空間オブジェクトを反復して `globalThis` へ公開する `exposeGlobals()` |

Swift 側は `evaluateJavaScript("_mmdZoomIn()")` のような裸の呼び出しで到達するため、
バンドル（IIFE）の中身は `exposeGlobals()` でグローバルへ載せ直す。`export` した
時点で載るので、公開関数を増やすときの追記漏れは起きない。

`viewer.html` は body 末尾で **markdown-it → highlight.js → DOMPurify →
viewer-bundle.js** の順に読む。ベンダーライブラリはバンドルに含めず、グローバル参照
のまま使う。mermaid（3.2MB）はさらに遅く、描画が必要になった時点で
`viewer-main.js` が動的に `<script>` を挿して遅延ロードする。CSP は
`script-src 'self'` のままで変わらない。

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
npm run check:viewer-bundle  # 再ビルドしてコミット済み成果物との差分を検出する
npm run lint:viewer          # ESLint（no-undef で未定義参照を機械検出する）
npx jest                     # Jest テスト（BefoldKit/Resources/__tests__/）
```

`check:viewer-bundle` はローカルでも CI と同じコマンドで確認できる。差分が出たら
`npm run build:viewer` の結果をコミットする。

テストは成果物ではなくこのディレクトリのソースを対象にする。純粋ロジックは
`viewer.js` を直接 require し、DOM 側は `__tests__/support/viewerMainHarness.js` が
esbuild でテスト用エントリを IIFE にまとめて jsdom の `window.eval` で評価する。

## Node バージョン

`.nvmrc` と `package.json` の `engines.node` で 24 に揃える（CI の js-test ジョブが
Node 24 固定のため）。esbuild は `package.json` で exact 指定しており、同一版なら
出力はバイト単位で決まる。
