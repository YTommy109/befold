---
id: TASK-538
title: 医療費控除のユースケース記事を紹介サイトに公開する
status: To Do
assignee: []
created_date: '2026-08-22 13:04'
updated_date: '2026-08-23 12:23'
labels: []
milestone: m-10
dependencies: []
priority: medium
ordinal: 782000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
「プログラムを書かず Claude だけで医療費控除の準備を回す」実運用を、befold のユースケース記事として紹介サイトに載せる。スマホで領収書をスキャンして投げ込むだけで、年末に医療費控除の明細書へ転記できる状態が保たれる、という筋書き。

## なぜやるか

- befold の適性が題材から自然に出てくる。元になった運用文書は『集計表を Numbers で開いて保存し直すと書式（先頭ゼロ・日付形式）が変わる』という問題を自分で書いており、**壊さずに見るだけのビューア**という befold の立ち位置がそのまま答えになる
- TSV のテーブル表示・領収書 PDF・Markdown の閲覧が 1 つの題材に全部登場する
- 『プログラムを書かずに Claude で業務を回す』例として、befold 以外の層にも届く

## 素材

作者が iCloud Drive 上で実運用している医療費記録の CLAUDE.md / README.md（365 行）。フォルダ構成・TSV 仕様・命名規約に加えて『なぜこの構成にしたか（検討の記録）』まで揃っている。

**実ファイルはリポジトリ外（iCloud Drive）にあり、確認用に site/temp へ一時コピーされた。個人情報を含むため、そのままの掲載はしない。**

## 決めた方針（2026-08-22 のユーザー確認）

- 掲載は**実ファイルを参考にした要所絞り込み版を新規に書き起こす**。全文転載はしない
- 家族構成は表に出さない。**架空の 4 人家族**を想定する
- Dropbox / iCloud の比較検討の節は落とす（焦点がぶれる。メールアドレスと法人フォルダの記述もある）
- 公開時期は問わない。完成次第
- befold の見せ場は 3 つ: (a) TSV を壊さずに表で見る (b) 領収書 PDF をすぐ確かめる (c) README/CLAUDE.md を読みやすく読む
- **Zola は導入しない**（別タスクの Notes に根拠）

## 注意

差分表示は使えない題材（iCloud Drive のフォルダで git 管理外）。記事で触れないか、『git 管理下のプロジェクトなら』と切り分ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 記事が公開され、紹介サイトから到達できる
- [x] #2 掲載物に実在の氏名・医療機関名・住所・電話番号・メールアドレスが含まれない
- [x] #3 読者が手元で再現できる形（テンプレートとして持ち帰れる）になっている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
参照用の実データ（site/temp）の後始末は TASK-538.5 で追跡する。記事が完成しても、そちらが Done になるまで作業は終わっていない。

## 実行順（2026-08-22 ユーザー指示で変更）

**site/temp をコミットしたくない**ため、公開版の文書を書き起こす TASK-538.2 を最優先にし、その完了で site/temp を消せるようにした。動作確認は後回しで、食い違いが出たら文書側を直す。

1. **TASK-538.2** 公開版 CLAUDE.md / README.md を書き起こす（site/temp を参照する最後の作業）
2. **TASK-538.5** site/temp を削除する → ここで初めてコミットする
3. **TASK-538.1** 記事の器を用意する（538.2 とは独立。並行してよい）
4. **TASK-538.3** 架空データで一巡し、食い違いがあれば公開版の文書を直す
5. **TASK-538.4** 記事本文を書いて公開する

TASK-538.1 だけは site/temp と無関係なので、いつ着手してもよい。

## 親タスクの受入条件を本番で確認した（2026-08-23）

`https://befold.degino.com` 上で実測し、AC #1〜#3 をチェック済みにした。

- AC #1: `/usecases` と `/usecases/medical-expenses` が 200。記事一覧に `href="/usecases/medical-expenses"` のリンクが出る
- AC #2: 掲載内容は TASK-538.3 の架空データ（北原家）由来。実在の氏名・医療機関名・住所・電話番号・メールアドレスは含まない（TASK-538.4 の Notes を参照）
- AC #3: `/templates/medical-expenses/README.md` と `/templates/medical-expenses/CLAUDE.md` がどちらも 200 で配信され、テンプレートとして持ち帰れる

**残っているのは TASK-538.4 の AC #6（公開後の analytics 計上確認）だけ。** 読み取り専用トークンの失効で止まっている（詳細と再開条件は TASK-538.4 の Notes）。
<!-- SECTION:NOTES:END -->
