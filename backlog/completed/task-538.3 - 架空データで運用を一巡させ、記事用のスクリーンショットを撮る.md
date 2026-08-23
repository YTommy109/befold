---
id: TASK-538.3
title: 架空データで運用を一巡させ、記事用のスクリーンショットを撮る
status: Done
assignee:
  - '@claude'
created_date: '2026-08-22 13:06'
updated_date: '2026-08-22 14:27'
labels: []
milestone: m-10
dependencies:
  - TASK-538.2
parent_task_id: TASK-538
priority: medium
ordinal: 785000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
記事に載せる素材を作る。同時に、**書いた手順が実際に通ることを確かめる**（ユーザーは『実際に動かしていない点に不安がある』と述べている。読者は手順どおりに試すので、未検証のまま出さない）。

## 一巡させる内容

架空の 4 人家族ぶんのサンプルで、README に書いた手順をそのまま実行する。

1. 領収書 PDF を用意する（架空の医療機関・金額。スキャン風の画像 PDF にすること——テキスト層があると読み取り手順の意味が変わる）
2. pdfimages で画像を取り出し、Pillow の ImageOps.autocontrast で整えて読む
3. 複数枚まとめた PDF を pypdf で分割する
4. data/medical-YYYY-氏名.tsv へ追記し、receipts/YYYY/氏名/ へリネームして移す
5. providers.md へ支払先を追記する

手順が実際と食い違ったら、TASK-538.2 の文書側を直す。

## スクリーンショット（befold の見せ場 3 つ）

- TSV のテーブル表示（Numbers で開かずに集計表を確認する）
- 領収書 PDF のプレビュー（集計表の receipt 列から対応する PDF を確かめる。サイドバーでフォルダをたどる様子も入れる）
- README / CLAUDE.md の Markdown 表示

差分表示は題材が git 管理外（iCloud Drive）なので使わない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 架空データで README の手順を一巡させ、通らなかった箇所は文書側を修正してある
- [x] #2 befold の見せ場 3 つのスクリーンショットが揃っている
- [x] #3 スクリーンショットに実在の氏名・医療機関名・金額・パスが写り込んでいない
- [x] #4 サンプルデータ一式が、記事から持ち帰れる形（または再現手順）で残っている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. スクラッチパッドに venv を作り pillow / pypdf を入れる
2. 架空の領収書を画像として描き、テキスト層を持たない PDF にする（複数枚まとめた 1 ファイルを含める）
3. README の手順どおりに pdfimages -j → Pillow の autocontrast → pypdf 分割を実行し、通るかを実測する
4. 架空 4 人家族のサンプルツリー（data/ receipts/ docs/ Inbox/ trash/）を組み立てる
5. 食い違いがあれば README を直す
6. サンプルの再現手順をスクリプトとして残す
7. befold で開いてスクリーンショットを撮る（GUI 操作が要る部分はユーザーに依頼する）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## site/temp はこの時点で存在しない（2026-08-22）

実行順を変更したため、このタスクに着手する頃には参照用の実データ（site/temp）は削除済み（TASK-538.5）。**元の運用文書は参照できない前提で進める。**

このタスクは『TASK-538.2 が書いた公開版の手順が実際に通るか』を確かめるもので、通らなければ**直すのは公開版の CLAUDE.md / README.md の側**。元文書との突き合わせではない。

未検証の手順が一時的に文書へ載ることは許容している（公開は TASK-538.4 なので、外に出る前に直せる）。

## 実測の結果（2026-08-22）

架空の 4 人家族（北原 健吾 / 沙織 / 悠真 / 芽衣）で README の手順を最後まで実行した。生成物・スクリーンショットとも実在の情報は含まない。

### 通ったもの

- **pdfimages -j**: 2 ページの画像 PDF から `i-000.jpg` / `i-001.jpg` を 0.32 秒で取り出せた。対象にテキスト層が無いことは `pdftotext` の出力が 0 バイトであることで確認
- **Pillow の autocontrast**: 輝度域が (19,255) → (0,255) / (39,255) → (0,255) に広がった。1150px へ縮小した画像を実際に読み、患者氏名・調剤日・領収金額・内訳まで判読できることを確認した（記載どおり読める）
- **取り込み一巡**: receipts/YYYY/氏名/ へのリネーム移動、trash/ への退避、集計表への日付順追記まで通った

### 通らなかったもの（文書を修正）

1. **pypdf のコード片が単体で動かなかった。** `r` が未定義（`NameError: name 'r' is not defined`）で、書き出しも無かった。`PdfReader` の生成と `open(..., "wb")` での書き出しを補い、出力先を receipts/ の実際のパスにした
2. **Pillow の手順が sh のコメントとして書かれていた。** 実行できる Python コードに書き換え、`pdfimages` の出力が `/tmp/i-000.jpg` のように連番になることも明記した

### 成果物

- スクリーンショット 3 枚: `site/public/images/usecase-medical-{tsv,receipt,readme}.png`（各 1512x949、43〜144KB。既存の screenshot-*.png が 1280x800・77〜196KB なので同程度に収めた）
- 再現スクリプト: `scripts/make-medical-sample.py`。`scripts/make-git-demo-repo.sh`（配布サイトの git スクリーンショット用に使い捨てリポジトリを作るもの）と同じ役割・同じ置き場に揃えた。まっさらな出力先で実行し直して動作を確認済み

### スクリーンショット撮影で分かったこと

`osascript` の `front window` は**開いている befold ウィンドウのうち意図したものを指すとは限らない**。実際、TSV のウィンドウを撮ろうとして別のドキュメントのウィンドウを移動させてしまった（位置は元に戻した）。CGWindowID を取って `screencapture -l <id>` で撮る方法に切り替えたところ、ウィンドウ枠ぴったりで安定して撮れた。今後 GUI のスクリーンショットが要るときはこちらを使う。

### 起票時の記述との差

Description の手順 5「providers.md へ支払先を追記する」は、TASK-538.2 のレビューで providers.md 自体を落としたため実施しない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
架空の 4 人家族で README の手順を一巡させ、スクリーンショット 3 枚と再現スクリプトを残した。

検証で 2 件の欠陥が見つかり、いずれも文書側を修正した。(1) pypdf のコード片が r 未定義で動かず書き出しも無かった、(2) Pillow の手順が実行できない sh コメントだった。修正後、pdfimages → autocontrast → 1150px 縮小 の流れで生成した画像を実際に読み、患者氏名・日付・金額まで判読できることを確認している。

成果物: site/public/images/usecase-medical-{tsv,receipt,readme}.png（1512x949、43〜144KB）と scripts/make-medical-sample.py（まっさらな出力先で再実行して動作確認済み）。

検証: markdownlint-cli2 がリポジトリ全体で 0 issues。pdftotext でテキスト層が無いことを確認。生成物・スクリーンショットに実在の氏名・医療機関名・住所・電話番号は含まれない。
<!-- SECTION:FINAL_SUMMARY:END -->
