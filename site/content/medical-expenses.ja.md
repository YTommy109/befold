医療費控除に必要な家族全員の医療費の集計をどうやってますか? 私は今まで表計算ソフトに手入力してました。が、これからは違います。

領収書をもらったらスマートフォンでスキャンして、フォルダーに入れるだけです。あとは Claude に取り込みを頼むと、フォルダーに整理して、一覧表を作ってくれます。私が動かしている [CLAUDE.md](/templates/medical-expenses/CLAUDE.md)、[README.md](/templates/medical-expenses/README.md) はこちらです。

### 家族への説明も簡単

先に iCloud Drive へ「医療費」フォルダとその中の「Inbox」を作り、**Inbox を家族と共有しておきます**。準備はこれだけです。

> 病院や薬局の領収書をもらったら、iPhone の「ファイル」アプリで「Inbox」を開いて、右上の … から「書類をスキャン」。撮って保存するだけ。ファイル名はなんでもいい。

<figure class="article-shots portrait"><img src="/images/usecase-medical-scan-ja.png" alt="iPhone の「ファイル」アプリでフォルダを開き、右上のメニューを出したところ。「書類をスキャン」が並んでいる" loading="lazy" width="571" height="1242"/></figure>

### 月末に 1 回、こう頼む

> Inbox の新しいスキャンを読んで、集計表に追記して、receipts/ にリネームして移して。

起きることはこれだけです。

1. Inbox の未処理ファイルから、日付・医療機関・金額・対象者・区分を読み取る
2. 年 × 人ごとの集計表（TSV）へ日付順に追記する
3. スキャンを「日付_医療機関名_対象者_金額.pdf」にリネームし、receipts/ の年・人のフォルダへ移す
4. 読み取れなかったもの、対象者が判別できないものは報告する（推測で埋めない）

手順と TSV の仕様はフォルダの中の README.md と CLAUDE.md に書いてあるので、毎回説明し直す必要はありません。

### 読み違いに気づけるのは人だけ

読み取れなかったものは報告されますが、読み違えには気づけません。金額の桁、似た日付、家族の取り違え。ここだけは人が突き合わせます。befold なら 1 つのウィンドウで済みます。

#### 1. 表計算ソフトで開かずに TSV を読む

集計表はタブ区切りのテキストで、befold で開くと表として並びます。表計算ソフトで開いて保存し直すと、先頭ゼロが落ちたり日付の形式が変わったりします。次に読むのは LLM なので、黙って壊れます。見るのはビューア、直すのは依頼。

<figure class="article-shots"><img src="/images/usecase-medical-tsv.png" alt="集計表の TSV が befold で表として表示されている。date・person・provider・amount・receipt の列が並ぶ" loading="lazy" width="1512" height="949"/></figure>

#### 2. 集計表から領収書をすぐ確かめる

receipt 列にはファイル名が入っています。サイドバーからその PDF を開いて、金額と日付を原本と突き合わせます。直されればウィンドウはその場で更新されるので、開き直す必要はありません。

<figure class="article-shots"><img src="/images/usecase-medical-receipt.png" alt="スキャンした領収書の PDF が befold でプレビューされている" loading="lazy" width="1512" height="949"/></figure>

#### 3. LLM 向けの規約を、人が読む

README.md と CLAUDE.md は LLM に読ませるものですが、仕組みを忘れるのは人のほうです。半年ぶりに「交通費はどう書くんだったか」を確かめるとき、整形された Markdown で読めると速い。

<figure class="article-shots"><img src="/images/usecase-medical-readme.png" alt="運用手順を書いた README.md が befold で表示され、サイドバーにフォルダ構成が並んでいる" loading="lazy" width="1512" height="949"/></figure>

### テンプレート

そのままコピーして使えます。氏名・医療機関名・住所・電話番号はすべて記入例で、実在しません。この記事のスクリーンショットも同じ架空データです。

- [README.md](/templates/medical-expenses/README.md) — フォルダ構成・運用手順・TSV の仕様
- [CLAUDE.md](/templates/medical-expenses/CLAUDE.md) — LLM 向けの入口。README を読ませ、推測で埋めさせない

### 知っておくとよいこと

- 紙の領収書は捨てません。提出・提示は不要になりましたが、自宅で 5 年間保存する義務があります。
- 集計表の区分は明細書の 4 区分（診療・治療／医薬品購入／介護保険サービス／その他の医療費）に合わせてあります。年末にそのまま転記できます。
- befold は読むための道具で、編集はできません。直すのは LLM の仕事です。

<p class="listing-note">※ この記事は税務のアドバイスではありません。控除の対象や保存義務の扱いは変わることがあります。最終的な判断は国税庁の情報を確認し、迷うものは税務署に問い合わせてください。</p>

<ul class="listing-note"><li><a href="https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/1119_qa.htm">No.1119 医療費控除に関する手続について｜国税庁</a></li><li><a href="https://www.nta.go.jp/taxes/shiraberu/shinkoku/tebiki/2025/06/6_01.htm">医療費控除の明細書｜国税庁</a></li></ul>

### befold を使ってみる

{{cta}}
