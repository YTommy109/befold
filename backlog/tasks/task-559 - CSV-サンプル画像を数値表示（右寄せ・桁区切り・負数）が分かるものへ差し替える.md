---
id: TASK-559
title: CSV サンプル画像を数値表示（右寄せ・桁区切り・負数）が分かるものへ差し替える
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-27 11:51'
updated_date: '2026-08-27 11:52'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 809000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布サイトのカルーセルの CSV 画像（`site/public/images/screenshot-4.png`）は `sample/sample.csv` を撮ったもので、TASK-557 で入れた数値表示（右寄せ・桁区切り・負の数の表記）が伝わらない。

撮影対象を `sample/numeric-columns.csv` へ移し、負の数の表記は撮影時だけ ▲+赤字（`triangleRed`）に固定する。既定の `plain`（-1,234）だと「負の数の見せ方を選べる」ことが画像から読み取れないため（ユーザー判断、2026-08-27）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 screenshot-4.png が右寄せ・桁区切り・負の数（▲+赤字）を含む表を写している
- [x] #2 コード列（得意先コード・郵便番号・年度・伝票番号）に桁区切りが入っていないことが同じ画像で分かる
- [x] #3 撮影スクリプトを引数なしで回しても同じ画像が再現できる（負数スタイルの設定がスクリプト側にある）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## やったこと

- `scripts/capture-screenshots.applescript`: 4 番の対象を `sample.csv` → `numeric-columns.csv` へ。あわせて撮影前に `CsvNegativeStyle=triangleRed` と `CsvNumberGrouping=true` を `defaults write` する（`SourceDiffLayout` と同じ扱い。撮影が実行環境の既定値に依存しないようにするため）
- `sample/numeric-columns.csv`: 10 行 → 22 行へ拡張。**旧画像（sample.csv・22 行）が窓を埋めていたのに対し、10 行では下半分が空いたため**。列判定の性質は保っている——伝票番号は連番、得意先コードは 5 桁固定、郵便番号は 7 桁で先頭ゼロあり、年度は 2024〜2026、前年比は 1,000 未満の小数。したがって TASK-557.1 の 6 つの拒否条件の実測例はそのまま残る
- `site/public/images/screenshot-4.png` を撮り直し

## 検証

- 撮影後の画像を Read して目視確認（メモリ `screenshot-capture-needs-attended-session` のとおり `defaults read -g` ではなく画像で確かめた）: ダークテーマ、右寄せ、1,284,000 などの桁区切り、▲500 の赤字、そして**得意先コード・郵便番号・年度・伝票番号には桁区切りが入っていない**ことを確認
- 撮影は引数 4 を指定（引数なしだと 1〜6 も撮り直され、アンチエイリアスの差で無関係な差分が出る）
- `rg` で `numeric-columns` の参照を確認: 撮影スクリプトと backlog のみで、テストからは参照されていない
- **未実行**: `BefoldApp` の jest（`node_modules` が未インストール）。今回の差分は sample データと AppleScript だけで JS コードに触れていないため、CI の js-test に委ねる

## 環境について 1 点

このセッションでは `screencapture` も System Events も許可済みで、**Claude のセッションから撮影できた**（メモリ `screenshot-capture-needs-attended-session` は「バックグラウンドジョブからは不可」と記録していたが、対話セッションかつ許可済みの端末では回せる）。外観もダーク固定だった。

撮影スクリプトが `defaults write` するため、**実行後のアプリは負の数が ▲+赤字のまま**になる。既定へ戻すなら `defaults delete com.degino.befold CsvNegativeStyle`。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
撮影対象を numeric-columns.csv へ移し、負数スタイルを撮影スクリプト側で triangleRed に固定して screenshot-4.png を撮り直した。窓を埋めるためサンプルを 22 行へ拡張（列判定の拒否条件の実例は保持）。画像を目視確認し、右寄せ・桁区切り・▲赤字と、コード列に桁区切りが入らないことを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
