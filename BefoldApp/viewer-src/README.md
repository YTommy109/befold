# viewer-src

viewer 用 JS のモジュールソース。`npm run build:viewer` が esbuild で
`BefoldKit/Resources/viewer-bundle.js` へバンドルし、**成果物もリポジトリへコミットする**。

<!-- derived-from ../../backlog/tasks/task-432.1 - esbuild-のビルド経路と成果物コミットの仕組みを最小構成で通す.md -->

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
```

`check:viewer-bundle` はローカルでも CI と同じコマンドで確認できる。差分が出たら
`npm run build:viewer` の結果をコミットする。

## Node バージョン

`.nvmrc` と `package.json` の `engines.node` で 24 に揃える（CI の js-test ジョブが
Node 24 固定のため）。esbuild は `package.json` で exact 指定しており、同一版なら
出力はバイト単位で決まる。
