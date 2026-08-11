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
| `index.js` | バンドルのエントリ。`exposeGlobals()` で公開関数をグローバルへ載せ、`_mmdInit()` を呼ぶ |
| `main.js` | 公開面の barrel。エントリもテストハーネスもここだけを見る |
| `expose.js` | barrel の export を反復して `globalThis` へ公開する `exposeGlobals()` |
| `init.js` | 読み込み時の初期化（リスナ登録・注入値の反映）を 1 箇所に集約する |
| `bridge.js` | Swift ホストとの境界。`postMessage` の送信口とホスト機能フラグ |
| `render.js` | 描画の入口とチャンク追記のディスパッチ。「いま何の形を描いたか」の記録を持つ |
| `renderers.js` | 表示種別ごとの `#diagram-wrap` 組み立て |
| `document-state.js` | 直近に描画した内容とチャンク境界を保持する |
| `view-options.js` | 表示モード・行番号・差分の設定を保持する |
| `doc-path.js` | いま DOM に出ている文書のパスを追跡する |
| `scroll.js` | スクロール対象の決定・位置の復元・位置変化の通知 |
| `keyboard.js` | キーボード操作の配線と、キーからスクロール量を決める規則 |
| `zoom.js` | 全体ズームとダイアグラム個別ズームの倍率保持と DOM への適用 |
| `find.js` | 検索バーの状態・ハイライト・件数表示 |
| `path-refs.js` | 本文中のパス参照の注釈付けと Swift への解決要求 |
| `reference-clicks.js` | リンク/パス参照のクリック・コンテキストメニューを Swift へ伝える |
| `truncation.js` | 段階読み込みバナーと「続きを読み込む」 |
| `markdown.js` | markdown-it インスタンスの構成 |
| `mermaid.js` | mermaid の遅延ロード・設定・実行 |
| `color-scheme.js` | ダークモードの現在値と変更通知 |
| `fonts.js` | Swift が注入したフォント設定を CSS 変数へ反映する |
| `code-html.js` | ソースコードのハイライトと行単位 HTML の組み立て |
| `diff-html.js` | unified diff の解析とインライン/左右分割の HTML 組み立て |
| `csv-html.js` | CSV/TSV の解析とテーブル/ソース表示の HTML 組み立て |
| `encoding.js` | HTML エスケープと data URI / base64 の変換 |

依存は `import` で表現し、**循環させない**（`npm run check:viewer-cycles`）。
循環するとモジュール評価順が壊れ、別モジュールのトップレベル値を `undefined` の
まま掴む。実際に `scroll.js` は評価時に `doc-path.js` の `_mmdDocPath` を読む。

Swift 側は `evaluateJavaScript("_mmdZoomIn()")` のような裸の呼び出しで到達するため、
バンドル（IIFE）の中身は `exposeGlobals()` でグローバルへ載せ直す。`export` した
時点で載るので、公開関数を増やすときの追記漏れは起きない。

`viewer.html` は body 末尾で **markdown-it → highlight.js → DOMPurify →
viewer-bundle.js** の順に読む。ベンダーライブラリはバンドルに含めず、グローバル参照
のまま使う。mermaid（3.2MB）はさらに遅く、描画が必要になった時点で
`mermaid.js` が動的に `<script>` を挿して遅延ロードする。CSP は
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
npm run check:viewer-cycles  # モジュール間の循環 import を検出する
npx jest                     # Jest テスト（BefoldKit/Resources/__tests__/）
```

`check:viewer-bundle` はローカルでも CI と同じコマンドで確認できる。差分が出たら
`npm run build:viewer` の結果をコミットする。

テストは成果物ではなくこのディレクトリのソースを対象にする。DOM を要さない純粋関数は
`main.js` を直接 require し、DOM 側は `__tests__/support/viewerMainHarness.js` が
esbuild でテスト用エントリを IIFE にまとめて jsdom の `window.eval` で評価する。

## Node バージョン

`.nvmrc` と `package.json` の `engines.node` で 24 に揃える（CI の js-test ジョブが
Node 24 固定のため）。esbuild は `package.json` で exact 指定しており、同一版なら
出力はバイト単位で決まる。
