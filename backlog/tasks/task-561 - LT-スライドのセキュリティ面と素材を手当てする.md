---
id: TASK-561
title: LT スライドのセキュリティ面と素材を手当てする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-27 14:55'
updated_date: '2026-08-27 15:03'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 811000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-560 で作った `sample/presentation/` の LT スライドについて、自己点検で出た手当てをまとめる。

## 1. 画像の権利（対応済み）

`images/befold-image.jpg` が macOS 標準壁紙（`DefaultAerial.heic`）のスクリーンショットだった。公開リポジトリに入り登壇でも映るため、作者が撮影した写真（札幌・北 3 条広場）へ差し替える。

## 2. 各ページに自前の CSP（未着手・要判断）

`.html` は `DirectHTMLModeController` が `loadFileURL` で直接読むため、**viewer.html の meta CSP も DOMPurify も掛からない**。現状デッキに `<script>` / `on*=` / `http(s)://` は 0 件（実測）で無害だが、自分で締めておける。

```html
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; img-src 'self'; style-src 'self' 'unsafe-inline'">
```

`'unsafe-inline'`（style）が要るのは進捗バーの幅を `style="width: ..."` のインライン属性で持たせているため。ページごとのクラスに移せば外せる。

## 3. QuickLook のスクリーンショット撮り直し（未着手・要判断）

`images/befold-quicklook.png` は QuickLook パネルの半透明越しに、背後の Finder の行と別ウィンドウがぼけて写っている。等倍では判読不能だが拡大すると Finder の列が薄く見える。クリーンなデスクトップで撮り直すのが確実。

## 背景

TASK-560 のデッキを作ったあと、「secure がアピールポイントでは」という相談の中で、デッキ自身を点検して出てきた 3 点。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 images/befold-image.jpg が権利の所在の明確な写真になっている
- [x] #2 各ページが自前の CSP を宣言している（または宣言しない判断が Notes に残っている）
- [x] #3 QuickLook のスクリーンショットに他人の画面が写り込んでいない（または現状で可とした判断が Notes に残っている）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 1. 画像の差し替え（完了）

作者提供の写真（1280x960、札幌・北 3 条広場）を befold で開いて撮り直し、`images/befold-image.jpg` を置き換えた（272KB）。README の出どころの表も更新。撮影後の画像を Read して目視確認済み。

残る 2 件（CSP・QuickLook 撮り直し）は未着手。

## 2. CSP（完了）

全 22 ページの `<meta charset>` 直後に次を置いた。

```html
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self'; style-src 'self'; base-uri 'none'; form-action 'none'">
```

`'unsafe-inline'` を足さずに済ませるため、唯一のインライン `style` 属性だった進捗バーの幅を `.progress.p01` 〜 `.p22` のクラスへ移した（`rg -o 'style="[^"]*"'` の結果が 0 件になったことを確認）。

### 実測（2026-08-28 / befold 1.15.0 / 直接 HTML モード）

**当初の検証は空振りだった。** インライン `<script>` を仕込んだ使い捨てページで「CSP ありならスクリプトが動かない」ことを見ようとしたが、**CSP を外した対照でもスクリプトは動かなかった**。原因は `DirectHTMLModeController.enter` が `webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = false` を設定していること（コードで確認）。つまり直接 HTML モードでは JS がそもそも無効で、この実験では CSP の効き目を判定できない。

JS を使わない判定へ切り替え、`<iframe src="02-editing.html">` を置いたページを CSP の有無だけ変えて描いた:

| 条件 | 結果 |
|---|---|
| CSP 無し | iframe に 02 ページが描画される |
| CSP 有り | iframe は空（`default-src 'none'` により frame が読めない） |

**CSP は実際に効いている**と確定。加えて実ページ（01 / 12）を CSP 付きで描き、`style.css` と `images/*` が問題なく読めることも目視確認した（`img-src 'self'` / `style-src 'self'` が file:// のローカル資源を弾かない）。

## 3. QuickLook の撮り直し（不要と判断）

ユーザー判断（2026-08-28）: 背後に写っているのはこの OSS 開発中の Warp の画面であり、問題ない。QuickLook の半透明らしさが出ていて良い、とのこと。撮り直さない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LT スライドの素材とセキュリティ面を手当てした。写真を権利の明確なもの（作者撮影）へ差し替え、全 22 ページに自前の CSP を宣言し、インライン style 属性を廃してクラス化した。CSP が実際に効いていることは iframe を使った対照実験で確定（当初の script を使った検証は、直接 HTML モードで JS が元から無効なため空振りだった）。QuickLook の撮り直しはユーザー判断で不要。
<!-- SECTION:FINAL_SUMMARY:END -->
