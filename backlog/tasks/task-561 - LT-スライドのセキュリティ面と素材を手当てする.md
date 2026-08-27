---
id: TASK-561
title: LT スライドのセキュリティ面と素材を手当てする
status: In Progress
assignee:
  - '@Tommy109'
created_date: '2026-08-27 14:55'
updated_date: '2026-08-27 14:55'
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
- [ ] #1 images/befold-image.jpg が権利の所在の明確な写真になっている
- [ ] #2 各ページが自前の CSP を宣言している（または宣言しない判断が Notes に残っている）
- [ ] #3 QuickLook のスクリーンショットに他人の画面が写り込んでいない（または現状で可とした判断が Notes に残っている）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 1. 画像の差し替え（完了）

作者提供の写真（1280x960、札幌・北 3 条広場）を befold で開いて撮り直し、`images/befold-image.jpg` を置き換えた（272KB）。README の出どころの表も更新。撮影後の画像を Read して目視確認済み。

残る 2 件（CSP・QuickLook 撮り直し）は未着手。
<!-- SECTION:NOTES:END -->
