# LT スライド（befold の紹介）

befold 自身で映すことを前提にした LT 資料。**1 ページ 1 ファイル**の HTML で、
ファイル名の連番がそのまま進行順になる。

## 映し方

```bash
befold sample/presentation --sidebar   # フォルダごと開く
```

サイドバーで `01-intro.html` を選び、以降はツールバーの ← → （次のファイル / 前の
ファイル）で送る。全画面にすると画面いっぱいに出る。

## 作りの決まり

- **各ページの先頭に `<meta charset="utf-8">` を必ず置く。** befold は charset 宣言の
  ある HTML だけを `loadFileURL` で直接読み、そのときだけ同じフォルダの
  `style.css` と `images/` を参照できる。宣言が無いと `loadData` へ倒れて兄弟
  リソースが読めなくなり、**文字だけのページになる**。
- **外部から何も読み込まない。** リモート読み込みは `RemoteLoadBlocker` が遮断する
  ので、Web フォント・CDN は使わない（本文は system-ui、等幅は SF Mono / Menlo）。
- **各ページが自前の CSP を宣言する。**

  ```html
  <meta http-equiv="Content-Security-Policy" content="default-src 'none';
        img-src 'self'; style-src 'self'; base-uri 'none'; form-action 'none'">
  ```

  直接 HTML モードは viewer.html を経由しないため、**同梱 viewer.html の CSP も
  DOMPurify も掛からない**。締めるのはこの資料自身の仕事になる。実測（2026-08-28、
  befold 1.15.0）: CSP の有無だけを変えて `<iframe src="02-editing.html">` を置いた
  ページを描くと、**CSP 無しでは中身が描画され、CSP 有りでは空**になる。つまり宣言は
  実際に効いている。
- **インライン `style` 属性を使わない。** 進捗バーの幅はページごとのクラス
  （`.progress.p01` 〜 `.p22`）で持つ。属性で書くと `style-src` に
  `'unsafe-inline'` を足すことになるため。
- なお **直接 HTML モードでは JS がそもそも無効**（`DirectHTMLModeController.enter`
  が `allowsContentJavaScript = false` にする）。上の CSP は多層防御の 1 枚で、
  この資料は JS を 1 行も使わない。
- 見た目は `style.css` の 1 枚に集約する。ページ側は本文と、`.tag` / `.pager` /
  `.progress` の 3 つの位置情報（何ページ目か）だけを持つ。
- 文字サイズは `vmin` と `clamp()` で決めてあるので、ウィンドウの大きさに追随する。

## 画像の出どころ

| ファイル | 出どころ |
| --- | --- |
| `ogp.png` `markdown.png` `code.png` `diff.png` `csv.png` | `site/public/images/` の配布サイト用スクリーンショット |
| `pdf.png` | 同上（医療費控除の記事で使っている PDF 表示の画面） |
| `appicon.png` | `befold.app` の `AppIcon.icns` を `sips` で書き出したもの |
| `befold-image.jpg` | befold で写真を開いた画面。写真は作者が撮影したもの（札幌・北 3 条広場）で、権利の所在をはっきりさせるため素材サイトや OS 同梱の壁紙は使わない |
| `befold-quicklook.png` | Finder で `sample/flowchart.mmd` を選び Space を押した QuickLook |

配布サイト側のスクリーンショットを撮り直したら（`scripts/capture-screenshots.applescript`）、
ここへコピーし直す。**同じ画像を 2 箇所に置いている**のは、資料をフォルダごと
持ち出せるようにするため。
