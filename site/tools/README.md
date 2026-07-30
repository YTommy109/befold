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
