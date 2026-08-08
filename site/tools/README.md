# site/tools

配布サイトのビルド時には使わない、手作業用のツールを置く。

## ogp-template.html

OGP 画像 `public/images/ogp.png` の元テンプレート。
右側に置くアプリ画面は `ogp-screenshot.png`（1280×800）で、これも
このディレクトリにある。LP のカルーセル用スクリーンショットとは
用途が違う（あちらは形式ごとの紹介、こちらは Markdown に Mermaid を
埋め込んだ「よくある読み物」の絵）ので流用せず別に持つ。

中身を変えたら、以下を実行して PNG を作り直しコミットする。

    cd site
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
      --headless --disable-gpu --hide-scrollbars \
      --screenshot=public/images/ogp.png \
      --window-size=1200,630 \
      --default-background-color=ffffff \
      "file://$(pwd)/tools/ogp-template.html"

    sips -g pixelWidth -g pixelHeight public/images/ogp.png

サイズは必ず 1200×630 であること。Worker の実行時には一切関与しない。

## ogp-preview.html

再生成した `ogp.png` が各 SNS でどう切り抜かれるかを並べて確認するページ。

    open tools/ogp-preview.html

枠は近似なので、実際の切り抜きを保証するものではない。文字が切れないか、
小さいサムネイルでも読めるかを素早く見るために使う。最終確認は
デプロイ後の URL を各 SNS のカードデバッガに入れて行う。

## seed-local.mjs

ローカル D1 にダッシュボード確認用のサンプルデータを入れる。

    npm run seed:local

空の DB だとグラフが「期間内のデータなし」にしかならず、レイアウトやラベルの
見え方を確認できないため。ローカル D1 は `site/.wrangler` 配下にあり
**worktree ごとに別**なので、worktree を切るたびに実行する。

- 生成は決定的（固定シードの xorshift）。日付だけは実行時刻から逆算する。
  日別推移の窓が「当日を含む直近 14 日」なので、固定日付にするとすぐ窓から
  外れて何も表示されなくなる
- 実行のたびに `DELETE FROM events` してから入れ直す（何度実行しても同じ状態）
- 対象は `--local` のみ。リモート D1 には触れない
- クライアント種別に `ClaudeBot` / `GPTBot` を混ぜてある。AI クローラの内訳が
  実運用でどう見えるかを確かめるため
