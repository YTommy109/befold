# site/tools

配布サイトのビルド時には使わない、手作業用のツールを置く。

## ogp-template.html

OGP 画像 `public/images/ogp.png` の元テンプレート。
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
