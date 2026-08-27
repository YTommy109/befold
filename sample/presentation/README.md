# LT スライド（befold の紹介）

befold 自身で映すことを前提にした LT 資料。**1 ページ 1 ファイル**の HTML で、
ファイル名の連番がそのまま進行順になる。

## 映し方

```bash
befold sample/presentation --sidebar   # フォルダごと開く
```

サイドバーで `01-intro.html` を選び、**サイドバーにフォーカスを置いたまま `j` / `k`**
（または ↓ / ↑）で送る。⌃⌘F の全画面にすると画面いっぱいに出る。

**ツールバーの ← → は「次のファイル」ではなく履歴の戻る/進む**（⌘[ / ⌘]）なので、
まだ開いていないページへは進めない。サイドバーを閉じたまま順送りする手段は
現時点では無い。

## 作りの決まり

- **各ページの先頭に `<meta charset="utf-8">` を必ず置く。** befold は charset 宣言の
  ある HTML だけを `loadFileURL` で直接読み、そのときだけ同じフォルダの
  `style.css` と `images/` を参照できる。宣言が無いと `loadData` へ倒れて兄弟
  リソースが読めなくなり、**文字だけのページになる**。
- **外部から何も読み込まない。** リモート読み込みは `RemoteLoadBlocker` が遮断する
  ので、Web フォント・CDN は使わない（本文は system-ui、等幅は SF Mono / Menlo）。
- 見た目は `style.css` の 1 枚に集約する。ページ側は本文と、`.tag` / `.pager` /
  `.progress` の 3 つの位置情報（何ページ目か）だけを持つ。
- 文字サイズは `vmin` と `clamp()` で決めてあるので、ウィンドウの大きさに追随する。

## 画像の出どころ

| ファイル | 出どころ |
| --- | --- |
| `ogp.png` `markdown.png` `code.png` `diff.png` `csv.png` | `site/public/images/` の配布サイト用スクリーンショット |
| `pdf.png` | 同上（医療費控除の記事で使っている PDF 表示の画面） |
| `appicon.png` | `befold.app` の `AppIcon.icns` を `sips` で書き出したもの |
| `befold-image.jpg` | befold で写真（macOS の標準壁紙）を開いた画面 |
| `befold-quicklook.png` | Finder で `sample/flowchart.mmd` を選び Space を押した QuickLook |

配布サイト側のスクリーンショットを撮り直したら（`scripts/capture-screenshots.applescript`）、
ここへコピーし直す。**同じ画像を 2 箇所に置いている**のは、資料をフォルダごと
持ち出せるようにするため。
